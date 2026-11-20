'use strict';

const DEFAULTS = {
  hideStandout: true,
  hideRecommended: true,
  keepOnlyContinueAndFavorites: true,
  collapseSidebar: false,
  hideSidebar: false,
  accessoryLimitEnabled: true,
  regionProviderId: '',
  recentServers: {}
};

const SETTING_IDS = [
  'hideStandout',
  'hideRecommended',
  'keepOnlyContinueAndFavorites',
  'collapseSidebar',
  'hideSidebar',
  'accessoryLimitEnabled'
];

const $ = (id) => document.getElementById(id);

function send(message) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage(message, (response) => {
      if (chrome.runtime.lastError) resolve({ error: chrome.runtime.lastError.message });
      else resolve(response || {});
    });
  });
}

async function loadSettings() {
  const settings = await chrome.storage.local.get(DEFAULTS);
  for (const id of SETTING_IDS) $(id).checked = settings[id] === true;
  $('regionProviderId').value = settings.regionProviderId || '';
  renderHistory(settings.recentServers || {});
}

async function saveCheckbox(id) {
  await chrome.storage.local.set({ [id]: $(id).checked });
}

function makeText(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  node.textContent = text;
  return node;
}

function renderHistory(recentServers) {
  const host = $('recentServers');
  host.replaceChildren();
  const groups = Object.entries(recentServers || {}).filter(([, entries]) => Array.isArray(entries) && entries.length);
  if (!groups.length) {
    host.appendChild(makeText('p', 'empty', 'No server selections saved yet.'));
    return;
  }

  for (const [placeId, entries] of groups.sort((a, b) => (b[1][0]?.selectedAt || 0) - (a[1][0]?.selectedAt || 0))) {
    const group = makeText('div', 'game-history', '');
    group.appendChild(makeText('div', 'game-title', `${entries[0]?.gameName || 'Roblox experience'} · Place ${placeId}`));
    for (const entry of entries.slice(0, 5)) {
      const row = makeText('div', 'server-row', '');
      row.appendChild(makeText('span', 'server-id', entry.serverId));
      const result = makeText('span', 'region-result', '');
      const button = makeText('button', 'region-button', 'Region');
      button.type = 'button';
      button.addEventListener('click', async () => {
        button.disabled = true;
        result.textContent = 'Checking…';
        const response = await send({ type: 'LOOKUP_SERVER_REGION', placeId, serverId: entry.serverId });
        result.textContent = response.region || response.error || 'Unavailable';
        button.disabled = false;
      });
      row.append(button, result);
      group.appendChild(row);
    }
    host.appendChild(group);
  }
}

async function saveProviderId() {
  const value = $('regionProviderId').value.trim();
  await chrome.storage.local.set({ regionProviderId: value });
  $('providerStatus').textContent = value ? 'Saved locally.' : 'Provider cleared.';
}

async function clearHistory() {
  await chrome.storage.local.set({ recentServers: {} });
  renderHistory({});
}

async function resetSettings() {
  await chrome.storage.local.set(DEFAULTS);
  await loadSettings();
}

SETTING_IDS.forEach((id) => $(id).addEventListener('change', () => saveCheckbox(id)));
$('saveProvider').addEventListener('click', saveProviderId);
$('clearHistory').addEventListener('click', clearHistory);
$('resetSettings').addEventListener('click', resetSettings);
loadSettings();
