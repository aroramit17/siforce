import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildConvertLeadEnvelope, parseConvertLeadResponse } from '../src/background/soap.js';

test('envelope escapes values and orders elements per the partner WSDL', () => {
  const xml = buildConvertLeadEnvelope('00D!abc<&>', {
    leadId: '00Q5g00000AbCdEEAV',
    convertedStatus: 'Closed - Converted',
    opportunityName: 'Smith & Sons <Q3>',
  });
  assert.match(xml, /<urn:sessionId>00D!abc&lt;&amp;&gt;<\/urn:sessionId>/);
  assert.match(xml, /<urn:opportunityName>Smith &amp; Sons &lt;Q3&gt;<\/urn:opportunityName>/);
  assert.match(xml, /<urn:doNotCreateOpportunity>false</);
  assert.doesNotMatch(xml, /accountId/);
  const order = ['convertedStatus', 'doNotCreateOpportunity', 'leadId', 'opportunityName', 'overwriteLeadSource', 'sendNotificationEmail'];
  const positions = order.map((t) => xml.indexOf(`<urn:${t}>`));
  assert.deepEqual([...positions].sort((a, b) => a - b), positions);
});

test('no opportunity drops opportunityName', () => {
  const xml = buildConvertLeadEnvelope('sid', { leadId: '00Q5g00000AbCdE', convertedStatus: 'Qualified', createOpportunity: false, opportunityName: 'x' });
  assert.match(xml, /<urn:doNotCreateOpportunity>true</);
  assert.doesNotMatch(xml, /opportunityName/);
});

test('parses a successful conversion', () => {
  const r = parseConvertLeadResponse(`<?xml version="1.0"?><soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="urn:partner.soap.sforce.com"><soapenv:Body><convertLeadResponse><result><accountId>0015g00000AAAAAAA1</accountId><contactId>0035g00000BBBBBBB2</contactId><leadId>00Q5g00000AbCdEEAV</leadId><opportunityId>0065g00000CCCCCCC3</opportunityId><success>true</success></result></convertLeadResponse></soapenv:Body></soapenv:Envelope>`);
  assert.equal(r.success, true);
  assert.equal(r.accountId, '0015g00000AAAAAAA1');
  assert.equal(r.opportunityId, '0065g00000CCCCCCC3');
  assert.deepEqual(r.errors, []);
});

test('parses per-record errors and SOAP faults', () => {
  const r = parseConvertLeadResponse(`<soapenv:Envelope xmlns:soapenv="x"><soapenv:Body><convertLeadResponse><result><accountId xsi:nil="true"/><errors><message>Converted status is invalid</message><statusCode>INVALID_STATUS</statusCode></errors><success>false</success></result></convertLeadResponse></soapenv:Body></soapenv:Envelope>`);
  assert.equal(r.success, false);
  assert.deepEqual(r.errors, [{ statusCode: 'INVALID_STATUS', message: 'Converted status is invalid' }]);

  const f = parseConvertLeadResponse(`<soapenv:Envelope><soapenv:Body><soapenv:Fault><faultcode>sf:INVALID_SESSION_ID</faultcode><faultstring>INVALID_SESSION_ID: Invalid Session ID</faultstring></soapenv:Fault></soapenv:Body></soapenv:Envelope>`);
  assert.equal(f.success, false);
  assert.equal(f.errors[0].statusCode, 'sf:INVALID_SESSION_ID');
});
