// Tools the model can call. Data tools hit the Salesforce API; browser tools
// act on the Salesforce tab itself. Anything that changes data asks the rep
// to confirm in the panel first.

import { isSalesforceId } from '../shared/context.js';

const str = (description) => ({ type: 'string', description });
const sfId = (description) => ({ type: 'string', description, pattern: '^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$' });

export const TOOL_DEFINITIONS = [
  {
    name: 'get_record',
    description:
      'Read one Salesforce record. Pass fields to keep the result small; omit them to get every field.',
    input_schema: {
      type: 'object',
      properties: {
        objectApiName: str('Object API name, e.g. Lead, Account, Opportunity.'),
        recordId: sfId('15 or 18 character record Id.'),
        fields: { type: 'array', items: { type: 'string' }, description: 'Field API names to return.' },
      },
      required: ['objectApiName', 'recordId'],
      additionalProperties: false,
    },
  },
  {
    name: 'describe_object',
    description:
      'Get the fields of an object: API names, labels, types, whether they are updateable or required, and active picklist values. Use this before writing to unfamiliar fields.',
    input_schema: {
      type: 'object',
      properties: { objectApiName: str('Object API name.') },
      required: ['objectApiName'],
      additionalProperties: false,
    },
  },
  {
    name: 'soql_query',
    description:
      'Run a read-only SOQL query, e.g. to find duplicates or answer questions. Always include a LIMIT (50 or less).',
    input_schema: {
      type: 'object',
      properties: { query: str('The SOQL query.') },
      required: ['query'],
      additionalProperties: false,
    },
  },
  {
    name: 'get_lead_statuses',
    description:
      'List the org\'s Lead Status values and which ones count as converted. Needed to pick convertedStatus for convert_lead.',
    input_schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'update_record',
    description:
      'Update fields on an existing record. Asks the rep to confirm. Cannot set a Lead to a converted status; use convert_lead for that.',
    input_schema: {
      type: 'object',
      properties: {
        objectApiName: str('Object API name.'),
        recordId: sfId('Record Id.'),
        fields: { type: 'object', description: 'Map of field API name to new value.' },
        summary: str('One plain-English line shown to the rep for confirmation, e.g. "Set Jane Doe\'s Rating to Hot".'),
      },
      required: ['objectApiName', 'recordId', 'fields', 'summary'],
      additionalProperties: false,
    },
  },
  {
    name: 'create_record',
    description: 'Create a record (Task, Opportunity, Contact, etc.). Asks the rep to confirm.',
    input_schema: {
      type: 'object',
      properties: {
        objectApiName: str('Object API name.'),
        fields: { type: 'object', description: 'Map of field API name to value.' },
        summary: str('One plain-English line shown to the rep for confirmation.'),
      },
      required: ['objectApiName', 'fields', 'summary'],
      additionalProperties: false,
    },
  },
  {
    name: 'convert_lead',
    description:
      'Convert a Lead: marks it converted and creates (or attaches to) an Account and Contact, and optionally creates an Opportunity. This is the only way to give a Lead a converted status. Asks the rep to confirm.',
    input_schema: {
      type: 'object',
      properties: {
        leadId: sfId('Lead Id.'),
        convertedStatus: str('A Lead Status value with isConverted=true, from get_lead_statuses.'),
        accountId: sfId('Existing Account to attach the lead to. Omit to create a new Account.'),
        contactId: sfId('Existing Contact (on accountId) to merge the lead into. Omit to create a new Contact.'),
        createOpportunity: { type: 'boolean', description: 'Create an Opportunity. Defaults to true.' },
        opportunityName: str('Name for the new Opportunity.'),
        ownerId: sfId('Owner for the new records. Omit to keep the lead owner.'),
        summary: str(
          'Plain-English confirmation line, e.g. "Convert Jane Doe: new account Acme, new contact Jane Doe, new opportunity Acme".',
        ),
      },
      required: ['leadId', 'convertedStatus', 'summary'],
      additionalProperties: false,
    },
  },
  {
    name: 'refresh_page',
    description: 'Refresh the Salesforce record page the rep is viewing so it shows the latest data.',
    input_schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'navigate_to_record',
    description: 'Open a record in the rep\'s Salesforce tab.',
    input_schema: {
      type: 'object',
      properties: { recordId: sfId('Record Id to open.') },
      required: ['recordId'],
      additionalProperties: false,
    },
  },
  {
    name: 'open_list_view',
    description: 'Open the list view (tab) for an object, e.g. Leads or Opportunities.',
    input_schema: {
      type: 'object',
      properties: { objectApiName: str('Object API name.') },
      required: ['objectApiName'],
      additionalProperties: false,
    },
  },
  {
    name: 'read_page',
    description:
      'Read the visible text of the current Salesforce page. Use when the rep refers to something on screen that is not in a record field (related lists, components, path, errors).',
    input_schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'click_page_element',
    description:
      'Click a button, tab, or link on the Salesforce page by its visible label (e.g. "Edit", "Related", "New Contact"). Asks the rep to confirm. Prefer API tools for data changes.',
    input_schema: {
      type: 'object',
      properties: {
        label: str('Visible text or accessible label of the element.'),
        summary: str('Plain-English confirmation line.'),
      },
      required: ['label', 'summary'],
      additionalProperties: false,
    },
  },
];

const SCHEMAS = Object.fromEntries(TOOL_DEFINITIONS.map((t) => [t.name, t.input_schema]));

/** Light JSON-schema check of the top-level tool input. Returns an error string or null. */
export function validateToolInput(name, input) {
  const schema = SCHEMAS[name];
  if (!schema) return `Unknown tool: ${name}`;
  if (!input || typeof input !== 'object' || Array.isArray(input)) return 'Input must be an object.';
  for (const key of schema.required || []) {
    if (input[key] === undefined || input[key] === null || input[key] === '') return `Missing required field: ${key}`;
  }
  for (const [key, value] of Object.entries(input)) {
    const prop = schema.properties[key];
    if (!prop) return `Unexpected field: ${key}`;
    const actual = Array.isArray(value) ? 'array' : value === null ? 'null' : typeof value;
    if (actual !== prop.type) return `Field ${key} must be ${prop.type}, got ${actual}.`;
    if (prop.pattern && !new RegExp(prop.pattern).test(value)) return `Field ${key} is not a valid Salesforce Id.`;
  }
  return null;
}

function compactRecord(record) {
  if (!record || typeof record !== 'object') return record;
  const out = {};
  for (const [k, v] of Object.entries(record)) {
    if (k === 'attributes' || v === null) continue;
    out[k] = v && typeof v === 'object' && !Array.isArray(v) ? compactRecord(v) : v;
  }
  return out;
}

function compactDescribe(d) {
  return {
    name: d.name,
    label: d.label,
    fields: d.fields.map((f) => {
      const field = { name: f.name, label: f.label, type: f.type };
      if (f.updateable) field.updateable = true;
      if (f.createable && !f.nillable && !f.defaultedOnCreate) field.requiredOnCreate = true;
      if (f.referenceTo?.length) field.referenceTo = f.referenceTo;
      const values = (f.picklistValues || []).filter((p) => p.active);
      if (values.length) field.picklistValues = values.slice(0, 50).map((p) => p.value);
      return field;
    }),
  };
}

/** Run a function in the Salesforce tab. world: 'MAIN' sees Lightning's $A. */
async function inTab(tabId, func, args = [], world = 'ISOLATED') {
  const [res] = await chrome.scripting.executeScript({ target: { tabId }, world, func, args });
  return res?.result;
}

async function navigate(env, recordId) {
  const fired = await inTab(
    env.tabId,
    (id) => {
      try {
        const evt = window.$A?.get('e.force:navigateToSObject');
        if (!evt) return false;
        evt.setParams({ recordId: id });
        evt.fire();
        return true;
      } catch {
        return false;
      }
    },
    [recordId],
    'MAIN',
  ).catch(() => false);
  if (!fired) await chrome.tabs.update(env.tabId, { url: env.sf.recordUrl(recordId) });
}

async function confirmOrDecline(env, summary, { force = false } = {}) {
  if (!force && !env.settings.confirmWrites) return null;
  const answer = await env.confirm(summary);
  if (answer.approved) return null;
  return {
    declined: true,
    message: answer.note
      ? `The rep declined and said: "${answer.note}". Adjust to what they want.`
      : 'The rep declined this action. Do not retry it; ask what they want instead.',
  };
}

const HANDLERS = {
  async get_record({ objectApiName, recordId, fields }, env) {
    return compactRecord(await env.sf.getRecord(objectApiName, recordId, fields));
  },

  async describe_object({ objectApiName }, env) {
    return compactDescribe(await env.sf.describe(objectApiName));
  },

  async soql_query({ query }, env) {
    if (!/^\s*select\b/i.test(query)) throw new Error('Only SELECT queries are allowed.');
    const r = await env.sf.query(query);
    return { totalSize: r.totalSize, records: r.records.slice(0, 50).map(compactRecord) };
  },

  async get_lead_statuses(_input, env) {
    return env.sf.leadStatuses();
  },

  async update_record({ objectApiName, recordId, fields, summary }, env) {
    if (objectApiName.toLowerCase() === 'lead' && 'Status' in fields) {
      const statuses = await env.sf.leadStatuses();
      const target = statuses.find(
        (s) => [s.value, s.label].some((v) => v.toLowerCase() === String(fields.Status).toLowerCase()),
      );
      if (target?.isConverted) {
        return {
          error:
            `"${fields.Status}" is a converted Lead Status. It can only be set by Lead Conversion. ` +
            'Use convert_lead instead, which also creates the Account, Contact and Opportunity.',
        };
      }
    }
    const declined = await confirmOrDecline(env, summary);
    if (declined) return declined;
    await env.sf.updateRecord(objectApiName, recordId, fields);
    env.emit({ type: 'record_link', label: `Updated ${objectApiName}`, url: env.sf.recordUrl(recordId) });
    return { success: true };
  },

  async create_record({ objectApiName, fields, summary }, env) {
    const declined = await confirmOrDecline(env, summary);
    if (declined) return declined;
    const r = await env.sf.createRecord(objectApiName, fields);
    env.emit({ type: 'record_link', label: `New ${objectApiName}`, url: env.sf.recordUrl(r.id) });
    return { success: true, id: r.id };
  },

  async convert_lead(input, env) {
    if (input.contactId && !input.accountId) {
      return { error: 'contactId requires accountId (the Account that Contact belongs to).' };
    }
    // Conversion can't be undone from the UI, so it always asks, whatever the setting.
    const declined = await confirmOrDecline(env, input.summary, { force: true });
    if (declined) return declined;

    const r = await env.sf.convertLead(input);
    const links = [
      ['Account', r.accountId],
      ['Contact', r.contactId],
      ['Opportunity', r.opportunityId],
    ].filter(([, id]) => isSalesforceId(id));
    for (const [label, id] of links) env.emit({ type: 'record_link', label, url: env.sf.recordUrl(id) });
    return {
      success: true,
      accountId: r.accountId,
      contactId: r.contactId,
      opportunityId: r.opportunityId || null,
      accountAttachedToExisting: Boolean(input.accountId),
      contactMergedIntoExisting: Boolean(input.contactId),
    };
  },

  async refresh_page(_input, env) {
    const refreshed = await inTab(
      env.tabId,
      () => {
        try {
          const evt = window.$A?.get('e.force:refreshView');
          if (!evt) return false;
          evt.fire();
          return true;
        } catch {
          return false;
        }
      },
      [],
      'MAIN',
    ).catch(() => false);
    if (!refreshed) await chrome.tabs.reload(env.tabId);
    return { success: true };
  },

  async navigate_to_record({ recordId }, env) {
    await navigate(env, recordId);
    return { success: true };
  },

  async open_list_view({ objectApiName }, env) {
    await chrome.tabs.update(env.tabId, { url: `${env.sf.lightningBase}/lightning/o/${objectApiName}/list` });
    return { success: true };
  },

  async read_page(_input, env) {
    const text = await inTab(env.tabId, () => {
      const root = document.querySelector('.oneContent, .active.oneContent, main') || document.body;
      return root.innerText.replace(/\n{3,}/g, '\n\n').slice(0, 8000);
    });
    return { text: text || '' };
  },

  async click_page_element({ label, summary }, env) {
    const declined = await confirmOrDecline(env, summary);
    if (declined) return declined;
    const clicked = await inTab(
      env.tabId,
      (wanted) => {
        const target = wanted.trim().toLowerCase();
        const selector = 'button, a, [role="button"], [role="tab"], [role="menuitem"], [role="option"], lightning-button';
        const candidates = [];
        const walk = (root) => {
          root.querySelectorAll(selector).forEach((el) => candidates.push(el));
          root.querySelectorAll('*').forEach((el) => el.shadowRoot && walk(el.shadowRoot));
        };
        walk(document);
        const visible = (el) => {
          const r = el.getBoundingClientRect();
          return r.width > 0 && r.height > 0;
        };
        const name = (el) =>
          (el.getAttribute('aria-label') || el.getAttribute('title') || el.innerText || el.textContent || '')
            .trim()
            .toLowerCase();
        const el =
          candidates.find((c) => visible(c) && name(c) === target) ||
          candidates.find((c) => visible(c) && name(c).includes(target));
        if (!el) return false;
        el.click();
        return true;
      },
      [label],
    );
    return clicked ? { success: true } : { error: `No visible element labelled "${label}" on the page.` };
  },
};

/** Execute a tool call. Errors come back as {error} so the model can recover. */
export async function runTool(name, input, env) {
  const invalid = validateToolInput(name, input);
  if (invalid) return { error: invalid };
  try {
    return await HANDLERS[name](input, env);
  } catch (err) {
    return { error: err.message, errorCode: err.errorCode };
  }
}

export const isWriteTool = (name) =>
  ['update_record', 'create_record', 'convert_lead', 'click_page_element'].includes(name);
