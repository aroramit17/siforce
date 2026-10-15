# SiForce: a voice copilot for Salesforce

SiForce is a Chrome extension that docks a small tab on the right edge of every Salesforce page. Press the mic, say what you want ("update this lead status to converted"), and it does the work in your org using Claude and your existing Salesforce login.

```
 ┌──────────────── Salesforce (Lightning) ────────────────┐ ┌─ SiForce ──────────────────┐
 │  Jane Doe · Lead                                        │ │ Lead · Jane Doe            │
 │                                                         │ │  you: update this lead     │
 │                                                     ┌──┐│ │       status to converted  │
 │                                                     │🎤││ │  ● Reading the Lead        │
 │                                                     │ ‹││ │  ● Checking lead statuses  │
 │                                                     └──┘│ │  ┌ CONFIRM ──────────────┐ │
 │                                                         │ │  │ Convert Jane Doe: new │ │
 │                                                         │ │  │ account Acme, contact │ │
 │                                                         │ │  │ Jane Doe, opp Acme    │ │
 │                                                         │ │  └ [Confirm]  [Cancel] ─┘ │
 └─────────────────────────────────────────────────────────┘ └────────────────────────────┘
```

## What it does

- **Floating side tab** on every Salesforce page, similar to Salesloft's. Drag it up or down; it remembers where you put it.
- **Push to talk.** Click the mic (or press <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>M</kbd>). Live captions show what it heard, and it sends when you stop talking. You can also type.
- **Knows where you are.** Each request carries the current object, record Id and record name, so "this lead", "her" and "it" resolve to the record on screen.
- **Acts on Salesforce.** Claude reads records, checks field metadata and picklists, runs SOQL, updates and creates records, and converts leads through the Salesforce APIs.
- **Browser actions.** It can refresh the record view, open records and list views, read what's on the page, and click buttons by label.
- **Talks back.** Replies are short and read aloud (you can turn this off). When it needs a yes or no, it asks out loud and opens the mic for your answer.
- **Asks before writing.** Every change shows a confirmation card. Say "yes" or "no", or click. Say "no, attach it to the existing Acme account" and it adjusts instead of giving up.

## How "update this lead status to converted" works

In Salesforce, a converted lead status isn't an ordinary field value. Statuses flagged `IsConverted` can only be reached through **Lead Conversion**, which moves the lead to the next stage of the funnel by creating an Account, a Contact and, optionally, an Opportunity. SiForce handles it that way:

1. Reads the lead (name, company, email, current status, whether it's already converted).
2. Looks up the org's Lead Status values and picks the one marked converted (asks if there are several).
3. Checks for an existing Account with the same company and a Contact with the same email, and offers to attach to them instead of creating duplicates.
4. Shows a confirmation: *"Convert Jane Doe: new account Acme, new contact Jane Doe, new opportunity Acme"*.
5. Converts the lead through the SOAP `convertLead` call, posts links to the new Account, Contact and Opportunity in the panel, and opens the Opportunity.

There's also a hard guard in code. If the model tries a plain `update_record` that sets a Lead to a converted status, the tool refuses and points it to `convert_lead`. Lead conversion always asks for confirmation, even when "Ask me before changing any record" is turned off.

## Install (developer mode)

```bash
npm install
npm run build          # outputs dist/
```

1. Open `chrome://extensions`, turn on **Developer mode**, click **Load unpacked**, and choose the `dist/` folder.
2. The settings page opens. Paste an [Anthropic API key](https://console.anthropic.com/settings/keys) and save.
3. Open Salesforce (Lightning), go to a Lead, click the mic on the right-hand tab, and allow microphone access when Chrome asks.

Use `npm run watch` to rebuild on save, then click reload on the extension card.

## Settings

| Setting | Default | Notes |
|---|---|---|
| Model | Claude Opus 5.5 | Sonnet 5.5 and Haiku 5.5 respond faster |
| Effort | Medium | Low gives the quickest spoken replies |
| Read replies aloud | On | Uses the browser's built-in speech synthesis |
| Speech language | Browser default | Any BCP-47 tag, e.g. `en-GB` |
| Ask me before changing any record | On | Lead conversion always asks |

## Architecture

```
src/
  content/content.js     Side tab + drawer (closed shadow DOM), speech in/out, page context
  content/panel.css      Panel styles (bundled into content.js as text)
  background/index.js    Service worker: one conversation per tab, port messaging, confirmations
  background/agent.js    Claude tool-use loop (@anthropic-ai/sdk, manual loop)
  background/tools.js    Tool definitions + handlers (Salesforce API and browser actions)
  background/prompt.js   System prompt with Salesforce domain rules (lead conversion etc.)
  background/salesforce.js  REST + SOAP client that reuses the browser's Salesforce session
  background/soap.js     convertLead envelope builder and response parser
  shared/context.js      URL/title -> {object, recordId, recordName, pageType}
  options/               Settings page
build.mjs                esbuild bundle to dist/, plus generated icons
```

- **Speech-to-text** uses Chrome's Web Speech API (`webkitSpeechRecognition`) in the content script. The mic permission belongs to your Salesforce domain.
- **Salesforce auth** works like Salesforce Inspector. The service worker reads your `sid` session cookie, matches the org Id from the Lightning domain to the `my.salesforce.com` domain, and calls the REST API (`/services/data/vXX.X`) and SOAP API (`/services/Soap/u/XX.X`) with it. There's no connected app or OAuth setup, and SiForce can only do what your user can do.
- **Claude** is called from the service worker with `client.beta.messages.create`, using adaptive thinking, prompt caching, and the server-side refusal fallback (`fallbacks: "default"`) on models that support it. The loop runs up to 15 tool steps per request.
- **Conversation state** lives in the service worker per tab, so the conversation survives full page navigations and is replayed into the new panel.

## Privacy and security

- Your Anthropic API key is kept in `chrome.storage.local` on this machine and sent only to `api.anthropic.com`. Calling the API straight from the browser is intended for personal or internal use. For a team rollout, put a small proxy in front of the API and keep the key on the server.
- Record data that Claude reads (fields, query results, page text) is sent to the Anthropic API to work out the next step.
- Chrome's speech recognition sends audio to Google's speech service.
- The Salesforce session cookie never leaves the extension. It's used only for calls to your own org.

## Testing

```bash
npm test                 # unit tests: URL parsing, SOAP build/parse, tool guards and confirmations
npm run test:e2e         # see below
```

`test/e2e/run.mjs` loads the built extension in real Chromium. It points `*.lightning.force.com`, `*.my.salesforce.com` and `api.anthropic.com` at a local HTTPS mock (a fake org plus a scripted Claude), types "update this lead status to converted", answers "yes" to the confirmation, and checks that the converted-status guard fires, that `convertLead` goes out over SOAP with the session, and that the tab lands on the new Opportunity. It needs `playwright` (`npm i --no-save playwright`), `openssl`, and permission to bind port 443.

## Limitations

- Tested against a mocked org. Run it in a sandbox before pointing it at production.
- Speech recognition needs Chrome or Edge. In other browsers, type instead.
- Person Account orgs and custom lead field mappings haven't been tested yet.
- Clicking UI elements by label is best effort. Data changes go through the API.
