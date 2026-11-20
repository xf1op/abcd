'use strict';

const DEFAULTS = Object.freeze({
  hideStandout: true,
  hideRecommended: true,
  keepOnlyContinueAndFavorites: true,
  collapseSidebar: false,
  hideSidebar: false,
  accessoryLimitEnabled: true,
  regionProviderId: '',
  recentServers: {}
});

const ACCESSORY_TYPE_IDS = new Set([8, 41, 42, 43, 44, 45, 46, 47, 64, 65, 66, 67, 68, 69, 70, 71, 72]);

async function getSettings() {
  return chrome.storage.local.get(DEFAULTS);
}

async function getAccessoryCount() {
  const response = await fetch('https://avatar.roblox.com/v4/avatar', {
    method: 'GET',
    credentials: 'include',
    cache: 'no-store',
    headers: { Accept: 'application/json' }
  });
  if (!response.ok) throw new Error(`Roblox avatar API returned HTTP ${response.status}`);

  const avatar = await response.json();
  const assets = Array.isArray(avatar.assets) ? avatar.assets : [];
  const accessoryAssets = assets.filter((asset) => {
    const typeId = Number(asset?.assetType?.id ?? asset?.assetTypeId);
    return ACCESSORY_TYPE_IDS.has(typeId);
  });

  return {
    count: accessoryAssets.length,
    limit: 10,
    assets: accessoryAssets.map((asset) => ({
      id: Number(asset.id),
      name: String(asset.name || 'Accessory'),
      assetTypeId: Number(asset?.assetType?.id ?? asset?.assetTypeId)
    }))
  };
}

async function getPublicOutfits(userId) {
  if (!/^\d{1,20}$/.test(String(userId))) throw new Error('Invalid Roblox user ID.');

  const url = new URL(`https://avatar.roblox.com/v2/avatar/users/${userId}/outfits`);
  url.searchParams.set('itemsPerPage', '25');
  url.searchParams.set('page', '1');

  // Public outfit data is requested without sending the logged-in Roblox cookies.
  const response = await fetch(url, {
    method: 'GET',
    credentials: 'omit',
    cache: 'no-store',
    headers: { Accept: 'application/json' }
  });
  if (!response.ok) throw new Error(`Roblox outfit API returned HTTP ${response.status}`);

  const payload = await response.json();
  const data = Array.isArray(payload.data) ? payload.data : [];
  return data.map((outfit) => ({
    id: Number(outfit.id),
    name: String(outfit.name || `Outfit ${outfit.id}`),
    isEditable: Boolean(outfit.isEditable),
    outfitType: String(outfit.outfitType || '')
  })).filter((outfit) => Number.isFinite(outfit.id));
}

function lookupRegionWithProvider(providerId, placeId, serverId) {
  return new Promise((resolve, reject) => {
    if (!/^[a-p]{32}$/.test(String(providerId || ''))) {
      reject(new Error('Enter the 32-character ID of a compatible region-provider extension.'));
      return;
    }

    chrome.runtime.sendMessage(providerId, {
      type: 'ROVALRA_LOCAL_REGION_LOOKUP',
      payload: { placeId: String(placeId), serverId: String(serverId) }
    }, (response) => {
      if (chrome.runtime.lastError) {
        reject(new Error('The region-provider extension did not respond.'));
        return;
      }
      if (!response || typeof response.region !== 'string') {
        reject(new Error('The region-provider returned an unsupported response.'));
        return;
      }
      resolve(response.region);
    });
  });
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || typeof message.type !== 'string') return false;

  if (message.type === 'GET_SETTINGS') {
    getSettings().then(sendResponse).catch((error) => sendResponse({ error: error.message }));
    return true;
  }
  if (message.type === 'GET_ACCESSORY_COUNT') {
    getAccessoryCount().then(sendResponse).catch((error) => sendResponse({ error: error.message }));
    return true;
  }
  if (message.type === 'GET_PUBLIC_OUTFITS') {
    getPublicOutfits(message.userId)
      .then((outfits) => sendResponse({ outfits }))
      .catch((error) => sendResponse({ error: error.message }));
    return true;
  }
  if (message.type === 'LOOKUP_SERVER_REGION') {
    getSettings()
      .then((settings) => lookupRegionWithProvider(settings.regionProviderId, message.placeId, message.serverId))
      .then((region) => sendResponse({ region }))
      .catch((error) => sendResponse({ error: error.message }));
    return true;
  }
  return false;
});
