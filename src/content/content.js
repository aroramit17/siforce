// Floating voice panel injected into Salesforce. A tab docks on the right edge;
// press the mic, talk, and the request goes to the background agent along with
// what record is on screen. Everything lives in a closed shadow root so
// Salesforce styles can't leak in or out.

import css from './panel.css';
import { parseSalesforceUrl } from '../shared/context.js';
import { DEFAULT_SETTINGS } from '../shared/settings.js';

const ICONS = {
  mic: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10a7 7 0 0 0 14 0"/><path d="M12 17v4"/><path d="M8 21h8"/></svg>',
  spark: '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.2 6.3L20.5 10l-6.3 2.2L12 18.5l-2.2-6.3L3.5 10l6.3-1.7z"/></svg>',
  chevron: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 18l-6-6 6-6"/></svg>',
  close: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M18 6L6 18M6 6l12 12"/></svg>',
  speaker: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 5L6 9H2v6h4l5 4z"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/><path d="M19 5a10 10 0 0 1 0 14"/></svg>',
  newChat: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M5 12h14"/></svg>',
  gear: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>',
  link: '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17L17 7M8 7h9v9"/></svg>',
};

const EXAMPLES = [
  'Update this lead status to converted',
  'Log a call: left a voicemail, follow up Friday',
  'Set the rating to hot and the lead source to webinar',
  'How many open opportunities do I have closing this month?',
];

const TOOL_LABELS = {
  get_record: (i) => `Reading the ${i.objectApiName || 'record'}`,
  describe_object: (i) => `Checking ${i.objectApiName} fields`,
  soql_query: () => 'Searching Salesforce',
  get_lead_statuses: () => 'Checking lead statuses',
  update_record: (i) => `Updating the ${i.objectApiName}`,
  create_record: (i) => `Creating a ${i.objectApiName}`,
  convert_lead: () => 'Converting the lead',
  refresh_page: () => 'Refreshing the page',
  navigate_to_record: () => 'Opening the record',
  open_list_view: (i) => `Opening ${i.objectApiName} list`,
  read_page: () => 'Reading the page',
  click_page_element: (i) => `Clicking "${i.label}"`,
};

const YES_RE = /^(yes|yeah|yep|yup|sure|confirm(ed)?|do it|go ahead|go for it|ok(ay)?|correct|approve[d]?|proceed|sounds good|please do)\b/i;
const NO_RE = /^(no|nope|cancel|stop|don'?t|do not|wait|hold on|never ?mind)\b/i;

function el(tag, attrs = {}, children = []) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') node.className = v;
    else if (k === 'text') node.textContent = v;
    else if (k === 'html') node.innerHTML = v; // only ever used with the static ICONS above
    else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  for (const c of [].concat(children)) if (c) node.append(c);
  return node;
}

function main() {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

  const host = el('div', { id: 'siforce-root' });
  const shadow = host.attachShadow({ mode: 'closed' });
  shadow.append(el('style', { text: css }));

  let settings = { ...DEFAULT_SETTINGS };
  let port = null;
  let busy = false;
  let recognition = null;
  let listening = false;
  let lastInputWasVoice = false;
  let pendingConfirm = null; // {id, card}
  const activities = new Map(); // tool_use id -> element

  // ---------- Side tab ----------
  const tabMic = el('button', { class: 'mic', title: 'Talk to SiForce (Alt+Shift+M)', 'aria-label': 'Start talking', html: ICONS.mic });
  const tabOpen = el('button', { class: 'open', title: 'Open SiForce', 'aria-label': 'Open SiForce panel', html: ICONS.chevron });
  const grip = el('div', { class: 'grip', title: 'Drag to move' });
  const tab = el('div', { class: 'tab' }, [grip, tabMic, tabOpen]);
  const caption = el('div', { class: 'caption', hidden: '' });

  // ---------- Drawer ----------
  const contextLabel = el('div', { class: 'context' });
  const speakBtn = el('button', { class: 'icon-btn', title: 'Read replies aloud', 'aria-label': 'Read replies aloud', html: ICONS.speaker });
  const resetBtn = el('button', { class: 'icon-btn', title: 'New conversation', 'aria-label': 'New conversation', html: ICONS.newChat });
  const settingsBtn = el('button', { class: 'icon-btn', title: 'Settings', 'aria-label': 'Settings', html: ICONS.gear });
  const closeBtn = el('button', { class: 'icon-btn', title: 'Close', 'aria-label': 'Close panel', html: ICONS.close });
  const header = el('header', {}, [
    el('div', { class: 'brand' }, [el('span', { class: 'logo', html: ICONS.spark }), el('span', { text: 'SiForce' })]),
    contextLabel,
    speakBtn,
    resetBtn,
    settingsBtn,
    closeBtn,
  ]);
  const messages = el('div', { class: 'messages', 'aria-live': 'polite' });
  const interim = el('div', { class: 'interim' });
  const input = el('textarea', { placeholder: 'Talk or type a request…', rows: '1', 'aria-label': 'Message' });
  const stopBtn = el('button', { class: 'stop', hidden: '', text: 'Stop' });
  const panelMic = el('button', { class: 'mic big', title: 'Talk (Alt+Shift+M)', 'aria-label': 'Start talking', html: ICONS.mic });
  const footer = el('footer', {}, [interim, el('div', { class: 'composer' }, [input, stopBtn, panelMic])]);
  const panel = el('div', { class: 'panel closed', role: 'dialog', 'aria-label': 'SiForce assistant' }, [header, messages, footer]);

  shadow.append(tab, caption, panel);
  document.documentElement.append(host);

  // ---------- Settings ----------
  chrome.storage.local.get(['speakReplies', 'lang', 'tabTop']).then((s) => {
    settings = { ...settings, ...s };
    speakBtn.setAttribute('aria-pressed', String(settings.speakReplies));
    placeTab(s.tabTop ?? Math.round(window.innerHeight * 0.4));
  });
  chrome.storage.onChanged.addListener((changes) => {
    for (const [k, { newValue }] of Object.entries(changes)) settings[k] = newValue;
    speakBtn.setAttribute('aria-pressed', String(settings.speakReplies));
  });

  // ---------- Tab dragging ----------
  function placeTab(top) {
    const clamped = Math.max(12, Math.min(window.innerHeight - 140, top));
    tab.style.top = `${clamped}px`;
    caption.style.top = `${clamped + 58}px`;
    return clamped;
  }
  grip.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    const startY = e.clientY;
    const startTop = parseInt(tab.style.top, 10) || 0;
    let top = startTop;
    const move = (ev) => (top = placeTab(startTop + ev.clientY - startY));
    const up = () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      chrome.storage.local.set({ tabTop: top });
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  });

  // ---------- Panel open/close ----------
  const isOpen = () => !panel.classList.contains('closed');
  function setOpen(open) {
    panel.classList.toggle('closed', !open);
    tab.classList.toggle('hidden', open);
    try {
      sessionStorage.setItem('siforce.open', open ? '1' : '');
    } catch {}
    if (open) {
      caption.hidden = true;
      updateContextLabel();
      messages.scrollTop = messages.scrollHeight;
    }
  }
  try {
    if (sessionStorage.getItem('siforce.open')) setOpen(true);
  } catch {}

  // ---------- Page context ----------
  const currentContext = () => parseSalesforceUrl(location.href, document.title);
  function updateContextLabel() {
    const c = currentContext();
    const what =
      c.pageType === 'record'
        ? [c.objectApiName, c.recordName].filter(Boolean).join(' · ') || 'Record'
        : c.objectApiName
          ? `${c.objectApiName} ${c.pageType === 'list' ? 'list' : ''}`.trim()
          : c.pageType === 'home' ? 'Home' : '';
    contextLabel.textContent = what;
    contextLabel.title = what;
  }
  // Lightning is a single-page app; watch for URL and title changes.
  let lastHref = '';
  setInterval(() => {
    const key = location.href + document.title;
    if (key !== lastHref) {
      lastHref = key;
      if (isOpen()) updateContextLabel();
    }
  }, 1000);

  // ---------- Connection to the background agent ----------
  function connect() {
    if (port) return port;
    if (!chrome.runtime?.id) {
      renderError('SiForce was updated. Reload this page to keep using it.');
      return null;
    }
    port = chrome.runtime.connect({ name: 'siforce' });
    port.onMessage.addListener(onEvent);
    port.onDisconnect.addListener(() => {
      port = null;
      setBusy(false);
    });
    return port;
  }
  function send(msg) {
    try {
      connect()?.postMessage(msg);
    } catch {
      port = null;
      connect()?.postMessage(msg);
    }
  }

  function onEvent(ev) {
    switch (ev.type) {
      case 'replay':
        messages.replaceChildren();
        activities.clear();
        if (!ev.events.length) renderEmpty();
        for (const e of ev.events) renderEvent(e, { replay: true });
        setBusy(ev.busy);
        break;
      case 'busy':
        setBusy(ev.busy);
        break;
      default:
        renderEvent(ev, { replay: false });
    }
  }

  function renderEvent(ev, { replay }) {
    switch (ev.type) {
      case 'user':
        append(el('div', { class: 'msg user', text: ev.text }));
        break;
      case 'assistant':
        append(el('div', { class: 'msg assistant', text: ev.text }));
        if (!replay) speak(ev.text);
        break;
      case 'error':
        renderError(ev.text, ev.needsSettings);
        if (!replay) speak(ev.text);
        break;
      case 'record_link':
        append(el('a', { class: 'link', href: ev.url, target: '_self' }, [document.createTextNode(ev.label), el('span', { html: ICONS.link })]));
        break;
      case 'tool_start': {
        const label = (TOOL_LABELS[ev.name] || (() => ev.name))(ev.input || {});
        const line = el('div', { class: 'activity' }, [el('span', { class: 'dot' }), el('span', { text: label })]);
        activities.set(ev.id, line);
        append(line);
        break;
      }
      case 'tool_end':
        activities.get(ev.id)?.classList.add(ev.ok ? 'done' : 'failed');
        break;
      case 'confirm_request':
        renderConfirm(ev);
        break;
    }
  }

  // ---------- Rendering ----------
  function append(node) {
    messages.querySelector('.empty')?.remove();
    messages.querySelector('.thinking')?.remove();
    messages.append(node);
    if (busy && !pendingConfirm) messages.append(thinkingLine());
    messages.scrollTop = messages.scrollHeight;
  }
  function thinkingLine() {
    return el('div', { class: 'activity thinking' }, [el('span', { class: 'dot' }), el('span', { text: 'Thinking…' })]);
  }
  function renderEmpty() {
    const examples = EXAMPLES.map((text) => el('button', { text: `“${text}”`, onclick: () => submit(text) }));
    messages.append(
      el('div', { class: 'empty' }, [
        el('h3', { text: 'What should I do in Salesforce?' }),
        el('div', { text: 'Press the mic and say it. I know which record you are on.' }),
        el('div', { class: 'examples' }, examples),
      ]),
    );
  }
  function renderError(text, needsSettings) {
    const box = el('div', { class: 'msg error', text });
    if (needsSettings) {
      box.append(el('br'), el('button', { text: 'Open settings', onclick: () => send({ type: 'open_options' }) }));
    }
    append(box);
  }
  function renderConfirm(ev) {
    const resolve = (approved, note) => {
      if (!pendingConfirm || pendingConfirm.id !== ev.id) return;
      card.classList.add('resolved');
      card.querySelector('.label').textContent = approved ? 'Confirmed' : 'Cancelled';
      pendingConfirm = null;
      send({ type: 'confirm_response', id: ev.id, approved, note });
      if (busy) messages.append(thinkingLine());
    };
    const card = el('div', { class: 'confirm' }, [
      el('div', { class: 'label', text: 'Confirm' }),
      el('div', { class: 'summary', text: ev.summary }),
      el('div', { class: 'actions' }, [
        el('button', { class: 'yes', text: 'Confirm', onclick: () => resolve(true) }),
        el('button', { class: 'no', text: 'Cancel', onclick: () => resolve(false) }),
      ]),
      el('div', { class: 'voice-hint', text: 'Or press the mic and say “yes” or “no”.' }),
    ]);
    pendingConfirm = { id: ev.id, resolve };
    append(card);
    setOpen(true);
    // Voice users get the question read out, then the mic opens for their answer.
    speak(`${ev.summary}. Should I go ahead?`, () => {
      if (lastInputWasVoice && pendingConfirm?.id === ev.id) startListening();
    });
  }

  function setBusy(value) {
    busy = value;
    stopBtn.hidden = !value;
    messages.querySelector('.thinking')?.remove();
    if (value && !pendingConfirm) {
      messages.append(thinkingLine());
      messages.scrollTop = messages.scrollHeight;
    }
  }

  // ---------- Submitting ----------
  function submit(text, { viaVoice = false } = {}) {
    text = text.trim();
    if (!text) return;
    lastInputWasVoice = viaVoice;
    setOpen(true);

    if (pendingConfirm) {
      if (YES_RE.test(text)) return pendingConfirm.resolve(true);
      if (NO_RE.test(text)) return pendingConfirm.resolve(false);
      // Anything else ("no, attach it to the existing account") declines with their words as guidance.
      return pendingConfirm.resolve(false, text);
    }
    if (busy) {
      renderError('Still working on your last request. Hit stop to cancel it.');
      return;
    }
    send({ type: 'user_message', text, context: currentContext() });
  }

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      submit(input.value);
      input.value = '';
    }
    e.stopPropagation(); // keep Salesforce keyboard shortcuts from firing while typing
  });

  // ---------- Speech in ----------
  function startListening() {
    if (listening) return;
    if (!SpeechRecognition) {
      setOpen(true);
      renderError('Speech recognition is not available in this browser. You can type instead.');
      return;
    }
    window.speechSynthesis?.cancel();
    recognition = new SpeechRecognition();
    recognition.lang = settings.lang || navigator.language || 'en-US';
    recognition.interimResults = true;
    recognition.continuous = false;
    recognition.maxAlternatives = 1;

    let finalText = '';
    recognition.onresult = (e) => {
      let live = '';
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const r = e.results[i];
        if (r.isFinal) finalText += r[0].transcript;
        else live += r[0].transcript;
      }
      showInterim(finalText + live);
    };
    recognition.onerror = (e) => {
      if (e.error === 'not-allowed' || e.error === 'service-not-allowed') {
        setOpen(true);
        renderError('Microphone access is blocked for this site. Allow it from the lock icon in the address bar, then try again.');
      } else if (e.error === 'no-speech') {
        showInterim('');
      } else if (e.error !== 'aborted') {
        setOpen(true);
        renderError(`Speech recognition error: ${e.error}`);
      }
    };
    recognition.onend = () => {
      setListening(false);
      showInterim('');
      if (finalText.trim()) submit(finalText, { viaVoice: true });
    };

    recognition.start();
    setListening(true);
    showInterim('');
  }
  function stopListening() {
    recognition?.stop();
  }
  function toggleListening() {
    listening ? stopListening() : startListening();
  }
  function setListening(value) {
    listening = value;
    for (const m of [tabMic, panelMic]) {
      m.classList.toggle('listening', value);
      m.setAttribute('aria-label', value ? 'Stop listening' : 'Start talking');
    }
    caption.hidden = !value || isOpen();
  }
  function showInterim(text) {
    interim.textContent = listening ? text || 'Listening…' : '';
    caption.replaceChildren(text ? document.createTextNode(text) : el('span', { class: 'hint', text: 'Listening… say what you want to do' }));
  }

  // ---------- Speech out ----------
  function speak(text, onDone) {
    const synth = window.speechSynthesis;
    if (!settings.speakReplies || !synth || !text) return onDone?.();
    synth.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.lang = settings.lang || navigator.language || 'en-US';
    u.rate = 1.05;
    u.onend = () => onDone?.();
    u.onerror = () => onDone?.();
    synth.speak(u);
  }

  // ---------- Wiring ----------
  tabMic.addEventListener('click', toggleListening);
  panelMic.addEventListener('click', toggleListening);
  tabOpen.addEventListener('click', () => setOpen(true));
  closeBtn.addEventListener('click', () => setOpen(false));
  settingsBtn.addEventListener('click', () => send({ type: 'open_options' }));
  stopBtn.addEventListener('click', () => {
    pendingConfirm?.resolve(false);
    send({ type: 'stop' });
  });
  speakBtn.addEventListener('click', () => {
    const next = !settings.speakReplies;
    if (!next) window.speechSynthesis?.cancel();
    chrome.storage.local.set({ speakReplies: next });
  });
  resetBtn.addEventListener('click', () => {
    window.speechSynthesis?.cancel();
    pendingConfirm = null;
    send({ type: 'reset' });
    messages.replaceChildren();
    activities.clear();
    renderEmpty();
  });
  panel.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') setOpen(false);
  });

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === 'toggle_panel') setOpen(!isOpen());
    if (msg.type === 'toggle_listening') toggleListening();
  });

  connect();
}

// Only the top-level Salesforce window, and only once.
if (window.top === window && !window.__siforceLoaded) {
  window.__siforceLoaded = true;
  main();
}
