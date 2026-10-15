// Lead conversion is not exposed as a REST resource, so it goes through the SOAP
// partner API's convertLead() call. Service workers have no DOMParser, so the
// response is read with small, targeted regexes; the payload is tiny and flat.

export function xmlEscape(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

/**
 * @param {string} sessionId
 * @param {object} c
 * @param {string} c.leadId
 * @param {string} c.convertedStatus
 * @param {string} [c.accountId]        attach to an existing Account instead of creating one
 * @param {string} [c.contactId]        attach to an existing Contact (requires accountId)
 * @param {boolean} [c.createOpportunity=true]
 * @param {string} [c.opportunityName]
 * @param {string} [c.ownerId]
 * @param {boolean} [c.sendNotificationEmail=false]
 */
export function buildConvertLeadEnvelope(sessionId, c) {
  const field = (name, value) =>
    value === undefined || value === null || value === ''
      ? ''
      : `<urn:${name}>${xmlEscape(value)}</urn:${name}>`;
  const createOpp = c.createOpportunity !== false;

  return `<?xml version="1.0" encoding="utf-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:partner.soap.sforce.com">
  <soapenv:Header>
    <urn:SessionHeader><urn:sessionId>${xmlEscape(sessionId)}</urn:sessionId></urn:SessionHeader>
  </soapenv:Header>
  <soapenv:Body>
    <urn:convertLead>
      <urn:leadConverts>
        ${field('accountId', c.accountId)}
        ${field('contactId', c.contactId)}
        ${field('convertedStatus', c.convertedStatus)}
        <urn:doNotCreateOpportunity>${createOpp ? 'false' : 'true'}</urn:doNotCreateOpportunity>
        ${field('leadId', c.leadId)}
        ${createOpp ? field('opportunityName', c.opportunityName) : ''}
        <urn:overwriteLeadSource>false</urn:overwriteLeadSource>
        ${field('ownerId', c.ownerId)}
        <urn:sendNotificationEmail>${c.sendNotificationEmail ? 'true' : 'false'}</urn:sendNotificationEmail>
      </urn:leadConverts>
    </urn:convertLead>
  </soapenv:Body>
</soapenv:Envelope>`;
}

function tag(xml, name) {
  // Matches <name>..</name> with or without a namespace prefix; nil elements yield null.
  const m = xml.match(new RegExp(`<(?:\\w+:)?${name}(?:\\s[^>]*)?>([\\s\\S]*?)</(?:\\w+:)?${name}>`));
  return m ? decode(m[1].trim()) : null;
}

function decode(s) {
  return s
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

/**
 * @returns {{success: boolean, accountId?: string, contactId?: string, opportunityId?: string,
 *            leadId?: string, errors: {statusCode: string|null, message: string|null}[]}}
 */
export function parseConvertLeadResponse(xml) {
  const fault = tag(xml, 'faultstring');
  if (fault) {
    return { success: false, errors: [{ statusCode: tag(xml, 'faultcode'), message: fault }] };
  }
  const result = tag(xml, 'result') || '';
  const errors = [];
  const errRe = /<(?:\w+:)?errors>([\s\S]*?)<\/(?:\w+:)?errors>/g;
  let m;
  while ((m = errRe.exec(result))) {
    errors.push({ statusCode: tag(m[1], 'statusCode'), message: tag(m[1], 'message') });
  }
  return {
    success: tag(result, 'success') === 'true',
    accountId: tag(result, 'accountId') || undefined,
    contactId: tag(result, 'contactId') || undefined,
    opportunityId: tag(result, 'opportunityId') || undefined,
    leadId: tag(result, 'leadId') || undefined,
    errors,
  };
}
