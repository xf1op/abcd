'use strict';

(() => {
  const DEFAULTS = {
    cleanHomePage: true,
    collapseSidebar: false,
    hideSidebar: false,
    accessoryLimitEnabled: true,
    recentServers: {}
  };

  // Roblox AvatarAssetType IDs that contribute to the accessory limit.
  // 76 and 77 are layered eyebrow and eyelash accessories.
  const ACCESSORY_TYPE_IDS = new Set([
    8, 41, 42, 43, 44, 45, 46, 47,
    64, 65, 66, 67, 68, 69, 70, 71, 72, 76, 77
  ]);
  const NON_ACCESSORY_TYPE_IDS = new Set([
    2, 11, 12, 17, 18, 19, 27, 28, 29, 30, 31,
    48, 49, 50, 51, 52, 53, 54, 55, 61, 78, 79, 88, 89, 90, 92
  ]);
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
  let accessoryRefreshQueued = false;
  let accessoryRefreshTimer = null;
  let lastAccessoryRefresh = 0;
  let lastAccessoryActionAt = 0;
  let pendingAccessoryAdds = 0;
  let outfitCache = { userId: null, outfits: null, error: null, loading: false };
  let domFilterStats = { scans: 0, headingsFound: 0, removedSections: 0, mediaSourcesCleared: 0, unresolvedSections: 0, labels: [] };
  let settingsLoaded = false;
  let immediateDomScanQueued = false;

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

    for (let depth = 0; depth < 10; depth += 1) {
      node = node.parentElement;
      if (!node || node === document.body || node === document.documentElement || node.matches('main,#container-main')) break;

      const competingHeadings = Array.from(node.querySelectorAll(
        'h1,h2,h3,h4,[role="heading"],[data-testid*="title" i],[class*="section-title" i],[class*="heading" i],div,span'
      )).filter((candidate) => {
        if (candidate === heading || candidate.contains(heading) || heading.contains(candidate)) return false;
        const text = String(candidate.textContent || '').trim();
        return text.length <= 70 && isRecognizedFeedHeading(normalizeHeading(text));
      });
      const cards = node.querySelectorAll(cardLike).length;
      const semanticSection = node.matches(sectionLike);

      // Never remove a wrapper that also contains a different recognized feed section.
      if (competingHeadings.length) continue;
      if (semanticSection && (cards >= 1 || node.children.length >= 3)) return node;
      if (cards >= 2 && node.children.length >= 2) return node;
    }
    return null;
  }

  function clearSectionMedia(section) {
    let cleared = 0;
    const mediaSelector = 'img,source,video,audio,iframe,track,embed,object';
    const media = [];
    if (section.matches?.(mediaSelector)) media.push(section);
    media.push(...section.querySelectorAll(mediaSelector));

    for (const element of media) {
      if (element instanceof HTMLImageElement) {
        element.loading = 'lazy';
        for (const attr of ['srcset', 'sizes', 'src', 'data-src', 'data-srcset', 'data-lazy-src', 'data-original', 'data-original-src', 'data-background-image']) {
          if (element.hasAttribute(attr)) {
            element.removeAttribute(attr);
            cleared += 1;
          }
        }
      } else {
        for (const attr of ['src', 'srcset', 'poster', 'data-src', 'data-srcset', 'data-lazy-src', 'data-original', 'data-original-src', 'data-background-image']) {
          if (element.hasAttribute?.(attr)) {
            element.removeAttribute(attr);
            cleared += 1;
          }
        }
        if (element instanceof HTMLMediaElement) {
          try { element.pause(); element.load(); } catch { /* Detached media may reject load(). */ }
        }
      }
    }

    // Inline background images are also commonly used for Roblox thumbnails.
    const styled = [section, ...section.querySelectorAll('[style]')];
    for (const element of styled) {
      if (element.style?.backgroundImage && element.style.backgroundImage !== 'none') {
        element.style.backgroundImage = 'none';
        cleared += 1;
      }
    }

    return cleared;
  }

  function applyHomeFeedDomFilter() {
    if (!document.documentElement) return;
    if (!isHomePage()) {
      document.documentElement.dataset.rvLocalFeedDomRemoved = '0';
      document.documentElement.dataset.rvLocalFeedDomUnresolved = '0';
      document.documentElement.dataset.rvLocalFeedDomLabels = '';
      return;
    }
    if (!settingsLoaded || settings.cleanHomePage !== true) return;

    domFilterStats.scans += 1;
    const root = document.querySelector('#container-main') || document.querySelector('main') || document.body;
    if (!root) return;

    const headingSelector = 'h1,h2,h3,h4,[role="heading"],[data-testid*="title" i],[class*="section-title" i],[class*="heading" i]';
    const headings = new Set(root.querySelectorAll(headingSelector));
    // Some Roblox layouts use plain div/span nodes as titles.
    for (const element of root.querySelectorAll('div,span')) {
      if (element.childElementCount > 3) continue;
      const rawText = String(element.textContent || '').trim();
      if (rawText && rawText.length <= 70 && isRecognizedFeedHeading(normalizeHeading(rawText))) {
        headings.add(element);
      }
    }

    domFilterStats.headingsFound = headings.size;
    let removedNow = 0;
    let unresolvedNow = 0;
    let mediaClearedNow = 0;
    const labelsNow = [];
    const sectionsToRemove = new Map();

    for (const heading of headings) {
      if (!heading.isConnected) continue;
      const label = normalizeHeading(heading.textContent);
      if (!shouldHideFeedHeading(label)) continue;
      const section = findHomeSectionRoot(heading);
      if (!section) {
        unresolvedNow += 1;
        continue;
      }
      if (section.isConnected && !sectionsToRemove.has(section)) sectionsToRemove.set(section, label);
    }

    // Remove outermost section nodes first. Strip every media URL before detaching
    // so pending image/media loads can be cancelled instead of merely hidden.
    const candidates = [...sectionsToRemove.entries()].filter(([section]) =>
      ![...sectionsToRemove.keys()].some((other) => other !== section && other.contains(section))
    );

    for (const [section, label] of candidates) {
      if (!section.isConnected) continue;
      mediaClearedNow += clearSectionMedia(section);
      section.remove();
      removedNow += 1;
      labelsNow.push(label);
    }

    domFilterStats.removedSections += removedNow;
    domFilterStats.mediaSourcesCleared += mediaClearedNow;
    domFilterStats.unresolvedSections = unresolvedNow;
    domFilterStats.labels = [...new Set([...domFilterStats.labels, ...labelsNow])];

    document.documentElement.dataset.rvLocalFeedDomRemoved = String(domFilterStats.removedSections);
    document.documentElement.dataset.rvLocalFeedDomUnresolved = String(unresolvedNow);
    document.documentElement.dataset.rvLocalFeedMediaCleared = String(domFilterStats.mediaSourcesCleared);
    document.documentElement.dataset.rvLocalFeedDomLabels = domFilterStats.labels.join(',');
    document.documentElement.dataset.rvLocalFeedRestoreRequiresReload = 'true';
  }

  function nodeMayContainFeedHeading(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      return /standout|recommended for you|friends are playing|friends activity|friends playing/i.test(node.nodeValue || '');
    }
    if (!(node instanceof Element)) return false;
    const sample = (node.textContent || '').slice(0, 12000);
    return /standout games?|recommended for you|friends are playing|friends activity|friends playing/i.test(sample);
  }

  function queueImmediateDomPrune() {
    if (immediateDomScanQueued || !settingsLoaded || !settings.cleanHomePage || !isHomePage()) return;
    immediateDomScanQueued = true;
    queueMicrotask(() => {
      immediateDomScanQueued = false;
      applyHomeFeedDomFilter();
    });
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
    if (observer) return;
    observer = new MutationObserver((records) => {
      let possibleFeedInsert = false;
      let pageChanged = false;
      for (const record of records) {
        if (record.type === 'characterData' && nodeMayContainFeedHeading(record.target)) {
          possibleFeedInsert = true;
          pageChanged = true;
        }
        if (record.addedNodes?.length) {
          pageChanged = true;
          for (const node of record.addedNodes) {
            if (nodeMayContainFeedHeading(node)) possibleFeedInsert = true;
          }
        }
      }
      if (possibleFeedInsert) queueImmediateDomPrune();
      if (pageChanged) queuePageRefresh();
    });
    // Observe from the document root so the cleanup is active before Roblox
    // inserts its feed cards; document_idle would let thumbnails start loading.
    observer.observe(document, { childList: true, subtree: true, characterData: true });
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

  function classifyAccessoryTypeValue(value) {
    if (value === null || value === undefined || value === '') return null;
    const raw = String(value).trim();
    if (!raw) return null;

    if (/^\d+$/.test(raw)) {
      const id = Number(raw);
      if (ACCESSORY_TYPE_IDS.has(id)) return true;
      if (NON_ACCESSORY_TYPE_IDS.has(id)) return false;
      return null;
    }

    const normalized = raw
      .replace(/([a-z])([A-Z])/g, '$1 $2')
      .replace(/[_-]+/g, ' ')
      .replace(/\s+/g, ' ')
      .toLowerCase();

    // Check accessory names first so names such as "FaceAccessory" are not
    // mistaken for the non-accessory Face asset type.
    if (/\b(accessor(?:y|ies)|hat|hair|neck|shoulder|front|back|waist|eyebrow|eyelash|left shoe|right shoe|dress skirt|jacket accessory|sweater accessory|shorts accessory|t ?shirt accessory|shirt accessory|pants accessory)\b/.test(normalized)) {
      return true;
    }
    if (/\b(t ?shirt|shirt|pants|head|face|gear|torso|left arm|right arm|left leg|right leg|animation|emote|body part|body)\b/.test(normalized)) {
      return false;
    }
    return null;
  }

  function isAccessoryWearAction(target, action) {
    const typeAttributes = [
      'data-asset-type-id', 'data-assettypeid', 'data-asset-type', 'data-assettype',
      'data-item-type-id', 'data-itemtypeid', 'data-asset-type-name', 'data-item-type'
    ];

    // Roblox does not consistently expose an asset-type attribute on its Wear
    // buttons. Walk the item card and inspect its data attributes and labels.
    let node = action || (target instanceof Element ? target : target?.parentElement);
    for (let depth = 0; node && depth < 10; depth += 1, node = node.parentElement) {
      for (const attribute of typeAttributes) {
        const value = node.getAttribute?.(attribute);
        const classification = classifyAccessoryTypeValue(value);
        if (classification !== null) return classification;
      }

      const labels = [
        node.getAttribute?.('aria-label'),
        node.getAttribute?.('title'),
        node.getAttribute?.('data-testid'),
        node.getAttribute?.('data-testid-name'),
        node.getAttribute?.('alt'),
        typeof node.className === 'string' ? node.className : '',
        (node.textContent || '').slice(0, 140)
      ];
      for (const value of labels) {
        const classification = classifyAccessoryTypeValue(value);
        if (classification !== null) return classification;
      }
    }

    // Use the selected category as a fallback when Roblox gives the card no
    // type metadata at all.
    const selectedTabs = document.querySelectorAll(
      '[role="tab"][aria-selected="true"], [role="tab"][aria-current="page"], [aria-selected="true"], .tab-active'
    );
    for (const tab of selectedTabs) {
      if (!isVisibleElement(tab)) continue;
      const classification = classifyAccessoryTypeValue(
        `${tab.textContent || ''} ${tab.getAttribute('aria-label') || ''} ${tab.getAttribute('data-testid') || ''}`
      );
      if (classification !== null) return classification;
    }

    // Fail closed for an unidentified Wear action: new Roblox accessory types
    // must not bypass the cap simply because their metadata is missing.
    return true;
  }

  function findWearAction(target) {
    const element = target instanceof Element ? target : target?.parentElement;
    if (!(element instanceof Element)) return null;
    const action = element.closest(
      'button, [role="button"], a, input[type="button"], [data-testid*="wear" i], [data-action*="wear" i], [class*="wear" i], [data-testid*="equip" i], [data-action*="equip" i], [class*="equip" i]'
    );
    if (!action) return null;

    const label = [
      action.textContent,
      action.getAttribute('aria-label'),
      action.getAttribute('title'),
      action.getAttribute('data-testid'),
      action.getAttribute('data-action'),
      typeof action.className === 'string' ? action.className : ''
    ].filter(Boolean).join(' ').replace(/\s+/g, ' ').toLowerCase();
    return /\bwear\b|add to avatar|\bequip\b|put on/.test(label) ? action : null;
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

  function stopAvatarEquip(event, message) {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    showNotice(message);
  }

  function scheduleAccessoryCountRefresh() {
    clearTimeout(accessoryRefreshTimer);
    accessoryRefreshTimer = setTimeout(() => refreshAccessoryCount(true), 1200);
  }

  document.addEventListener('click', (event) => {
    if (!settings.accessoryLimitEnabled || !location.pathname.startsWith('/my/avatar')) return;

    const action = findWearAction(event.target);
    if (!action || !isAccessoryWearAction(event.target, action)) return;

    // Do not allow the initial API request to be bypassed by clicking before
    // the current avatar has been counted.
    if (accessoryCount === null) {
      stopAvatarEquip(event, 'Checking your accessory count. Try again in a moment.');
      refreshAccessoryCount(true);
      return;
    }

    const effectiveCount = accessoryCount + pendingAccessoryAdds;
    if (effectiveCount >= 10) {
      stopAvatarEquip(event, 'Accessory limit reached (10). Remove an accessory before adding another.');
      return;
    }

    // Reserve the slot immediately. This prevents several quick clicks from
    // all passing against the same stale API count. The next API read reconciles
    // the reservation, including same-category swaps that do not raise the
    // final accessory count.
    pendingAccessoryAdds += 1;
    lastAccessoryActionAt = Date.now();
    updateAccessoryWidget(`${Math.min(10, accessoryCount + pendingAccessoryAdds)}/10 accessories equipped · updating`);
    scheduleAccessoryCountRefresh();
  }, true);

  async function refreshAccessoryCount(force = false) {
    if (!settings.accessoryLimitEnabled) return;
    if (accessoryRefreshInFlight) {
      if (force) accessoryRefreshQueued = true;
      return;
    }
    if (!force && Date.now() - lastAccessoryRefresh < 15000) return;

    accessoryRefreshInFlight = true;
    const requestStartedAt = Date.now();
    lastAccessoryRefresh = requestStartedAt;

    let response;
    try {
      response = await send({ type: 'GET_ACCESSORY_COUNT' });
    } catch (error) {
      response = { error: String(error) };
    }
    accessoryRefreshInFlight = false;

    // A read that began before the most recent equip click may contain stale
    // data. Never let it erase a slot reservation; request a newer snapshot.
    if (requestStartedAt < lastAccessoryActionAt) {
      accessoryRefreshQueued = true;
    } else if (response?.error) {
      if (accessoryCount === null) updateAccessoryWidget('Could not read accessory count. Refresh to retry.');
    } else {
      const count = Number(response?.count);
      if (Number.isFinite(count) && count >= 0) {
        accessoryCount = count;
        pendingAccessoryAdds = 0;
        updateAccessoryWidget(`${accessoryCount}/10 accessories equipped`);
      } else {
        accessoryCount = null;
        updateAccessoryWidget('Could not read accessory count. Refresh to retry.');
      }
    }

    if (accessoryRefreshQueued) {
      accessoryRefreshQueued = false;
      setTimeout(() => refreshAccessoryCount(true), 450);
    }
  }

  function updateAccessoryWidget(text) {
    const label = accessoryWidget?.querySelector('[data-rv-count]');
    if (label) label.textContent = text;
    if (document.documentElement) {
      document.documentElement.dataset.rvLocalAccessoryCount = accessoryCount === null ? 'unknown' : String(accessoryCount);
      document.documentElement.dataset.rvLocalAccessoryPending = String(pendingAccessoryAdds);
    }
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
    startObserver();
    settings = { ...DEFAULTS, ...(await chrome.storage.local.get(DEFAULTS)) };
    settingsLoaded = true;
    applyLayoutSettings();
    queuePageRefresh();
    queueImmediateDomPrune();

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
