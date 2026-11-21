'use strict';

const API_ORIGIN = 'https://avatar.roblox.com';
const THUMBNAIL_ORIGIN = 'https://thumbnails.roblox.com';
const USER_SETTINGS_ORIGIN = 'https://apis.roblox.com';
const PAGE_SIZE = 100;
const REQUEST_GAP_MS = 1200;
const CACHE_TTL_MS = 30000;
const DEFAULT_RETRY_MS = 15000;
const MAX_RETRY_MS = 3600000;

const originQueues = new Map();
const lastRequestAt = new Map();
const responseCache = new Map();
const originRateLimitUntil = new Map();

function isRobloxContentSender(sender) {
  const source = sender?.url || sender?.tab?.url || '';
  try {
    const url = new URL(source);
    return url.protocol === 'https:' && url.hostname === 'www.roblox.com';
  } catch {
    return false;
  }
}

function validUserId(value) {
  const id = String(value ?? '');
  return /^\d{1,20}$/.test(id) ? id : null;
}

function parseRetryValue(value, unit = 'seconds') {
  if (value === null || value === undefined || value === '') return 0;
  const numeric = Number(value);
  if (Number.isFinite(numeric)) {
    if (unit === 'milliseconds') return numeric;
    if (numeric > 1e12) return numeric - Date.now();
    if (numeric > 1e9) return numeric * 1000 - Date.now();
    return numeric * 1000;
  }
  const timestamp = Date.parse(String(value));
  return Number.isFinite(timestamp) ? timestamp - Date.now() : 0;
}

function retryAfterMs(response, payload) {
  const headers = response.headers;
  const remainingRaw = headers.get('x-ratelimit-remaining');
  const remaining = remainingRaw == null ? null : Number.parseInt(remainingRaw, 10);
  const resetRaw = headers.get('x-ratelimit-reset') || headers.get('ratelimit-reset');
  const resetMs = parseRetryValue(resetRaw);

  if (response.status === 429) {
    const retryMsHeader = headers.get('retry-after-ms') || headers.get('retry-in-ms');
    const retryHeader = headers.get('retry-after') || headers.get('retry-in');
    let duration = parseRetryValue(retryMsHeader, 'milliseconds') ||
      parseRetryValue(retryHeader) || resetMs;

    const error = payload?.errors?.[0];
    const bodySeconds = error?.retryAfterSeconds ?? error?.retryAfter ?? error?.retryInSeconds ?? error?.retryIn ??
      payload?.retryAfterSeconds ?? payload?.retryAfter ?? payload?.retryInSeconds ?? payload?.retryIn;
    if (!duration && bodySeconds !== undefined) duration = parseRetryValue(bodySeconds);

    if (!duration) {
      const message = String(payload?.errors?.[0]?.message || payload?.message || '');
      const match = message.match(/retry(?:\s|\-)?(?:in|after)\s*[:=]?\s*(\d+(?:\.\d+)?)\s*(ms|milliseconds?|s|seconds?)?/i);
      if (match) duration = parseRetryValue(match[1], /^m/i.test(match[2] || '') ? 'milliseconds' : 'seconds');
    }

    return Math.min(MAX_RETRY_MS, Math.max(1000, duration || DEFAULT_RETRY_MS));
  }

  if (Number.isFinite(remaining) && remaining <= 0 && resetMs > 0) {
    return Math.min(MAX_RETRY_MS, Math.max(1000, resetMs));
  }

  return 0;
}

function jsonResult(response, payload) {
  const remainingRaw = response.headers.get('x-ratelimit-remaining');
  const remaining = remainingRaw == null ? null : Number.parseInt(remainingRaw, 10);
  return {
    ok: response.ok,
    status: response.status,
    payload,
    message: payload?.errors?.[0]?.message || payload?.message || '',
    rateLimitRemaining: Number.isFinite(remaining) ? remaining : null,
    retryAfterMs: retryAfterMs(response, payload)
  };
}


async function fetchUserPrivacySettings() {
  const url = `${USER_SETTINGS_ORIGIN}/user-settings-api/v1/user-settings/settings-and-options`;
  try {
    const response = await fetch(url, {
      method: 'GET',
      credentials: 'include',
      cache: 'no-store',
      headers: { Accept: 'application/json' }
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      return {
        ok: false,
        status: response.status,
        message: payload?.errors?.[0]?.message || payload?.message || 'Could not read Roblox privacy settings.'
      };
    }
    return { ok: true, status: response.status, payload };
  } catch {
    return { ok: false, status: 0, message: 'Could not connect to Roblox privacy settings.' };
  }
}

async function postUserPrivacySettings(values) {
  const allowedKeys = [
    'whoCanSeeMyInventory',
    'whoCanSeeMyOnlineStatus',
    'whoCanJoinMeInExperiences'
  ];
  if (!values || typeof values !== 'object' || Array.isArray(values)) {
    return { ok: false, status: 400, message: 'Invalid privacy settings.' };
  }
  const entries = Object.entries(values);
  if (!entries.length || entries.length > allowedKeys.length ||
      entries.some(([key, value]) => !allowedKeys.includes(key) ||
        typeof value !== 'string' || !value || value.length > 64)) {
    return { ok: false, status: 400, message: 'Invalid privacy settings.' };
  }

  const url = `${USER_SETTINGS_ORIGIN}/user-settings-api/v1/user-settings`;
  const request = async (csrfToken) => {
    const headers = {
      Accept: 'application/json',
      'Content-Type': 'application/json'
    };
    if (csrfToken) headers['x-csrf-token'] = csrfToken;
    const response = await fetch(url, {
      method: 'POST',
      credentials: 'include',
      cache: 'no-store',
      headers,
      body: JSON.stringify(values)
    });
    const payload = await response.json().catch(() => null);
    return { response, payload };
  };

  try {
    let result = await request('');
    if (result.response.status === 403) {
      const csrfToken = result.response.headers.get('x-csrf-token');
      if (csrfToken) result = await request(csrfToken);
    }
    if (!result.response.ok) {
      return {
        ok: false,
        status: result.response.status,
        message: result.payload?.errors?.[0]?.message || result.payload?.message || 'Roblox rejected the privacy update.'
      };
    }
    return { ok: true, status: result.response.status, payload: result.payload };
  } catch {
    return { ok: false, status: 0, message: 'Could not connect to Roblox privacy settings.' };
  }
}

function getCached(key) {
  const entry = responseCache.get(key);
  if (!entry) return null;
  if (entry.expiresAt <= Date.now()) {
    responseCache.delete(key);
    return null;
  }
  return entry.value;
}

function setCached(key, value) {
  responseCache.set(key, { value, expiresAt: Date.now() + CACHE_TTL_MS });
  if (responseCache.size > 80) {
    const firstKey = responseCache.keys().next().value;
    if (firstKey) responseCache.delete(firstKey);
  }
}

async function pacedFetch(url, options, cacheKey) {
  const cached = getCached(cacheKey);
  if (cached) return { ...cached, retryAfterMs: 0 };

  const origin = url.origin;
  const previous = originQueues.get(origin) || Promise.resolve();
  const task = previous.catch(() => {}).then(async () => {
    const now = Date.now();
    const resetUntil = originRateLimitUntil.get(origin) || 0;
    const resetWait = Math.max(0, resetUntil - now);
    const elapsed = now - (lastRequestAt.get(origin) || 0);
    const pacingWait = Math.max(0, REQUEST_GAP_MS - elapsed);
    const wait = Math.max(resetWait, pacingWait);
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
    if ((originRateLimitUntil.get(origin) || 0) <= Date.now()) originRateLimitUntil.delete(origin);
    lastRequestAt.set(origin, Date.now());

    const response = await fetch(url, options);
    const payload = await response.json().catch(() => null);
    const result = jsonResult(response, payload);
    if (result.retryAfterMs > 0) {
      originRateLimitUntil.set(origin, Date.now() + result.retryAfterMs);
    }
    if (result.ok) setCached(cacheKey, { ...result, retryAfterMs: 0 });
    return result;
  });
  originQueues.set(origin, task.then(() => undefined, () => undefined));
  return task;
}

async function fetchOutfitPage(message) {
  const userId = validUserId(message.userId);
  const paginationToken = message.paginationToken == null ? '' : String(message.paginationToken);
  if (!userId || paginationToken.length > 4096) {
    return { ok: false, status: 400, message: 'Invalid profile or outfit cursor.' };
  }

  const url = new URL(`${API_ORIGIN}/v2/avatar/users/${userId}/outfits`);
  url.searchParams.set('itemsPerPage', String(PAGE_SIZE));
  url.searchParams.set('isEditable', 'true');
  if (paginationToken) url.searchParams.set('paginationToken', paginationToken);

  const cacheKey = `outfits:${url.href}`;
  return pacedFetch(url, {
    method: 'GET',
    credentials: 'include',
    cache: 'no-store',
    headers: { Accept: 'application/json' }
  }, cacheKey);
}

async function fetchOutfitThumbnails(message) {
  const ids = Array.isArray(message.outfitIds)
    ? [...new Set(message.outfitIds.map((value) => String(value)))]
    : [];
  if (!ids.length || ids.length > PAGE_SIZE || ids.some((id) => !/^\d{1,20}$/.test(id))) {
    return { ok: false, status: 400, message: 'Invalid outfit ID list.' };
  }

  const url = new URL(`${THUMBNAIL_ORIGIN}/v1/users/outfits`);
  url.searchParams.set('userOutfitIds', ids.join(','));
  url.searchParams.set('size', '150x150');
  url.searchParams.set('format', 'Png');
  url.searchParams.set('isCircular', 'false');

  const cacheKey = `thumbnails:${ids.join(',')}`;
  return pacedFetch(url, {
    method: 'GET',
    credentials: 'omit',
    cache: 'default',
    headers: { Accept: 'application/json' }
  }, cacheKey);
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  const supportedTypes = [
    'BLOXIMPROVED_OUTFITS_PAGE',
    'BLOXIMPROVED_OUTFITS_THUMBNAILS',
    'BLOXIMPROVED_PRIVACY_GET',
    'BLOXIMPROVED_PRIVACY_SET'
  ];
  if (!message || !supportedTypes.includes(message.type)) return false;
  if (!isRobloxContentSender(sender)) {
    sendResponse({ ok: false, status: 403, message: 'Request is not from a Roblox page.' });
    return false;
  }

  const operations = {
    BLOXIMPROVED_OUTFITS_PAGE: () => fetchOutfitPage(message),
    BLOXIMPROVED_OUTFITS_THUMBNAILS: () => fetchOutfitThumbnails(message),
    BLOXIMPROVED_PRIVACY_GET: () => fetchUserPrivacySettings(),
    BLOXIMPROVED_PRIVACY_SET: () => postUserPrivacySettings(message.values)
  };
  const operation = operations[message.type]();

  operation
    .then(sendResponse)
    .catch(() => sendResponse({ ok: false, status: 0, message: 'Roblox API request failed.', retryAfterMs: 0 }));
  return true;
});
