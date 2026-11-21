'use strict';

const BUTTON_KEYS = [
  'sidebarButtonProfileCard',
  'sidebarButtonHome',
  'sidebarButtonProfile',
  'sidebarButtonRobloxPlus',
  'sidebarButtonMessages',
  'sidebarButtonFriends',
  'sidebarButtonAvatar',
  'sidebarButtonInventory',
  'sidebarButtonTrade',
  'sidebarButtonCommunities',
  'sidebarButtonNewsroom',
  'sidebarButtonOfficialStore',
  'sidebarButtonGiftCards',
  'sidebarButtonPlusPromo'
];
const DEFAULTS = Object.freeze({
  cleanHomePage: true,
  sidebarEnabled: true,
  sidebarCollapsed: true,
  sidebarButtonsEnabled: true,
  sidebarButtonProfileCard: true,
  sidebarButtonHome: true,
  sidebarButtonProfile: true,
  sidebarButtonRobloxPlus: true,
  sidebarButtonMessages: true,
  sidebarButtonFriends: true,
  sidebarButtonAvatar: true,
  sidebarButtonInventory: true,
  sidebarButtonTrade: true,
  sidebarButtonCommunities: true,
  sidebarButtonNewsroom: true,
  sidebarButtonOfficialStore: true,
  sidebarButtonGiftCards: true,
  sidebarButtonPlusPromo: true
});
const cleanHomePageInput = document.getElementById('cleanHomePage');
const sidebarEnabledInput = document.getElementById('sidebarEnabled');
const sidebarButtonsEnabledInput = document.getElementById('sidebarButtonsEnabled');
const sidebarButtonList = document.getElementById('sidebarButtonList');
const saveStatus = document.getElementById('saveStatus');
const resetButton = document.getElementById('resetSettings');

async function loadSettings() {
  const values = { ...DEFAULTS, ...(await chrome.storage.local.get(DEFAULTS)) };
  cleanHomePageInput.checked = values.cleanHomePage === true;
  sidebarEnabledInput.checked = values.sidebarEnabled === true;
  sidebarButtonsEnabledInput.checked = values.sidebarButtonsEnabled === true;
  for (const key of BUTTON_KEYS) document.getElementById(key).checked = values[key] === true;
  sidebarButtonList.disabled = !sidebarButtonsEnabledInput.checked;
}

async function saveSetting(key, value) {
  try {
    await chrome.storage.local.set({ [key]: value });
    saveStatus.textContent = 'Saved locally.';
  } catch {
    saveStatus.textContent = 'Could not save this setting.';
  }
}

cleanHomePageInput.addEventListener('change', () => saveSetting('cleanHomePage', cleanHomePageInput.checked));
sidebarEnabledInput.addEventListener('change', () => saveSetting('sidebarEnabled', sidebarEnabledInput.checked));
sidebarButtonsEnabledInput.addEventListener('change', async () => {
  sidebarButtonList.disabled = !sidebarButtonsEnabledInput.checked;
  await saveSetting('sidebarButtonsEnabled', sidebarButtonsEnabledInput.checked);
});

for (const key of BUTTON_KEYS) {
  document.getElementById(key).addEventListener('change', (event) => saveSetting(key, event.currentTarget.checked));
}

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
