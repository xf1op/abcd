'use strict';

const DEFAULTS = Object.freeze({ cleanHomePage: true, sidebarEnabled: true, sidebarCollapsed: true });
const cleanHomePageInput = document.getElementById('cleanHomePage');
const sidebarEnabledInput = document.getElementById('sidebarEnabled');
const saveStatus = document.getElementById('saveStatus');
const resetButton = document.getElementById('resetSettings');

async function loadSettings() {
  const values = { ...DEFAULTS, ...(await chrome.storage.local.get(DEFAULTS)) };
  cleanHomePageInput.checked = values.cleanHomePage === true;
  sidebarEnabledInput.checked = values.sidebarEnabled === true;
}

cleanHomePageInput.addEventListener('change', async () => {
  try {
    await chrome.storage.local.set({ cleanHomePage: cleanHomePageInput.checked });
    saveStatus.textContent = 'Saved locally.';
  } catch {
    saveStatus.textContent = 'Could not save this setting.';
  }
});

sidebarEnabledInput.addEventListener('change', async () => {
  try {
    await chrome.storage.local.set({ sidebarEnabled: sidebarEnabledInput.checked });
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
