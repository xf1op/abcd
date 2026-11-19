'use strict';

(() => {
  const DEFAULTS = {
    hideStandout: true,
    hideRecommended: true,
    keepOnlyContinueAndFavorites: true,
    collapseSidebar: false,
    hideSidebar: false,
    accessoryLimitEnabled: true,
    recentServers: {}
  };

  const ACCESSORY_TYPE_IDS = new Set([8, 41, 42, 43, 44, 45, 46, 47, 64, 65, 66, 67, 68, 69, 70, 71, 72]);
  const SERVER_CARD_SELECTOR = [
    '[data-gameid]', '[data-game-id]', '[data-server-id]', '[data-serverid]',
    '.rbx-game-server-item', '[data-testid*="server"]'
  ].join(',');

  let settings = { ...DEFAULTS };
  let observer = null;
  let refreshQueued = false;
  let accessoryCount = null;
  let accessoryWidget = null;
  let outfitWidget = null;
  let accessoryRefreshInFlight = false;
  let lastAccessoryRefresh = 0;

  const send = (message) => new Promise((resolve) => {
    chrome.runtime.sendMessage(message, (response) => {
      if (chrome.runtime.lastError) resolve({ error: chrome.runtime.lastError.message });
      else resolve(response || {});
    });
  });

  function isHomePage() {
    const path = location.pathname.replace(/^\/[a-z]{2}(?:-[a-z]{2})?\//i, '/');
    return path === '/home' || path === '/';
  }

  function isProfilePage() {
    return /\/users\/(\d+)\/(?:profile)?\/?$/i.test(location.pathname);
  }

  function getProfileUserId() {
    return location.pathname.match(/\/users\/(\d+)\//i)?.[1] || null;
  }

  function applyLayoutSettings() {
    document.body.classList.toggle('rv-local-sidebar-collapsed', settings.collapseSidebar === true);
    document.body.classList.toggle('rv-local-sidebar-hidden', settings.hideSidebar === true);
  }

  function queuePageRefresh() {
    if (refreshQueued) return;
    refreshQueued = true;
    setTimeout(() => {
      refreshQueued = false;
      applyLayoutSettings();
      ensureAccessoryWidget();
      ensureOutfitWidget();
    }, 160);
  }

  function startObserver() {
    if (observer || !document.body) return;
    observer = new MutationObserver(queuePageRefresh);
    const root = document.querySelector('#container-main') || document.querySelector('main') || document.body;
    observer.observe(root, { childList: true, subtree: true });
  }

  function getCurrentPlaceId() {
    return location.pathname.match(/\/games\/(\d+)/i)?.[1] || null;
  }

  function getServerCard(target) {
    return target instanceof Element ? target.closest(SERVER_CARD_SELECTOR) : null;
  }

  function getServerId(card) {
    if (!card) return null;
    const candidates = [
      card.getAttribute('data-gameid'),
      card.getAttribute('data-game-id'),
      card.getAttribute('data-server-id'),
      card.getAttribute('data-serverid'),
      card.dataset?.gameid,
      card.dataset?.gameId,
      card.dataset?.serverId,
      card.dataset?.serverid,
      card.id
    ];
    for (const candidate of candidates) {
      if (candidate && /^[\w-]{6,100}$/.test(String(candidate))) return String(candidate);
    }
    return null;
  }

  async function saveRecentServer(placeId, serverId) {
    const stored = await chrome.storage.local.get({ recentServers: {} });
    const all = stored.recentServers || {};
    const existing = Array.isArray(all[placeId]) ? all[placeId] : [];
    const gameName = (document.querySelector('h1')?.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 100);
    const next = [
      { serverId, gameName, selectedAt: Date.now(), state: 'selected' },
      ...existing.filter((entry) => entry.serverId !== serverId)
    ].slice(0, 5);
    all[placeId] = next;
    await chrome.storage.local.set({ recentServers: all });
  }

  document.addEventListener('click', (event) => {
    const placeId = getCurrentPlaceId();
    if (!placeId) return;
    const card = getServerCard(event.target);
    const serverId = getServerId(card);
    if (serverId) saveRecentServer(placeId, serverId).catch(() => {});
  }, true);

  function accessoryTypeFromElement(target) {
    let node = target instanceof Element ? target : null;
    for (let depth = 0; node && depth < 7; depth++, node = node.parentElement) {
      const values = [
        node.getAttribute('data-asset-type-id'),
        node.getAttribute('data-assettypeid'),
        node.getAttribute('data-asset-type'),
        node.getAttribute('data-assettype')
      ];
      for (const value of values) {
        if (!value) continue;
        const numeric = Number(value);
        if (Number.isInteger(numeric) && ACCESSORY_TYPE_IDS.has(numeric)) return numeric;
        const normalized = String(value).toLowerCase();
        if (/accessory|hair|hat|neck|shoulder|front|back|waist|shoe|skirt|jacket|sweater|shorts/.test(normalized)) return 1;
      }
    }
    return null;
  }

  function isWearAction(target) {
    const button = target instanceof Element ? target.closest('button,[role="button"]') : null;
    if (!button) return false;
    const label = `${button.textContent || ''} ${button.getAttribute('aria-label') || ''} ${button.getAttribute('data-testid') || ''}`.toLowerCase();
    return /wear|add to avatar|equip|put on/.test(label);
  }

  function showNotice(message) {
    let notice = document.getElementById('rv-local-notice');
    if (!notice) {
      notice = document.createElement('div');
      notice.id = 'rv-local-notice';
      notice.setAttribute('role', 'status');
      document.body.appendChild(notice);
    }
    notice.textContent = message;
    notice.classList.add('rv-local-notice-visible');
    clearTimeout(notice._hideTimer);
    notice._hideTimer = setTimeout(() => notice.classList.remove('rv-local-notice-visible'), 2600);
  }

  document.addEventListener('click', (event) => {
    if (!settings.accessoryLimitEnabled || !location.pathname.startsWith('/my/avatar')) return;
    if (accessoryCount === null || accessoryCount < 10) return;
    if (!isWearAction(event.target)) return;
    if (accessoryTypeFromElement(event.target) === null) return;

    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    showNotice('Accessory limit reached (10). Remove an accessory before adding another.');
  }, true);

  async function refreshAccessoryCount(force = false) {
    if (!settings.accessoryLimitEnabled || accessoryRefreshInFlight) return;
    if (!force && Date.now() - lastAccessoryRefresh < 15000) return;
    accessoryRefreshInFlight = true;
    lastAccessoryRefresh = Date.now();
    const response = await send({ type: 'GET_ACCESSORY_COUNT' });
    accessoryRefreshInFlight = false;

    if (response?.error) {
      accessoryCount = null;
      updateAccessoryWidget('Could not read your avatar accessory count.');
      return;
    }

    accessoryCount = Number(response.count);
    updateAccessoryWidget(`${accessoryCount}/10 accessories equipped`);
  }

  function updateAccessoryWidget(text) {
    if (!accessoryWidget) return;
    const label = accessoryWidget.querySelector('[data-rv-count]');
    if (label) label.textContent = text;
  }

  function ensureAccessoryWidget() {
    if (!settings.accessoryLimitEnabled || !location.pathname.startsWith('/my/avatar')) {
      accessoryWidget?.remove();
      accessoryWidget = null;
      return;
    }
    if (accessoryWidget?.isConnected) return;

    accessoryWidget = document.createElement('aside');
    accessoryWidget.id = 'rv-local-accessory-widget';
    accessoryWidget.innerHTML = '<strong>Accessory limit</strong><span data-rv-count>Checking…</span><button type="button" data-rv-refresh>Refresh</button>';
    accessoryWidget.querySelector('[data-rv-refresh]').addEventListener('click', () => refreshAccessoryCount(true));
    (document.querySelector('main') || document.body).appendChild(accessoryWidget);
    refreshAccessoryCount(true);
  }

  function ensureOutfitWidget() {
    if (!isProfilePage()) {
      outfitWidget?.remove();
      outfitWidget = null;
      return;
    }
    if (outfitWidget?.isConnected) return;
    const userId = getProfileUserId();
    if (!userId) return;

    outfitWidget = document.createElement('section');
    outfitWidget.id = 'rv-local-outfits-widget';
    outfitWidget.innerHTML = '<div class="rv-local-widget-heading"><strong>Public outfits</strong><button type="button" data-rv-load-outfits>Load</button></div><div data-rv-outfits-result>Not loaded. Requests go directly to Roblox and are not stored.</div>';
    outfitWidget.querySelector('[data-rv-load-outfits]').addEventListener('click', async () => {
      const result = outfitWidget.querySelector('[data-rv-outfits-result]');
      result.textContent = 'Loading public outfits…';
      const response = await send({ type: 'GET_PUBLIC_OUTFITS', userId });
      if (response.error) {
        result.textContent = response.error;
        return;
      }
      const outfits = Array.isArray(response.outfits) ? response.outfits : [];
      if (!outfits.length) {
        result.textContent = 'No public outfits returned.';
        return;
      }
      const list = document.createElement('ul');
      for (const outfit of outfits) {
        const item = document.createElement('li');
        item.textContent = `${outfit.name} · ID ${outfit.id}`;
        list.appendChild(item);
      }
      result.replaceChildren(list);
    });

    const host = document.querySelector('#profile-container') || document.querySelector('main') || document.body;
    host.prepend(outfitWidget);
  }

  async function initialize() {
    settings = { ...DEFAULTS, ...(await chrome.storage.local.get(DEFAULTS)) };
    applyLayoutSettings();
    queuePageRefresh();
    startObserver();
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area !== 'local') return;
      if (Object.keys(changes).some((key) => key in DEFAULTS)) {
        chrome.storage.local.get(DEFAULTS).then((next) => {
          settings = { ...DEFAULTS, ...next };
          queuePageRefresh();
          if (location.pathname.startsWith('/my/avatar')) refreshAccessoryCount(true);
        });
      }
    });
  }

  initialize().catch(() => {});
})();
