export const DEFAULT_SETTINGS = {
  apiKey: '',
  model: 'claude-opus-5-5',
  effort: 'medium',
  confirmWrites: true,
  speakReplies: true,
  lang: '',
};

export async function loadSettings() {
  const stored = await chrome.storage.local.get(Object.keys(DEFAULT_SETTINGS));
  return { ...DEFAULT_SETTINGS, ...stored };
}
