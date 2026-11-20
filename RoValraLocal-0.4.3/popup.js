'use strict';

const DEFAULTS = Object.freeze({ cleanHomePage: true });
const cleanHomePageInput = document.getElementById('cleanHomePage');
const saveStatus = document.getElementById('saveStatus');
const resetButton = document.getElementById('resetSettings');

async function loadSettings() {
  const values = { ...DEFAULTS, ...(await chrome.storage.local.get(DEFAULTS)) };
  cleanHomePageInput.checked = values.cleanHomePage === true;
}

cleanHomePageInput.addEventListener('change', async () => {
  try {
    await chrome.storage.local.set({ cleanHomePage: cleanHomePageInput.checked });
    saveStatus.textContent = 'Saved locally.';
  } catch {
    saveStatus.textContent = 'Could not save this setting.';
  }
});

resetButton.addEventListener('click', async () => {
  try {
    await chrome.storage.local.set(DEFAULTS);
    await loadSettings();
    saveStatus.textContent = 'Default restored.';
  } catch {
    saveStatus.textContent = 'Could not reset settings.';
  }
});

loadSettings().catch(() => {
  saveStatus.textContent = 'Could not load settings.';
});
