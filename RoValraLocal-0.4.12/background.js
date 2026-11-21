'use strict';

const API_ORIGIN = 'https://avatar.roblox.com';
const THUMBNAIL_ORIGIN = 'https://thumbnails.roblox.com';
const PAGE_SIZE = 100;
const REQUEST_GAP_MS = 1200;
const CACHE_TTL_MS = 30000;
const DEFAULT_RETRY_MS = 15000;
const MAX_RETRY_MS = 3600000;

const originQueues = new Map();
const lastRequestAt = new Map();
const responseCache = new Map();

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
  if (response.status !== 429) return 0;
  const headers = response.headers;
  const retryMsHeader = headers.get('retry-after-ms') || headers.get('retry-in-ms');
  const retryHeader = headers.get('retry-after') || headers.get('retry-in');
  const resetHeader = headers.get('ratelimit-reset') || headers.get('x-ratelimit-reset');
  let duration = parseRetryValue(retryMsHeader, 'milliseconds') ||
    parseRetryValue(retryHeader) || parseRetryValue(resetHeader);

  const error = payload?.errors?.[0];
  const bodySeconds = error?.retryAfterSeconds ?? error?.retryAfter ?? error?.retryInSeconds ?? error?.retryIn ??
    payload?.retryAfterSeconds ?? payload?.retryAfter ?? payload?.retryInSeconds ?? payload?.retryIn;
  if (!duration && bodySeconds !== undefined) duration = parseRetryValue(bodySeconds);

  if (!duration) {
    const message = String(payload?.errors?.[0]?.message || payload?.message || '');
    const match = message.match(/retry(?:\s|-)?(?:in|after)\s*[:=]?\s*(\d+(?:\.\d+)?)\s*(ms|milliseconds?|s|seconds?)?/i);
    if (match) duration = parseRetryValue(match[1], /^m/i.test(match[2] || '') ? 'milliseconds' : 'seconds');
  }

  return Math.min(MAX_RETRY_MS, Math.max(1000, duration || DEFAULT_RETRY_MS));
}

function jsonResult(response, payload) {
  return {
    ok: response.ok,
    status: response.status,
    payload,
    message: payload?.errors?.[0]?.message || payload?.message || '',
    retryAfterMs: retryAfterMs(response, payload)
  };
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
  if (cached) return cached;

  const origin = url.origin;
  const previous = originQueues.get(origin) || Promise.resolve();
  const task = previous.catch(() => {}).then(async () => {
    const elapsed = Date.now() - (lastRequestAt.get(origin) || 0);
    const wait = REQUEST_GAP_MS - elapsed;
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
    lastRequestAt.set(origin, Date.now());

    const response = await fetch(url, options);
    const payload = await response.json().catch(() => null);
    const result = jsonResult(response, payload);
    if (result.ok) setCached(cacheKey, result);
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
    credentials: 'omit',
    cache: 'default',
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
  if (!message || !['RVLOCAL_OUTFITS_PAGE', 'RVLOCAL_OUTFITS_THUMBNAILS'].includes(message.type)) {
    return false;
  }
  if (!isRobloxContentSender(sender)) {
    sendResponse({ ok: false, status: 403, message: 'Request is not from a Roblox page.' });
    return false;
  }

  const operation = message.type === 'RVLOCAL_OUTFITS_PAGE'
    ? fetchOutfitPage(message)
    : fetchOutfitThumbnails(message);

  operation
    .then(sendResponse)
    .catch(() => sendResponse({ ok: false, status: 0, message: 'Roblox API request failed.', retryAfterMs: 0 }));
  return true;
});
