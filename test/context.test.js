import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseSalesforceUrl, apiHostFromLightningHost, objectFromId } from '../src/shared/context.js';

test('Lightning record page with object name', () => {
  const c = parseSalesforceUrl('https://acme.lightning.force.com/lightning/r/Lead/00Q5g00000AbCdEEAV/view', 'Jane Doe | Lead | Salesforce');
  assert.equal(c.pageType, 'record');
  assert.equal(c.objectApiName, 'Lead');
  assert.equal(c.recordId, '00Q5g00000AbCdEEAV');
  assert.equal(c.recordName, 'Jane Doe');
});

test('Lightning record page without object name infers it from the key prefix', () => {
  const c = parseSalesforceUrl('https://acme.lightning.force.com/lightning/r/0065g00000XyZabAAB/view');
  assert.equal(c.objectApiName, 'Opportunity');
  assert.equal(c.recordId, '0065g00000XyZabAAB');
});

test('List view and home', () => {
  assert.equal(parseSalesforceUrl('https://acme.lightning.force.com/lightning/o/Lead/list?filterName=Recent').pageType, 'list');
  assert.equal(parseSalesforceUrl('https://acme.lightning.force.com/lightning/page/home').pageType, 'home');
});

test('Classic record URL', () => {
  const c = parseSalesforceUrl('https://acme.my.salesforce.com/00Q5g00000AbCdE');
  assert.equal(c.pageType, 'record');
  assert.equal(c.objectApiName, 'Lead');
});

test('custom objects and unknown prefixes', () => {
  const c = parseSalesforceUrl('https://acme.lightning.force.com/lightning/r/Invoice__c/a015g00000AbCdEAAV/view');
  assert.equal(c.objectApiName, 'Invoice__c');
  assert.equal(objectFromId('a015g00000AbCdEAAV'), null);
});

test('API host from Lightning host, including sandboxes', () => {
  assert.equal(apiHostFromLightningHost('acme.lightning.force.com'), 'acme.my.salesforce.com');
  assert.equal(apiHostFromLightningHost('acme--uat.sandbox.lightning.force.com'), 'acme--uat.sandbox.my.salesforce.com');
});
