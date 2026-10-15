// Talks to the Salesforce org the user is already logged into, using their
// browser session (the same approach as Salesforce Inspector). No connected
// app or OAuth setup needed: the extension reads the `sid` cookie.

import { apiHostFromLightningHost } from '../shared/context.js';
import { buildConvertLeadEnvelope, parseConvertLeadResponse } from './soap.js';

const FALLBACK_API_VERSION = '62.0';
const SID_DOMAINS = ['salesforce.com', 'cloudforce.com', 'salesforce.mil', 'force.com'];

export class SalesforceError extends Error {
  constructor(message, { status, errorCode, details } = {}) {
    super(message);
    this.name = 'SalesforceError';
    this.status = status;
    this.errorCode = errorCode;
    this.details = details;
  }
}

const sessionCache = new Map(); // page host -> {apiHost, sid, version}

/**
 * Find a session usable for API calls. Lightning-domain cookies are not valid
 * against the API, so match the org id from the page's cookie to the `sid` on
 * the org's my.salesforce.com domain.
 */
async function findSession(pageHost) {
  const pageSid = await chrome.cookies.get({ url: `https://${pageHost}`, name: 'sid' });
  const orgId = pageSid?.value.split('!')[0];

  if (orgId) {
    for (const domain of SID_DOMAINS) {
      const cookies = await chrome.cookies.getAll({ name: 'sid', domain, secure: true });
      const match = cookies.find(
        (c) =>
          c.value.startsWith(orgId + '!') &&
          !c.domain.includes('lightning.force.com') &&
          !c.domain.includes('visualforce.com'),
      );
      if (match) return { apiHost: match.domain.replace(/^\./, ''), sid: match.value };
    }
  }

  // Fallback: derive the my.salesforce.com host directly.
  const apiHost = apiHostFromLightningHost(pageHost);
  const sid = await chrome.cookies.get({ url: `https://${apiHost}`, name: 'sid' });
  if (sid) return { apiHost, sid: sid.value };

  throw new SalesforceError(
    'Could not find a Salesforce session. Make sure you are logged in to Salesforce in this browser.',
  );
}

export class SalesforceClient {
  /** @param {string} pageHost  host of the tab, e.g. acme.lightning.force.com */
  constructor(pageHost) {
    this.pageHost = pageHost;
  }

  async session() {
    if (!sessionCache.has(this.pageHost)) {
      const s = await findSession(this.pageHost);
      s.version = await detectApiVersion(s).catch(() => FALLBACK_API_VERSION);
      sessionCache.set(this.pageHost, s);
    }
    return sessionCache.get(this.pageHost);
  }

  /** Lightning base URL for links shown to the user. */
  get lightningBase() {
    return `https://${this.pageHost}`;
  }

  recordUrl(recordId) {
    return `${this.lightningBase}/lightning/r/${recordId}/view`;
  }

  async rest(method, path, body, { retried = false } = {}) {
    const s = await this.session();
    const res = await fetch(`https://${s.apiHost}/services/data/v${s.version}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${s.sid}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    if (res.status === 401 && !retried) {
      // Session rotated (re-login, different org); look it up again once.
      sessionCache.delete(this.pageHost);
      return this.rest(method, path, body, { retried: true });
    }
    if (res.status === 204) return null;

    const text = await res.text();
    const data = text ? JSON.parse(text) : null;
    if (!res.ok) {
      const first = Array.isArray(data) ? data[0] : data;
      throw new SalesforceError(first?.message || `Salesforce returned HTTP ${res.status}`, {
        status: res.status,
        errorCode: first?.errorCode,
        details: data,
      });
    }
    return data;
  }

  query(soql) {
    return this.rest('GET', `/query?q=${encodeURIComponent(soql)}`);
  }

  getRecord(objectApiName, recordId, fields) {
    const qs = fields?.length ? `?fields=${encodeURIComponent(fields.join(','))}` : '';
    return this.rest('GET', `/sobjects/${objectApiName}/${recordId}${qs}`);
  }

  describe(objectApiName) {
    return this.rest('GET', `/sobjects/${objectApiName}/describe`);
  }

  updateRecord(objectApiName, recordId, fields) {
    return this.rest('PATCH', `/sobjects/${objectApiName}/${recordId}`, fields);
  }

  createRecord(objectApiName, fields) {
    return this.rest('POST', `/sobjects/${objectApiName}`, fields);
  }

  async leadStatuses() {
    try {
      const r = await this.query(
        'SELECT MasterLabel, ApiName, IsConverted, IsDefault, SortOrder FROM LeadStatus ORDER BY SortOrder',
      );
      return r.records.map((s) => ({
        value: s.ApiName || s.MasterLabel,
        label: s.MasterLabel,
        isConverted: s.IsConverted,
        isDefault: s.IsDefault,
      }));
    } catch {
      // Very old API versions lack LeadStatus.ApiName.
      const r = await this.query(
        'SELECT MasterLabel, IsConverted, IsDefault, SortOrder FROM LeadStatus ORDER BY SortOrder',
      );
      return r.records.map((s) => ({
        value: s.MasterLabel,
        label: s.MasterLabel,
        isConverted: s.IsConverted,
        isDefault: s.IsDefault,
      }));
    }
  }

  async convertLead(options) {
    const s = await this.session();
    const res = await fetch(`https://${s.apiHost}/services/Soap/u/${s.version}`, {
      method: 'POST',
      headers: { 'Content-Type': 'text/xml; charset=utf-8', SOAPAction: '""' },
      body: buildConvertLeadEnvelope(s.sid, options),
    });
    const result = parseConvertLeadResponse(await res.text());
    if (!result.success) {
      const msg = result.errors.map((e) => `${e.statusCode}: ${e.message}`).join('; ');
      throw new SalesforceError(msg || `Lead conversion failed (HTTP ${res.status})`, {
        status: res.status,
        details: result.errors,
      });
    }
    return result;
  }
}

async function detectApiVersion({ apiHost, sid }) {
  const res = await fetch(`https://${apiHost}/services/data/`, {
    headers: { Authorization: `Bearer ${sid}`, Accept: 'application/json' },
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const versions = await res.json();
  return versions[versions.length - 1].version;
}
