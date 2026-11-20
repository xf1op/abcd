'use strict';

(() => {
  const DEFAULTS = {
    cleanHomePage: true,
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
  let outfitControl = null;
  let accessoryRefreshInFlight = false;
  let lastAccessoryRefresh = 0;
  let outfitCache = { userId: null, outfits: null, error: null, loading: false };
  let domFilterStats = { scans: 0, headingsFound: 0, hiddenSections: 0, unresolvedSections: 0 };

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
    return /\/users\/(\d+)(?:\/profile)?\/?$/i.test(location.pathname);
  }

  function getProfileUserId() {
    return location.pathname.match(/\/users\/(\d+)(?:\/|$)/i)?.[1] || null;
  }

  function applyLayoutSettings() {
    if (!document.body) return;
    document.body.classList.toggle('rv-local-sidebar-collapsed', settings.collapseSidebar === true);
    document.body.classList.toggle('rv-local-sidebar-hidden', settings.hideSidebar === true);
  }

  function normalizeHeading(value) {
    return String(value || '').replace(/\s+/g, ' ').trim().replace(/[!:.]+$/, '').toLowerCase();
  }

  function isKeptFeedHeading(label) {
    return label === 'continue' || label === 'continue playing' ||
      label === 'favorites' || label === 'favourites';
  }

  function isStandoutHeading(label) {
    return /^(standout games?|standout games? for you)$/.test(label);
  }

  function isRecommendedHeading(label) {
    return /^(recommended for you|recommendations?|discover|sponsored)(?:\s|$)/.test(label);
  }

  function isFriendsHeading(label) {
    return /^(friends|friends are playing|friends activity|friends playing)(?:\s|$)/.test(label);
  }

  function isRecognizedFeedHeading(label) {
    return isKeptFeedHeading(label) || isStandoutHeading(label) ||
      isRecommendedHeading(label) || isFriendsHeading(label);
  }

  function shouldHideFeedHeading(label) {
    return settings.cleanHomePage === true && isRecognizedFeedHeading(label) &&
      !isKeptFeedHeading(label);
  }

  function findHomeSectionRoot(heading) {
    let node = heading;
    const sectionLike = 'section,[data-testid*="sort" i],[data-testid*="carousel" i],[data-testid*="section" i],[class*="sort-container" i],[class*="carousel" i],[class*="section-container" i]';
    const cardLike = 'a[href*="/games/"],[data-testid*="game-card" i],[data-testid*="game-tile" i],[data-testid*="friend" i],[class*="game-card" i],[class*="GameCard"]';

    for (let depth = 0; depth < 9; depth += 1) {
      node = node.parentElement;
      if (!node || node === document.body || node.matches('main,#container-main')) break;

      const label = node.dataset?.rvLocalSectionLabel;
      const competingHeadings = Array.from(node.querySelectorAll(
        'h1,h2,h3,[role="heading"],[data-testid*="title" i],[class*="section-title" i],[class*="heading" i]'
      ))
        .filter((candidate) => {
          if (candidate === heading || candidate.contains(heading) || heading.contains(candidate)) return false;
          return isRecognizedFeedHeading(normalizeHeading(candidate.textContent));
        });
      const cards = node.querySelectorAll(cardLike).length;
      const semanticSection = node.matches(sectionLike);

      if (competingHeadings.length > 0) continue;
      if (semanticSection && (cards >= 1 || node.children.length >= 3)) return node;
      if (cards >= 2 && node.children.length >= 2) return node;
      if (label) return node;
    }

    return null;
  }

  function applyHomeFeedDomFilter() {
    if (!document.documentElement) return;
    if (!isHomePage()) {
      document.documentElement.dataset.rvLocalFeedDomHidden = '0';
      document.documentElement.dataset.rvLocalFeedDomUnresolved = '0';
      document.documentElement.dataset.rvLocalFeedDomLabels = '';
      return;
    }

    domFilterStats.scans += 1;
    const root = document.querySelector('#container-main') || document.querySelector('main') || document.body;
    if (!root) return;

    const headings = [];
    const seenHeadingNodes = new Set();
    const headingSelector = 'h1,h2,h3,h4,[role="heading"],[data-testid*="title" i],[class*="section-title" i],[class*="heading" i]';

    // Roblox has used plain div/span elements for feed titles. Keep the
    // semantic selectors, then add exact-text matches as a fallback.
    for (const heading of root.querySelectorAll(headingSelector)) {
      if (!seenHeadingNodes.has(heading)) {
        seenHeadingNodes.add(heading);
        headings.push(heading);
      }
    }
    for (const element of root.querySelectorAll('div,span')) {
      if (element.childElementCount > 3) continue;
      const rawText = String(element.textContent || '').trim();
      if (!rawText || rawText.length > 70) continue;
      if (!isRecognizedFeedHeading(normalizeHeading(rawText))) continue;
      if (!seenHeadingNodes.has(element)) {
        seenHeadingNodes.add(element);
        headings.push(element);
      }
    }

    domFilterStats.headingsFound = headings.length;
    let hidden = 0;
    let unresolved = 0;
    const hiddenContainers = new Set();

    for (const heading of headings) {
      const label = normalizeHeading(heading.textContent);
      if (!shouldHideFeedHeading(label)) continue;

      const section = findHomeSectionRoot(heading);
      if (!section) {
        unresolved += 1;
        continue;
      }

      if (!hiddenContainers.has(section)) {
        hiddenContainers.add(section);
        section.classList.add('rv-local-hide-home-section');
        section.dataset.rvLocalSectionLabel = label;
        hidden += 1;
      }
    }

    // Restore sections immediately when the user disables the corresponding option.
    for (const section of root.querySelectorAll('.rv-local-hide-home-section')) {
      const label = section.dataset.rvLocalSectionLabel || '';
      if (!shouldHideFeedHeading(label)) {
        section.classList.remove('rv-local-hide-home-section');
        delete section.dataset.rvLocalSectionLabel;
      }
    }

    domFilterStats.hiddenSections = hidden;
    domFilterStats.unresolvedSections = unresolved;
    document.documentElement.dataset.rvLocalFeedDomHidden = String(hidden);
    document.documentElement.dataset.rvLocalFeedDomUnresolved = String(unresolved);
    document.documentElement.dataset.rvLocalFeedDomLabels = Array.from(hiddenContainers)
      .map((section) => section.dataset.rvLocalSectionLabel || '')
      .filter(Boolean).join(',');
  }

  function queuePageRefresh() {
    if (refreshQueued) return;
    refreshQueued = true;
    setTimeout(() => {
      refreshQueued = false;
      applyLayoutSettings();
      applyHomeFeedDomFilter();
      ensureAccessoryWidget();
      ensureOutfitControl();
    }, 160);
  }

  function startObserver() {
    if (observer || !document.body) return;
    observer = new MutationObserver(queuePageRefresh);
    const root = document.querySelector('#container-main') || document.querySelector('main') || document.body;
    observer.observe(root, { childList: true, subtree: true });
  }

  window.addEventListener('popstate', queuePageRefresh);
  window.addEventListener('hashchange', queuePageRefresh);

  function getCurrentPlaceId() {
    return location.pathname.match(/\/games\/(\d+)/i)?.[1] || null;
  }

  function getServerCard(target) {
    return target instanceof Element ? target.closest(SERVER_CARD_SELECTOR) : null;
  }

  function getServerId(card) {
    if (!card) return null;
    const candidates = [
      card.getAttribute('data-gameid'), card.getAttribute('data-game-id'),
      card.getAttribute('data-server-id'), card.getAttribute('data-serverid'),
      card.dataset?.gameid, card.dataset?.gameId, card.dataset?.serverId, card.dataset?.serverid,
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
    all[placeId] = [
      { serverId, gameName, selectedAt: Date.now(), state: 'selected' },
      ...existing.filter((entry) => entry.serverId !== serverId)
    ].slice(0, 5);
    await chrome.storage.local.set({ recentServers: all });
  }

  document.addEventListener('click', (event) => {
    const placeId = getCurrentPlaceId();
    if (!placeId) return;
    const serverId = getServerId(getServerCard(event.target));
    if (serverId) saveRecentServer(placeId, serverId).catch(() => {});
  }, true);

  function accessoryTypeFromElement(target) {
    let node = target instanceof Element ? target : null;
    for (let depth = 0; node && depth < 7; depth += 1, node = node.parentElement) {
      const values = [
        node.getAttribute('data-asset-type-id'), node.getAttribute('data-assettypeid'),
        node.getAttribute('data-asset-type'), node.getAttribute('data-assettype')
      ];
      for (const value of values) {
        if (!value) continue;
        const numeric = Number(value);
        if (Number.isInteger(numeric) && ACCESSORY_TYPE_IDS.has(numeric)) return numeric;
        if (/accessory|hair|hat|neck|shoulder|front|back|waist|shoe|skirt|jacket|sweater|shorts/i.test(String(value))) return 1;
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
    if (accessoryCount === null || accessoryCount < 10 || !isWearAction(event.target)) return;
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
    const label = accessoryWidget?.querySelector('[data-rv-count]');
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

  function getProfileRoot() {
    return document.querySelector('#profile-container') ||
      document.querySelector('[data-testid*="profile-header"]') ||
      document.querySelector('.profile-header-container') ||
      document.querySelector('main');
  }

  function isVisibleElement(element) {
    if (!element || !element.isConnected) return false;
    const style = getComputedStyle(element);
    return style.display !== 'none' && style.visibility !== 'hidden' && element.getClientRects().length > 0;
  }

  function findChatAction(root) {
    if (!root) return null;
    const selector = [
      '#user-profile-header-Chat', '#profile-chat-btn',
      'button', 'a', '[role="button"]', '[tabindex]', '[aria-label]', '[title]',
      '[data-testid]', '[data-action="Chat" i]', '[data-action-name="Chat" i]',
      '[class*="chat" i]', '[id*="chat" i]'
    ].join(',');
    const candidates = Array.from(root.querySelectorAll(selector));

    for (const element of candidates) {
      if (!isVisibleElement(element)) continue;
      const parts = [
        element.getAttribute('aria-label'), element.getAttribute('title'),
        element.getAttribute('data-testid'), element.id,
        typeof element.className === 'string' ? element.className : '',
        element.textContent
      ];
      const label = normalizeHeading(parts.filter(Boolean).join(' '));
      if (!/\bchat\b/.test(label)) continue;
      const action = element.matches('button,a,[role="button"],[tabindex]')
        ? element
        : element.closest('button,a,[role="button"],[tabindex]');
      if (action && isVisibleElement(action)) return action;
      if (element.matches('[class*="chat" i],[id*="chat" i]')) return element;
    }
    return null;
  }

  function profileActionProbe(root) {
    if (!root) return 'no-profile-root';
    const nodes = Array.from(root.querySelectorAll('button,a,[role="button"],[tabindex]'))
      .filter(isVisibleElement)
      .slice(0, 12);
    if (!nodes.length) return 'no-visible-actions';
    return nodes.map((element) => {
      const text = normalizeHeading(element.textContent).slice(0, 24);
      const aria = normalizeHeading(element.getAttribute('aria-label')).slice(0, 24);
      const title = normalizeHeading(element.getAttribute('title')).slice(0, 24);
      const testId = String(element.getAttribute('data-testid') || '').slice(0, 30);
      const cls = (typeof element.className === 'string' ? element.className : '').trim().slice(0, 36);
      return [element.tagName.toLowerCase(), text, aria, title, testId, cls].filter(Boolean).join('|');
    }).join(' ; ');
  }

  function setOutfitPanelMessage(panel, message) {
    const status = panel.querySelector('[data-rv-outfits-status]');
    if (status) status.textContent = message;
  }

  function renderOutfits(panel, outfits) {
    const list = panel.querySelector('[data-rv-outfits-list]');
    const status = panel.querySelector('[data-rv-outfits-status]');
    if (!list || !status) return;
    list.replaceChildren();

    if (!outfits.length) {
      status.textContent = 'No public outfits were returned for this player.';
      return;
    }

    status.textContent = `${outfits.length} public outfit${outfits.length === 1 ? '' : 's'}`;
    for (const outfit of outfits) {
      const row = document.createElement('li');
      const name = document.createElement('span');
      name.className = 'rv-local-outfit-name';
      name.textContent = outfit.name || `Outfit ${outfit.id}`;
      const id = document.createElement('span');
      id.className = 'rv-local-outfit-id';
      id.textContent = `#${outfit.id}`;
      row.append(name, id);
      list.appendChild(row);
    }
  }

  async function loadOutfitsForControl(control, userId) {
    const panel = control.querySelector('[data-rv-outfits-panel]');
    if (!panel) return;

    if (outfitCache.userId === userId && Array.isArray(outfitCache.outfits)) {
      renderOutfits(panel, outfitCache.outfits);
      return;
    }
    if (outfitCache.userId === userId && outfitCache.loading) return;

    outfitCache = { userId, outfits: null, error: null, loading: true };
    setOutfitPanelMessage(panel, 'Loading public outfits from Roblox…');
    const response = await send({ type: 'GET_PUBLIC_OUTFITS', userId });

    if (outfitControl !== control || !control.isConnected) return;
    if (response?.error) {
      outfitCache = { userId, outfits: null, error: response.error, loading: false };
      setOutfitPanelMessage(panel, response.error);
      return;
    }

    const outfits = Array.isArray(response.outfits) ? response.outfits : [];
    outfitCache = { userId, outfits, error: null, loading: false };
    renderOutfits(panel, outfits);
  }

  function createOutfitControl(userId) {
    const control = document.createElement('span');
    control.id = 'rv-local-outfit-control';
    control.dataset.userId = userId;

    const button = document.createElement('button');
    button.id = 'rv-local-outfits-button';
    button.type = 'button';
    button.textContent = 'Outfits';
    button.setAttribute('aria-expanded', 'false');
    button.setAttribute('aria-haspopup', 'true');
    button.setAttribute('aria-controls', 'rv-local-outfits-panel');

    const panel = document.createElement('div');
    panel.id = 'rv-local-outfits-panel';
    panel.dataset.rvOutfitsPanel = '';
    panel.hidden = true;

    const heading = document.createElement('div');
    heading.className = 'rv-local-outfits-panel-heading';
    heading.textContent = 'Public outfits';
    const status = document.createElement('p');
    status.dataset.rvOutfitsStatus = '';
    status.textContent = 'Open to load this player’s public outfits.';
    const list = document.createElement('ul');
    list.dataset.rvOutfitsList = '';
    const note = document.createElement('p');
    note.className = 'rv-local-outfits-note';
    note.textContent = 'Fetched directly from Roblox. Not saved by RoValra Local.';
    panel.append(heading, status, list, note);
    control.append(button, panel);

    button.setAttribute('aria-label', 'View public outfits');
    button.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      const opening = panel.hidden;
      panel.hidden = !opening;
      button.setAttribute('aria-expanded', String(opening));
      if (opening) loadOutfitsForControl(control, userId);
    });

    return control;
  }

  function ensureOutfitControl() {
    if (!isProfilePage()) {
      outfitControl?.remove();
      outfitControl = null;
      document.documentElement.dataset.rvLocalOutfitButton = 'not-profile';
      return;
    }

    const userId = getProfileUserId();
    const root = getProfileRoot();
    if (!userId || !root) return;

    if (outfitControl?.isConnected && outfitControl.dataset.userId === userId) return;
    outfitControl?.remove();
    outfitControl = null;

    let chatAction = findChatAction(root);
    if (!chatAction) chatAction = findChatAction(document);
    if (!chatAction) {
      document.documentElement.dataset.rvLocalOutfitButton = 'waiting-for-chat-action';
      document.documentElement.dataset.rvLocalOutfitProbe = profileActionProbe(root);
      return;
    }

    outfitControl = createOutfitControl(userId);
    chatAction.insertAdjacentElement('afterend', outfitControl);
    document.documentElement.dataset.rvLocalOutfitButton = 'attached';
    delete document.documentElement.dataset.rvLocalOutfitProbe;
  }

  document.addEventListener('click', (event) => {
    if (!outfitControl?.isConnected || outfitControl.contains(event.target)) return;
    const panel = outfitControl.querySelector('[data-rv-outfits-panel]');
    const button = outfitControl.querySelector('#rv-local-outfits-button');
    if (panel && !panel.hidden) {
      panel.hidden = true;
      button?.setAttribute('aria-expanded', 'false');
    }
  });

  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || !outfitControl?.isConnected) return;
    const panel = outfitControl.querySelector('[data-rv-outfits-panel]');
    const button = outfitControl.querySelector('#rv-local-outfits-button');
    if (panel && !panel.hidden) {
      panel.hidden = true;
      button?.setAttribute('aria-expanded', 'false');
      button?.focus();
    }
  });

  async function initialize() {
    settings = { ...DEFAULTS, ...(await chrome.storage.local.get(DEFAULTS)) };
    applyLayoutSettings();
    queuePageRefresh();
    startObserver();

    chrome.storage.onChanged.addListener((changes, area) => {
      if (area !== 'local' || !Object.keys(changes).some((key) => key in DEFAULTS)) return;
      chrome.storage.local.get(DEFAULTS).then((next) => {
        settings = { ...DEFAULTS, ...next };
        queuePageRefresh();
        if (location.pathname.startsWith('/my/avatar')) refreshAccessoryCount(true);
      });
    });
  }

  initialize().catch(() => {});
})();
