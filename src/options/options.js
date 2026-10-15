import { DEFAULT_SETTINGS, loadSettings } from '../shared/settings.js';

const form = document.getElementById('form');
const status = document.getElementById('status');
const fields = Object.keys(DEFAULT_SETTINGS);

const settings = await loadSettings();
for (const key of fields) {
  const input = document.getElementById(key);
  if (input.type === 'checkbox') input.checked = settings[key];
  else input.value = settings[key];
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const next = {};
  for (const key of fields) {
    const input = document.getElementById(key);
    next[key] = input.type === 'checkbox' ? input.checked : input.value.trim();
  }
  await chrome.storage.local.set(next);
  status.textContent = 'Saved. Open any Salesforce page to start talking.';
  setTimeout(() => (status.textContent = ''), 4000);
});
