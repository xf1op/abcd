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
const AVATAR_SELECTION_TYPES = [0, 1, 2, 3, 4, 5];

let cachedCsrfToken = '';
let equipQueue = Promise.resolve();

async function getSettings() {
  return chrome.storage.local.get(DEFAULTS);
}

function getAvatarUrl() {
  const url = new URL('https://avatar.roblox.com/v4/avatar');
  for (const type of AVATAR_SELECTION_TYPES) {
    url.searchParams.append('selectionTypes', String(type));
  }
  return url.toString();
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

  // Roblox may return the required CSRF token in the first 403 response.
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
  const avatar = await robloxJson(getAvatarUrl());
  const assets = avatar?.avatarModel?.assets;

  if (!Array.isArray(assets)) {
    throw new Error('Roblox returned an unexpected avatar response; no changes were made.');
  }

  return assets;
}

function getAssetTypeId(asset) {
  const id = Number(asset?.assetType?.id ?? asset?.assetTypeId ?? asset?.type?.id);
  return Number.isInteger(id) ? id : null;
}

function isAccessory(asset) {
  return ACCESSORY_TYPE_IDS.has(getAssetTypeId(asset));
}

function toWearAsset(asset) {
  const id = Number(asset?.id);
  if (!Number.isSafeInteger(id) || id <= 0) {
    throw new Error('Roblox returned an invalid equipped asset; no changes were made.');
  }

  const result = { id };
  if (asset.meta && typeof asset.meta === 'object' && !Array.isArray(asset.meta)) {
    result.meta = asset.meta;
  }
  return result;
}

async function updateAvatarAssets(assets) {
  const body = {
    updateTypes: ['UpdateAssets'],
    avatarDefinition: {
      updateAvatarModel: { assets }
    }
  };

  const result = await robloxJson('https://avatar.roblox.com/v4/avatar', {
    method: 'PATCH',
    body: JSON.stringify(body)
  });

  const invalidAssets = [
    ...(Array.isArray(result.invalidAssets) ? result.invalidAssets : []),
    ...(Array.isArray(result.validation?.invalidAssets) ? result.validation.invalidAssets : [])
  ];

  if (result.success === false || invalidAssets.length) {
    throw new Error('Roblox rejected one or more avatar assets; the change was not reported as successful.');
  }

  return result;
}

async function equipAccessory(rawAssetId) {
  const assetId = Number(rawAssetId);
  if (!Number.isSafeInteger(assetId) || assetId <= 0) {
    throw new Error('Invalid accessory ID.');
  }

  const currentAssets = await getCurrentAvatarAssets();
  const currentIds = new Set(
    currentAssets.map((asset) => Number(asset?.id))
      .filter((id) => Number.isSafeInteger(id) && id > 0)
  );

  if (currentIds.has(assetId)) {
    return {
      success: true,
      alreadyEquipped: true,
      count: currentAssets.filter(isAccessory).length,
      limit: ACCESSORY_LIMIT
    };
  }

  const currentlyEquippedAccessories = currentAssets.filter(isAccessory);
  const currentCount = currentlyEquippedAccessories.length;
  const removeCount = Math.max(0, currentCount - (ACCESSORY_LIMIT - 1));
  const removeIds = new Set();

  // No history, timestamps, observer, or per-item storage is kept.
  // Below 10/10: remove nothing. At 10/10: choose exactly one random
  // currently equipped accessory. This selection exists only for this click.
  while (removeIds.size < removeCount) {
    const choice = Math.floor(Math.random() * currentlyEquippedAccessories.length);
    removeIds.add(Number(currentlyEquippedAccessories[choice].id));
  }

  const retainedAssets = currentAssets.filter((asset) => !removeIds.has(Number(asset?.id)));
  const payloadAssets = retainedAssets.map(toWearAsset);
  payloadAssets.push({ id: assetId });

  await updateAvatarAssets(payloadAssets);

  return {
    success: true,
    alreadyEquipped: false,
    count: Math.min(ACCESSORY_LIMIT, currentCount + 1 - removeIds.size),
    limit: ACCESSORY_LIMIT,
    replaced: removeIds.size
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
      assetTypeName: String(asset?.assetType?.name || asset?.type?.name || '')
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
