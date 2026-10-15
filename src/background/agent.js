// The agent loop: send the conversation to Claude, run whatever tools it asks
// for, feed the results back, and repeat until it answers.

import Anthropic from '@anthropic-ai/sdk';
import { SYSTEM_PROMPT, buildPageContextBlock } from './prompt.js';
import { TOOL_DEFINITIONS, runTool } from './tools.js';

const MAX_STEPS = 15;

// Models that support the server-side refusal fallback (`fallbacks: "default"`).
const SERVER_FALLBACK_MODELS = new Set(['claude-opus-5-5', 'claude-sonnet-5-5', 'claude-fable-5-1', 'claude-opus-5']);

export class AgentError extends Error {}

function describeApiError(err) {
  if (err instanceof Anthropic.AuthenticationError) return 'Your Anthropic API key was rejected. Check it in SiForce settings.';
  if (err instanceof Anthropic.PermissionDeniedError) return 'This API key does not have access to the selected model.';
  if (err instanceof Anthropic.NotFoundError) return 'The selected model was not found. Pick another one in SiForce settings.';
  if (err instanceof Anthropic.RateLimitError) return 'Claude is rate limiting requests right now. Try again in a moment.';
  if (err instanceof Anthropic.APIConnectionError) return 'Could not reach the Claude API. Check your connection.';
  if (err instanceof Anthropic.APIError) return `Claude API error: ${err.message}`;
  return err.message || String(err);
}

/** Add user content, merging into a trailing user message so roles keep alternating. */
function pushUser(history, blocks) {
  const last = history[history.length - 1];
  if (last?.role === 'user') last.content = [...last.content, ...blocks];
  else history.push({ role: 'user', content: blocks });
}

/** If a turn stopped between a tool_use and its results, close it out so the history stays valid. */
function closeDanglingToolUse(history, reason) {
  const last = history[history.length - 1];
  if (last?.role !== 'assistant' || !Array.isArray(last.content)) return;
  const pending = last.content.filter((b) => b.type === 'tool_use');
  if (!pending.length) return;
  history.push({
    role: 'user',
    content: pending.map((b) => ({ type: 'tool_result', tool_use_id: b.id, content: reason, is_error: true })),
  });
}

/**
 * Run one user turn to completion.
 * @param {object} p
 * @param {Array} p.history          conversation for this tab, mutated in place (append-only)
 * @param {string} p.userText
 * @param {object} p.pageContext     from parseSalesforceUrl
 * @param {object} p.settings
 * @param {object} p.env             {sf, tabId, settings, confirm, emit}
 * @param {AbortSignal} p.signal
 */
export async function runAgentTurn({ history, userText, pageContext, settings, env, signal }) {
  if (!settings.apiKey) throw new AgentError('Add your Anthropic API key in SiForce settings to get started.');

  const client = new Anthropic({ apiKey: settings.apiKey, dangerouslyAllowBrowser: true });
  const model = settings.model;

  pushUser(history, [{ type: 'text', text: `${buildPageContextBlock(pageContext)}\n\n${userText}` }]);

  try {
    for (let step = 0; step < MAX_STEPS; step++) {
      const params = {
        model,
        max_tokens: 16000,
        system: [{ type: 'text', text: SYSTEM_PROMPT }],
        tools: TOOL_DEFINITIONS,
        messages: history,
        thinking: { type: 'adaptive' },
        output_config: { effort: settings.effort },
        cache_control: { type: 'ephemeral' },
      };
      if (SERVER_FALLBACK_MODELS.has(model)) {
        params.betas = ['server-side-fallback-2026-07-01'];
        params.fallbacks = 'default';
      }

      let response;
      try {
        response = await client.beta.messages.create(params, { signal });
      } catch (err) {
        if (signal.aborted) return;
        throw new AgentError(describeApiError(err));
      }

      if (response.stop_reason === 'refusal') {
        throw new AgentError("Claude declined that request. Try rephrasing it.");
      }

      history.push({ role: 'assistant', content: response.content });

      for (const block of response.content) {
        if (block.type === 'text' && block.text.trim()) env.emit({ type: 'assistant', text: block.text.trim() });
      }

      if (response.stop_reason === 'pause_turn') continue;
      if (response.stop_reason === 'max_tokens') {
        closeDanglingToolUse(history, 'Response was cut off before this tool ran.');
        throw new AgentError('The response was cut off. Try a shorter request.');
      }
      if (response.stop_reason !== 'tool_use') return;

      const results = [];
      for (const block of response.content) {
        if (block.type !== 'tool_use') continue;
        if (signal.aborted) break;
        env.emit({ type: 'tool_start', id: block.id, name: block.name, input: block.input });
        const result = await runTool(block.name, block.input, env);
        const failed = Boolean(result?.error);
        env.emit({ type: 'tool_end', id: block.id, name: block.name, ok: !failed && !result?.declined });
        results.push({
          type: 'tool_result',
          tool_use_id: block.id,
          content: JSON.stringify(result ?? { success: true }),
          ...(failed ? { is_error: true } : {}),
        });
      }
      if (signal.aborted) return;
      history.push({ role: 'user', content: results });
    }
    throw new AgentError('That took too many steps, so I stopped. Try breaking it into smaller requests.');
  } finally {
    closeDanglingToolUse(history, 'Cancelled by the rep.');
  }
}
