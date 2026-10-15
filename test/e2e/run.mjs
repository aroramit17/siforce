// End-to-end: real Chromium + the built extension, against a mock Salesforce
// org and a mock Claude API (scripted tool calls). Proves the wiring:
// panel -> port -> agent loop -> SDK -> tools -> SF REST/SOAP -> confirm UI.
//
// Run:  npm run build && npm i --no-save playwright && sudo node test/e2e/run.mjs
// (binds 127.0.0.1:443; needs openssl; set CHROME_PATH to use a specific Chromium)
import https from 'node:https';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const here = path.dirname(fileURLToPath(import.meta.url));
const EXT = path.resolve(here, '../../dist');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'siforce-e2e-'));
execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', `${OUT}/key.pem`, '-out', `${OUT}/cert.pem`,
  '-days', '1', '-subj', '/CN=mock', '-addext', 'subjectAltName=DNS:acme.lightning.force.com,DNS:acme.my.salesforce.com,DNS:api.anthropic.com'], { stdio: 'ignore' });
const LEAD = '00Q5g00000AbCdEEAV';
const ACC = '0015g00000AAAAAAA1', CON = '0035g00000BBBBBBB2', OPP = '0065g00000CCCCCCC3';
const SID = '00D5g000000AbCd!AQ4AQFakeSession';
const log = [];
let soapBody = null;
const claudeRequests = [];

function page(title) {
  return `<!doctype html><html><head><title>${title}</title></head><body><main class="oneContent"><h1>${title.split('|')[0]}</h1><p>Company: Acme Robotics</p></main></body></html>`;
}

// Scripted Claude: decide the next step from how many tool results are in the latest turn.
function claudeReply(body) {
  const msgs = body.messages;
  const lastUserText = [...msgs].reverse().find((m) => m.role === 'user' && m.content.some((b) => b.type === 'text'));
  const idx = msgs.lastIndexOf(lastUserText);
  const steps = msgs.slice(idx + 1).filter((m) => m.role === 'assistant').length;
  const tool = (name, input) => ({ type: 'tool_use', id: `toolu_${steps}`, name, input });
  const script = [
    [{ type: 'text', text: 'On it.' }, tool('get_record', { objectApiName: 'Lead', recordId: LEAD, fields: ['Name', 'Company', 'Email', 'Status', 'IsConverted'] })],
    // Try the naive path first to prove the guard redirects it.
    [tool('update_record', { objectApiName: 'Lead', recordId: LEAD, fields: { Status: 'Closed - Converted' }, summary: 'Set status to Closed - Converted' })],
    [tool('get_lead_statuses', {})],
    [tool('soql_query', { query: "SELECT Id, Name FROM Account WHERE Name = 'Acme Robotics' LIMIT 5" })],
    [tool('convert_lead', { leadId: LEAD, convertedStatus: 'Closed - Converted', opportunityName: 'Acme Robotics', summary: 'Convert Jane Doe: new account Acme Robotics, new contact Jane Doe, new opportunity Acme Robotics' })],
    [tool('navigate_to_record', { recordId: OPP })],
    [{ type: 'text', text: 'Done. Jane Doe is converted. I created the Acme Robotics account, the Jane Doe contact, and an Acme Robotics opportunity.' }],
  ];
  const content = script[Math.min(steps, script.length - 1)];
  return {
    id: `msg_${Date.now()}`, type: 'message', role: 'assistant', model: body.model, content,
    stop_reason: content.some((b) => b.type === 'tool_use') ? 'tool_use' : 'end_turn', stop_sequence: null,
    usage: { input_tokens: 10, output_tokens: 10 },
  };
}

const server = https.createServer({ key: fs.readFileSync(`${OUT}/key.pem`), cert: fs.readFileSync(`${OUT}/cert.pem`) }, async (req, res) => {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const raw = Buffer.concat(chunks).toString();
  const url = new URL(req.url, `https://${req.headers.host}`);
  const host = req.headers.host.split(':')[0];
  log.push(`${host} ${req.method} ${url.pathname}${url.search}`);
  const json = (code, obj) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj)); };

  if (host === 'api.anthropic.com') {
    const body = JSON.parse(raw);
    claudeRequests.push({ headers: req.headers, body });
    return json(200, claudeReply(body));
  }
  if (host === 'acme.lightning.force.com') {
    res.writeHead(200, { 'content-type': 'text/html' });
    const isOpp = url.pathname.includes(OPP);
    return res.end(page(isOpp ? 'Acme Robotics | Opportunity | Salesforce' : 'Jane Doe | Lead | Salesforce'));
  }
  // acme.my.salesforce.com API
  if (req.headers.authorization !== `Bearer ${SID}` && !url.pathname.startsWith('/services/Soap')) return json(401, [{ message: 'Session expired', errorCode: 'INVALID_SESSION_ID' }]);
  if (url.pathname === '/services/data/') return json(200, [{ version: '61.0' }, { version: '62.0' }]);
  if (url.pathname === `/services/data/v62.0/sobjects/Lead/${LEAD}`) return json(200, { attributes: {}, Name: 'Jane Doe', Company: 'Acme Robotics', Email: 'jane@acme.test', Status: 'Working - Contacted', IsConverted: false });
  if (url.pathname === '/services/data/v62.0/query') {
    const q = url.searchParams.get('q');
    if (q.includes('FROM LeadStatus')) return json(200, { totalSize: 3, records: [
      { MasterLabel: 'Open - Not Contacted', ApiName: 'Open - Not Contacted', IsConverted: false, IsDefault: true },
      { MasterLabel: 'Working - Contacted', ApiName: 'Working - Contacted', IsConverted: false, IsDefault: false },
      { MasterLabel: 'Closed - Converted', ApiName: 'Closed - Converted', IsConverted: true, IsDefault: false },
    ] });
    return json(200, { totalSize: 0, records: [] });
  }
  if (url.pathname === '/services/Soap/u/62.0') {
    soapBody = raw;
    res.writeHead(200, { 'content-type': 'text/xml' });
    return res.end(`<?xml version="1.0"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="urn:partner.soap.sforce.com"><soapenv:Body><convertLeadResponse><result><accountId>${ACC}</accountId><contactId>${CON}</contactId><leadId>${LEAD}</leadId><opportunityId>${OPP}</opportunityId><success>true</success></result></convertLeadResponse></soapenv:Body></soapenv:Envelope>`);
  }
  json(404, [{ message: 'not found' }]);
});
await new Promise((r) => server.listen(443, '127.0.0.1', r));

const ctx = await chromium.launchPersistentContext('', {
  executablePath: process.env.CHROME_PATH || undefined,
  headless: true,
  ignoreHTTPSErrors: true,
  args: [
    `--disable-extensions-except=${EXT}`, `--load-extension=${EXT}`,
    '--host-resolver-rules=MAP acme.lightning.force.com 127.0.0.1, MAP acme.my.salesforce.com 127.0.0.1, MAP api.anthropic.com 127.0.0.1',
    '--ignore-certificate-errors', '--no-proxy-server',
  ],
});
let [sw] = ctx.serviceWorkers();
if (!sw) sw = await ctx.waitForEvent('serviceworker');
for (let i = 0; i < 50; i++) { if (await sw.evaluate(() => Boolean(globalThis.chrome?.storage))) break; await new Promise((r) => setTimeout(r, 100)); }
await sw.evaluate(() => chrome.storage.local.set({ apiKey: 'sk-ant-test', speakReplies: false }));
await sw.evaluate(async (sid) => {
  for (const host of ['acme.lightning.force.com', 'acme.my.salesforce.com']) {
    await chrome.cookies.set({ url: `https://${host}/`, name: 'sid', value: sid, secure: true, expirationDate: Date.now() / 1000 + 3600 });
  }
}, SID);
for (const p of ctx.pages()) if (p.url().startsWith('chrome-extension://')) await p.close(); // options page from onInstalled

const tab = await ctx.newPage();
await tab.setViewportSize({ width: 1280, height: 800 });
await tab.goto(`https://acme.lightning.force.com/lightning/r/Lead/${LEAD}/view`);
await tab.waitForSelector('#siforce-root', { state: 'attached' });
await tab.waitForTimeout(500);
await tab.screenshot({ path: `${OUT}/shot-1-tab.png` });

// Closed shadow root: drive the UI by coordinates and keyboard.
// Open the drawer via the tab's chevron (bottom button of the docked tab).
const box = await tab.evaluate(() => ({ w: innerWidth, h: innerHeight }));
const tabTop = Math.round(box.h * 0.4);
await tab.mouse.click(box.w - 22, tabTop + 8 + 6 + 6 + 40 + 6 + 15);
await tab.waitForTimeout(400);
await tab.screenshot({ path: `${OUT}/shot-2-panel.png` });

// Focus the textarea (footer, left of the mic) and type the request.
await tab.mouse.click(box.w - 16 - 384 + 12 + 120, box.h - 16 - 12 - 22);
await tab.keyboard.type('update this lead status to converted');
await tab.keyboard.press('Enter');

// Wait for the confirm card, screenshot, then click Confirm.
for (let i = 0; i < 100 && claudeRequests.length < 5; i++) await tab.waitForTimeout(100);
await tab.waitForTimeout(600);
await tab.screenshot({ path: `${OUT}/shot-3-confirm.png` });
// Answer the confirmation the way a voice user would: "yes".
await tab.mouse.click(box.w - 16 - 384 + 12 + 120, box.h - 16 - 12 - 22);
await tab.keyboard.type('yes');
await tab.keyboard.press('Enter');

await tab.waitForURL(new RegExp(OPP), { timeout: 15000 });
await tab.waitForSelector('#siforce-root', { state: 'attached' });
await tab.waitForTimeout(1500);
await tab.screenshot({ path: `${OUT}/shot-4-done.png` });

// ---- Assertions ----
const fail = (m) => { console.error('FAIL:', m); process.exitCode = 1; };
const first = claudeRequests[0];
console.log('Claude requests:', claudeRequests.length);
console.log('first request model/effort/fallbacks/betas:', first.body.model, first.body.output_config, first.body.fallbacks, first.headers['anthropic-beta']);
if (first.body.model !== 'claude-opus-5-5') fail('model');
if (first.body.fallbacks !== 'default' || !String(first.headers['anthropic-beta']).includes('server-side-fallback-2026-07-01')) fail('fallbacks');
if (first.body.thinking?.type !== 'adaptive') fail('thinking');
if (!first.headers['anthropic-dangerous-direct-browser-access']) fail('browser header');
const ctxText = first.body.messages[0].content[0].text;
console.log('page context sent:\n' + ctxText);
if (!ctxText.includes(`Record Id: ${LEAD}`) || !ctxText.includes('Object: Lead') || !ctxText.includes('Jane Doe')) fail('page context');

const guard = claudeRequests[2].body.messages.at(-1).content[0];
console.log('guard result:', guard.content);
if (!guard.is_error || !guard.content.includes('convert_lead')) fail('converted-status guard');

if (!soapBody) fail('no SOAP convertLead call');
else {
  console.log('SOAP leadId/status:', soapBody.match(/<urn:leadId>(.*?)</)[1], '/', soapBody.match(/<urn:convertedStatus>(.*?)</)[1]);
  if (!soapBody.includes(`<urn:sessionId>${SID}</urn:sessionId>`)) fail('SOAP session');
}
const convertResult = claudeRequests[5].body.messages.at(-1).content[0];
console.log('convert result to Claude:', convertResult.content);
if (!convertResult.content.includes(OPP)) fail('convert result');
if (!tab.url().includes(OPP)) fail('navigation');
console.log('final URL:', tab.url());
console.log('SF/API log:\n ' + log.filter((l) => !l.startsWith('api.anthropic')).join('\n '));
console.log(`Screenshots in ${OUT}`);
console.log(process.exitCode ? 'E2E FAILED' : 'E2E PASSED');
await ctx.close();
server.close();
