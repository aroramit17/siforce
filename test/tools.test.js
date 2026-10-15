import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runTool, validateToolInput } from '../src/background/tools.js';

const LEAD = '00Q5g00000AbCdEEAV';

function fakeEnv(overrides = {}) {
  const calls = [];
  const sf = {
    recordUrl: (id) => `https://acme.lightning.force.com/lightning/r/${id}/view`,
    leadStatuses: async () => [
      { value: 'Open - Not Contacted', label: 'Open - Not Contacted', isConverted: false },
      { value: 'Closed - Converted', label: 'Closed - Converted', isConverted: true },
    ],
    updateRecord: async (...a) => calls.push(['update', ...a]),
    convertLead: async (o) => {
      calls.push(['convert', o]);
      return { success: true, accountId: '0015g00000AAAAAAA1', contactId: '0035g00000BBBBBBB2', opportunityId: '0065g00000CCCCCCC3' };
    },
    ...overrides.sf,
  };
  const events = [];
  return {
    calls,
    events,
    env: {
      sf,
      tabId: 1,
      settings: { confirmWrites: true, ...overrides.settings },
      emit: (e) => events.push(e),
      confirm: overrides.confirm || (async () => ({ approved: true })),
    },
  };
}

test('validation catches missing fields, wrong types and bad ids', () => {
  assert.match(validateToolInput('get_record', { objectApiName: 'Lead' }), /recordId/);
  assert.match(validateToolInput('get_record', { objectApiName: 'Lead', recordId: 'nope' }), /valid Salesforce Id/);
  assert.match(validateToolInput('update_record', { objectApiName: 'Lead', recordId: LEAD, fields: 'x', summary: 's' }), /must be object/);
  assert.equal(validateToolInput('get_lead_statuses', {}), null);
});

test('setting a Lead to a converted status is redirected to convert_lead without writing', async () => {
  const { env, calls } = fakeEnv();
  const r = await runTool('update_record', { objectApiName: 'Lead', recordId: LEAD, fields: { Status: 'closed - converted' }, summary: 's' }, env);
  assert.match(r.error, /convert_lead/);
  assert.equal(calls.length, 0);
});

test('ordinary status update goes through after confirmation', async () => {
  const { env, calls } = fakeEnv();
  const r = await runTool('update_record', { objectApiName: 'Lead', recordId: LEAD, fields: { Status: 'Open - Not Contacted' }, summary: 's' }, env);
  assert.deepEqual(r, { success: true });
  assert.equal(calls[0][0], 'update');
});

test('declined confirmation writes nothing and passes the rep\'s words back', async () => {
  const { env, calls } = fakeEnv({ confirm: async () => ({ approved: false, note: 'use the existing Acme account' }) });
  const r = await runTool('convert_lead', { leadId: LEAD, convertedStatus: 'Closed - Converted', summary: 's' }, env);
  assert.equal(r.declined, true);
  assert.match(r.message, /existing Acme account/);
  assert.equal(calls.length, 0);
});

test('convert_lead always confirms, even with confirmWrites off, and emits record links', async () => {
  let asked = 0;
  const { env, events } = fakeEnv({ settings: { confirmWrites: false }, confirm: async () => (asked++, { approved: true }) });
  const r = await runTool('convert_lead', { leadId: LEAD, convertedStatus: 'Closed - Converted', opportunityName: 'Acme', summary: 's' }, env);
  assert.equal(asked, 1);
  assert.equal(r.opportunityId, '0065g00000CCCCCCC3');
  assert.deepEqual(events.map((e) => e.label), ['Account', 'Contact', 'Opportunity']);
});

test('soql_query rejects anything but SELECT', async () => {
  const { env } = fakeEnv();
  const r = await runTool('soql_query', { query: 'DELETE FROM Lead' }, env);
  assert.match(r.error, /SELECT/);
});
