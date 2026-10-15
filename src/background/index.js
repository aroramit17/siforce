// Service worker: one conversation per Salesforce tab. The content script in
// the tab connects over a port; if the tab reloads (e.g. after navigating to a
// new record), the conversation survives and is replayed to the new panel.

import { AgentError, runAgentTurn } from './agent.js';
import { SalesforceClient } from './salesforce.js';
import { loadSettings } from '../shared/settings.js';

const sessions = new Map(); // tabId -> session

function getSession(tabId) {
  if (!sessions.has(tabId)) {
    sessions.set(tabId, {
      history: [], // Claude messages
      transcript: [], // display events, replayed after a reload
      port: null,
      busy: false,
      abort: null,
      confirms: new Map(), // id -> resolve
    });
  }
  return sessions.get(tabId);
}

const REPLAYED = new Set(['user', 'assistant', 'record_link', 'error']);

function emitter(session) {
  return (event) => {
    if (REPLAYED.has(event.type)) session.transcript.push(event);
    try {
      session.port?.postMessage(event);
    } catch {
      // Port closed mid-turn (tab reloading); the transcript replays on reconnect.
    }
  };
}

function resolveConfirms(session, answer) {
  for (const resolve of session.confirms.values()) resolve(answer);
  session.confirms.clear();
}

async function handleUserMessage(tabId, session, msg) {
  const emit = emitter(session);
  if (session.busy) {
    emit({ type: 'error', text: 'Still working on your last request. Hit stop to cancel it.' });
    return;
  }
  session.busy = true;
  session.abort = new AbortController();
  emit({ type: 'user', text: msg.text });
  emit({ type: 'busy', busy: true });

  const settings = await loadSettings();
  const sf = new SalesforceClient(msg.context.host);
  let confirmSeq = 0;
  const env = {
    sf,
    tabId,
    settings,
    emit,
    confirm(summary) {
      const id = `c${Date.now()}-${confirmSeq++}`;
      return new Promise((resolve) => {
        if (!session.port) return resolve({ approved: false });
        session.confirms.set(id, resolve);
        emit({ type: 'confirm_request', id, summary });
      });
    },
  };

  try {
    await runAgentTurn({
      history: session.history,
      userText: msg.text,
      pageContext: msg.context,
      settings,
      env,
      signal: session.abort.signal,
    });
  } catch (err) {
    emit({
      type: 'error',
      text: err instanceof AgentError ? err.message : `Something went wrong: ${err.message}`,
      needsSettings: !settings.apiKey,
    });
  } finally {
    session.busy = false;
    session.abort = null;
    emit({ type: 'busy', busy: false });
  }
}

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== 'siforce' || !port.sender?.tab?.id) return;
  const tabId = port.sender.tab.id;
  const session = getSession(tabId);
  session.port = port;
  port.postMessage({ type: 'replay', events: session.transcript, busy: session.busy });

  port.onMessage.addListener((msg) => {
    switch (msg.type) {
      case 'user_message':
        handleUserMessage(tabId, session, msg);
        break;
      case 'confirm_response': {
        const resolve = session.confirms.get(msg.id);
        session.confirms.delete(msg.id);
        resolve?.({ approved: Boolean(msg.approved), note: msg.note });
        break;
      }
      case 'stop':
        resolveConfirms(session, { approved: false });
        session.abort?.abort();
        break;
      case 'reset':
        resolveConfirms(session, { approved: false });
        session.abort?.abort();
        // Fresh arrays, so a turn that is still unwinding can't write into the new chat.
        session.history = [];
        session.transcript = [];
        break;
      case 'open_options':
        chrome.runtime.openOptionsPage();
        break;
    }
  });

  port.onDisconnect.addListener(() => {
    if (session.port !== port) return;
    session.port = null;
    // Nobody is there to answer a pending confirmation.
    resolveConfirms(session, { approved: false });
  });
});

chrome.tabs.onRemoved.addListener((tabId) => {
  const session = sessions.get(tabId);
  session?.abort?.abort();
  sessions.delete(tabId);
});

async function sendToActiveTab(message) {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) return;
  try {
    await chrome.tabs.sendMessage(tab.id, message);
  } catch {
    // Not a Salesforce tab, so no content script is listening.
    if (message.type === 'toggle_panel') chrome.runtime.openOptionsPage();
  }
}

chrome.action.onClicked.addListener(() => sendToActiveTab({ type: 'toggle_panel' }));
chrome.commands.onCommand.addListener((command) => {
  if (command === 'toggle-listening') sendToActiveTab({ type: 'toggle_listening' });
});

chrome.runtime.onInstalled.addListener(async ({ reason }) => {
  if (reason === 'install') {
    const { apiKey } = await chrome.storage.local.get('apiKey');
    if (!apiKey) chrome.runtime.openOptionsPage();
  }
});
