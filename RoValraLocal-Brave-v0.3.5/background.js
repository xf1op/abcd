'use strict';

const DEFAULTS = Object.freeze({
  cleanHomePage: true,
  collapseSidebar: false,
  hideSidebar: false,
  accessoryLimitEnabled: true,
  regionProviderId: '',
  recentServers: {}
});

const ACCESSORY_LIMIT = 10;
const ACCESSORY_TYPE_IDS = new Set([
  8, 41, 42, 43, 44, 45, 46, 47,
  64, 65, 66, 67, 68, 69, 70, 71, 72, 76, 77
]);

let cachedCsrfToken = '';
let equipQueue = Promise.resolve();

async function getSettings() {
  return chrome.storage.local.get(DEFAULTS);
}

async function robloxJson(url, options = {}) {
  const method = String(options.method || 'GET').toUpperCase();
  const headers = {
    Accept: 'application/json',
    ...(options.body !== undefined ? { 'Content-Type': 'application/json' } : {}),
    ...(options.headers || {})
  };

  if (method !== 'GET' && cachedCsrfToken) {
    headers['X-CSRF-TOKEN'] = cachedCsrfToken;
  }

  const request = {
    ...options,
    method,
    credentials: options.credentials || 'include',
    cache: 'no-store',
    headers
  };

  let response = await fetch(url, request);
  let token = response.headers.get('x-csrf-token');
  if (token) cachedCsrfToken = token;

  // Roblox supplies a fresh CSRF token with the first 403 on some POST requests.
  if (response.status === 403 && method !== 'GET' && token) {
    response = await fetch(url, {
      ...request,
      headers: { ...headers, 'X-CSRF-TOKEN': token }
    });
    token = response.headers.get('x-csrf-token');
    if (token) cachedCsrfToken = token;
  }

  const raw = await response.text();
  let data = {};
  if (raw) {
    try {
      data = JSON.parse(raw);
    } catch {
      data = { raw: raw.slice(0, 300) };
    }
  }

  if (!response.ok) {
    const detail = Array.isArray(data.errors)
      ? data.errors.map((error) => error?.message).filter(Boolean).join('; ')
      : '';
    throw new Error(`Roblox Avatar API HTTP ${response.status}${detail ? `: ${detail}` : ''}`);
  }

  return data;
}

async function getCurrentAvatarAssets() {
  // This is the same authenticated endpoint/schema verified in the user's
  // browser test. Its asset type is exposed as `type.id` (some responses use
  // `assetType.id`), unlike the old v4 parser.
  const avatar = await robloxJson('https://avatar.roblox.com/v1/avatar');
  if (!avatar || !Array.isArray(avatar.assets)) {
    throw new Error('Roblox returned an unexpected avatar response; no changes were made.');
  }

  return avatar.assets;
}

function getAssetTypeId(asset) {
  const id = Number(asset?.type?.id ?? asset?.assetType?.id ?? asset?.assetTypeId);
  return Number.isInteger(id) ? id : null;
}

function isAccessory(asset) {
  return ACCESSORY_TYPE_IDS.has(getAssetTypeId(asset));
}

async function setWearingAssets(assetIds) {
  const result = await robloxJson('https://avatar.roblox.com/v1/avatar/set-wearing-assets', {
    method: 'POST',
    body: JSON.stringify({ assetIds })
  });

  const invalidIds = Array.isArray(result?.invalidAssetIds) ? result.invalidAssetIds : [];
  if (invalidIds.length) {
    throw new Error(`Roblox rejected asset IDs: ${invalidIds.slice(0, 5).join(', ')}`);
  }

  return result;
}

async function equipAccessory(rawAssetId) {
  const assetId = Number(rawAssetId);
  if (!Number.isSafeInteger(assetId) || assetId <= 0) {
    throw new Error('Invalid accessory ID.');
  }

  const currentAssets = await getCurrentAvatarAssets();
  const currentIds = currentAssets
    .map((asset) => Number(asset?.id))
    .filter((id) => Number.isSafeInteger(id) && id > 0);

  if (currentIds.includes(assetId)) {
    return {
      success: true,
      alreadyEquipped: true,
      count: currentAssets.filter(isAccessory).length,
      limit: ACCESSORY_LIMIT
    };
  }

  const equippedAccessories = currentAssets.filter(isAccessory);
  const currentCount = equippedAccessories.length;

  // Exactly one replacement at 10 or above. Never remove two items to force
  // an over-limit avatar down to nine; one click means at most one removal.
  let removedAssetId = null;
  if (currentCount >= ACCESSORY_LIMIT && equippedAccessories.length) {
    const randomIndex = Math.floor(Math.random() * equippedAccessories.length);
    removedAssetId = Number(equippedAccessories[randomIndex].id);
  }

  // Keep every currently worn asset, except the one random accessory selected
  // above. The legacy set-wearing-assets endpoint accepts the full asset ID
  // list and avoids the normal single-item Wear handler's category swapping.
  const nextAssetIds = currentIds.filter((id) => id !== removedAssetId);
  if (!nextAssetIds.includes(assetId)) nextAssetIds.push(assetId);

  await setWearingAssets(nextAssetIds);

  return {
    success: true,
    alreadyEquipped: false,
    count: currentCount + 1 - (removedAssetId === null ? 0 : 1),
    limit: ACCESSORY_LIMIT,
    replaced: removedAssetId !== null ? 1 : 0,
    removedAssetId
  };
}

function enqueueEquip(assetId) {
  const task = equipQueue.then(() => equipAccessory(assetId));
  equipQueue = task.catch(() => {});
  return task;
}

async function getAccessoryCount() {
  const assets = await getCurrentAvatarAssets();
  const equipped = assets.filter(isAccessory);

  return {
    count: equipped.length,
    limit: ACCESSORY_LIMIT,
    assets: equipped.map((asset) => ({
      id: Number(asset.id),
      name: String(asset.name || 'Accessory'),
      assetTypeId: getAssetTypeId(asset),
      assetTypeName: String(asset?.type?.name || asset?.assetType?.name || '')
    }))
  };
}

async function getPublicOutfits(userId) {
  if (!/^\d{1,20}$/.test(String(userId))) throw new Error('Invalid Roblox user ID.');

  const url = new URL(`https://avatar.roblox.com/v2/avatar/users/${userId}/outfits`);
  url.searchParams.set('itemsPerPage', '25');
  url.searchParams.set('page', '1');

  const payload = await robloxJson(url.toString(), {
    method: 'GET',
    credentials: 'omit'
  });

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

  if (message.type === 'EQUIP_ACCESSORY') {
    enqueueEquip(message.assetId)
      .then(sendResponse)
      .catch((error) => sendResponse({ error: error.message || String(error) }));
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
