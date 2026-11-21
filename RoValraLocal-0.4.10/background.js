'use strict';

const API_ORIGIN = 'https://avatar.roblox.com';
const THUMBNAIL_ORIGIN = 'https://thumbnails.roblox.com';
const PAGE_SIZE = 100;

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

function jsonResult(response, payload) {
  return {
    ok: response.ok,
    status: response.status,
    payload,
    message: payload?.errors?.[0]?.message || payload?.message || ''
  };
}

async function fetchOutfitPage(message) {
  const userId = validUserId(message.userId);
  const page = Number(message.page);
  if (!userId || !Number.isInteger(page) || page < 1 || page > 100) {
    return { ok: false, status: 400, message: 'Invalid profile or page.' };
  }

  const url = new URL(`${API_ORIGIN}/v2/avatar/users/${userId}/outfits`);
  url.searchParams.set('page', String(page));
  url.searchParams.set('itemsPerPage', String(PAGE_SIZE));
  url.searchParams.set('isEditable', 'true');
  url.searchParams.set('outfitType', 'Avatar');

  const response = await fetch(url, {
    method: 'GET',
    credentials: 'omit',
    cache: 'default',
    headers: { Accept: 'application/json' }
  });
  const payload = await response.json().catch(() => null);
  return jsonResult(response, payload);
}

async function fetchOutfitThumbnails(message) {
  const ids = Array.isArray(message.outfitIds)
    ? message.outfitIds.map((value) => String(value))
    : [];
  if (!ids.length || ids.length > PAGE_SIZE || ids.some((id) => !/^\d{1,20}$/.test(id))) {
    return { ok: false, status: 400, message: 'Invalid outfit ID list.' };
  }

  const url = new URL(`${THUMBNAIL_ORIGIN}/v1/users/outfits`);
  url.searchParams.set('userOutfitIds', ids.join(','));
  url.searchParams.set('size', '150x150');
  url.searchParams.set('format', 'Png');
  url.searchParams.set('isCircular', 'false');

  const response = await fetch(url, {
    method: 'GET',
    credentials: 'omit',
    cache: 'default',
    headers: { Accept: 'application/json' }
  });
  const payload = await response.json().catch(() => null);
  return jsonResult(response, payload);
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
    .catch(() => sendResponse({ ok: false, status: 0, message: 'Roblox API request failed.' }));
  return true;
});
