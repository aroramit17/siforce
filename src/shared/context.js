// Works out what the user is looking at in Salesforce from the URL and tab title.
// Pure functions so they can be unit-tested in Node.

const ID_RE = /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/;

// Well-known key prefixes, used when the URL has an Id but no object name (Classic, some Lightning URLs).
const KEY_PREFIXES = {
  '001': 'Account',
  '003': 'Contact',
  '005': 'User',
  '006': 'Opportunity',
  '00Q': 'Lead',
  '500': 'Case',
  '701': 'Campaign',
  '00T': 'Task',
  '00U': 'Event',
  '800': 'Contract',
  '801': 'Order',
  '0Q0': 'Quote',
};

export function isSalesforceId(value) {
  return typeof value === 'string' && ID_RE.test(value);
}

export function objectFromId(id) {
  if (!isSalesforceId(id)) return null;
  return KEY_PREFIXES[id.slice(0, 3)] || null;
}

/**
 * @param {string} href  window.location.href
 * @param {string} [title]  document.title, e.g. "Jane Doe | Lead | Salesforce"
 * @returns {{url: string, host: string, pageType: string, objectApiName: string|null,
 *            recordId: string|null, recordName: string|null}}
 */
export function parseSalesforceUrl(href, title = '') {
  const url = new URL(href);
  const parts = url.pathname.split('/').filter(Boolean);
  const ctx = {
    url: href,
    host: url.host,
    pageType: 'other',
    objectApiName: null,
    recordId: null,
    recordName: null,
  };

  if (parts[0] === 'lightning') {
    // /lightning/r/Lead/00Q.../view  or  /lightning/r/00Q.../view
    if (parts[1] === 'r') {
      if (isSalesforceId(parts[2])) {
        ctx.recordId = parts[2];
        ctx.objectApiName = objectFromId(parts[2]);
      } else {
        ctx.objectApiName = parts[2] || null;
        ctx.recordId = isSalesforceId(parts[3]) ? parts[3] : null;
      }
      ctx.pageType = ctx.recordId ? 'record' : 'other';
    } else if (parts[1] === 'o') {
      // /lightning/o/Lead/list  /lightning/o/Lead/new  /lightning/o/Lead/home
      ctx.objectApiName = parts[2] || null;
      const action = parts[3] || 'home';
      ctx.pageType = action === 'list' ? 'list' : action === 'new' ? 'new' : 'object-home';
    } else if (parts[1] === 'page' && parts[2] === 'home') {
      ctx.pageType = 'home';
    } else if (parts[1] === 'setup') {
      ctx.pageType = 'setup';
    }
  } else if (parts.length === 1 && isSalesforceId(parts[0])) {
    // Salesforce Classic record URL: /00Q5g00000AbCdE
    ctx.recordId = parts[0];
    ctx.objectApiName = objectFromId(parts[0]);
    ctx.pageType = 'record';
  }

  if (ctx.pageType === 'record' && title) {
    // Lightning titles look like "Jane Doe | Lead | Salesforce"
    const name = title.split('|')[0].trim();
    if (name && name.toLowerCase() !== 'salesforce') ctx.recordName = name;
  }
  return ctx;
}

/** Lightning host -> the my.salesforce.com host that accepts API calls. */
export function apiHostFromLightningHost(host) {
  return host
    .replace(/\.lightning\.force\.com$/, '.my.salesforce.com')
    .replace(/\.my\.salesforce-setup\.com$/, '.my.salesforce.com');
}
