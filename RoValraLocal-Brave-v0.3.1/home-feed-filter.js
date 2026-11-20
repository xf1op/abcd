'use strict';

(() => {
  const GUARD = '__roValraLocalHomeFeedFilterInstalled__';
  if (window[GUARD]) return;
  window[GUARD] = true;

  const VERSION = '0.3.1';
  const DEFAULTS = Object.freeze({ cleanHomePage: true });
  const ENDPOINT_PATH = '/discovery-api/omni-recommendation';
  const KEEP_TOPIC_IDS = new Set([100000001, 100000003]);

  let settings = { ...DEFAULTS };
  let settingsReady = false;
  let resolveSettingsReady;
  const settingsReadyPromise = new Promise((resolve) => { resolveSettingsReady = resolve; });
  const filteredPayloads = new WeakSet();

  const diagnostics = {
    installed: true,
    version: VERSION,
    endpoint: `https://apis.roblox.com${ENDPOINT_PATH}`,
    settingsReady: false,
    hooks: {
      responseJson: false,
      responseText: false,
      xhrResponse: false,
      xhrResponseText: false,
      xhrInstanceResponse: false,
      xhrInstanceResponseText: false
    },
    matchingResponsesSeen: 0,
    filteredResponses: 0,
    lastFilter: null,
    lastError: null
  };
  window.__rvLocalFeedDiagnostics = diagnostics;
  window.__rvLocalFeedLastFilter = { status: 'installed', version: VERSION };

  function updateLastFilter(result) {
    diagnostics.lastFilter = result;
    window.__rvLocalFeedLastFilter = result;
  }

  function normalizeSettings(input) {
    return { cleanHomePage: input?.cleanHomePage === true };
  }

  function applySettings(input) {
    settings = normalizeSettings(input);
    diagnostics.settingsReady = true;
    if (!settingsReady) {
      settingsReady = true;
      resolveSettingsReady();
    }
  }

  window.addEventListener('message', (event) => {
    if (event.source !== window || event.origin !== location.origin) return;
    const message = event.data;
    if (message?.__rvLocalFeedBridge === 'settings') applySettings(message.settings);
  });

  // Use the stored preferences when available; defaults prevent an early request
  // from bypassing filtering if extension storage is momentarily unavailable.
  setTimeout(() => {
    if (!settingsReady) applySettings(DEFAULTS);
  }, 1200);

  function isTargetUrl(value) {
    if (typeof value !== 'string' || !value) return false;
    try {
      const url = new URL(value, location.href);
      return url.hostname === 'apis.roblox.com' && url.pathname === ENDPOINT_PATH;
    } catch {
      return false;
    }
  }

  function topicIdOf(sort) {
    const id = Number(sort?.topicId);
    return Number.isFinite(id) ? id : null;
  }

  function shouldKeepSort(sort) {
    const id = topicIdOf(sort);
    const name = String(sort?.topic || '').trim().toLowerCase();
    return KEEP_TOPIC_IDS.has(id) ||
      name === 'continue' || name === 'continue playing' ||
      name === 'favorites' || name === 'favourites';
  }

  function collectRetainedGameIds(sorts) {
    const ids = new Set();
    for (const sort of sorts) {
      if (!Array.isArray(sort?.recommendationList)) continue;
      for (const item of sort.recommendationList) {
        if (!item || (item.contentType && item.contentType !== 'Game')) continue;
        if (item.contentId !== undefined && item.contentId !== null) ids.add(String(item.contentId));
      }
    }
    return ids;
  }

  function pruneGameMetadata(payload, retainedGameIds) {
    const gameMap = payload?.contentMetadata?.Game;
    if (!gameMap || typeof gameMap !== 'object' || Array.isArray(gameMap)) return 0;

    let removed = 0;
    for (const id of Object.keys(gameMap)) {
      if (!retainedGameIds.has(String(id))) {
        delete gameMap[id];
        removed += 1;
      }
    }
    return removed;
  }

  function filterHomeFeed(payload, source) {
    if (!settingsReady || !settings.cleanHomePage) return payload;
    if (!payload || typeof payload !== 'object' || filteredPayloads.has(payload) ||
        payload.pageType !== 'Home' || !Array.isArray(payload.sorts)) return payload;

    const originalSortCount = payload.sorts.length;
    const keptSorts = payload.sorts.filter((sort) => shouldKeepSort(sort));
    payload.sorts = keptSorts;

    const retainedGameIds = collectRetainedGameIds(keptSorts);
    const removedGameMetadata = pruneGameMetadata(payload, retainedGameIds);

    if (settings.cleanHomePage && payload.contentMetadataByStringId &&
        typeof payload.contentMetadataByStringId === 'object') {
      for (const key of ['RecommendedFriend', 'CatalogAvatar']) {
        delete payload.contentMetadataByStringId[key];
      }
    }

    const result = {
      status: 'filtered',
      source,
      originalSections: originalSortCount,
      removedSections: Math.max(0, originalSortCount - keptSorts.length),
      retainedSections: keptSorts.length,
      retainedTopics: keptSorts.map((sort) => String(sort?.topic || sort?.topicId || 'unknown')),
      retainedGameIds: retainedGameIds.size,
      removedGameMetadata
    };
    filteredPayloads.add(payload);
    diagnostics.filteredResponses += 1;
    updateLastFilter(result);
    return payload;
  }

  function filterJsonText(rawText, source) {
    if (typeof rawText !== 'string' || !rawText) return rawText;
    try {
      const payload = JSON.parse(rawText);
      const filtered = filterHomeFeed(payload, source);
      return filtered === payload ? rawText : JSON.stringify(filtered);
    } catch (error) {
      diagnostics.lastError = `Could not filter ${source}: ${String(error)}`;
      return rawText;
    }
  }

  // Response methods cover Fetch consumers, whether they parse JSON or text.
  if (typeof Response !== 'undefined' && Response.prototype) {
    const nativeJson = Response.prototype.json;
    if (typeof nativeJson === 'function') {
      Response.prototype.json = function (...args) {
        if (!isTargetUrl(this.url)) return nativeJson.apply(this, args);
        diagnostics.matchingResponsesSeen += 1;
        const response = this;
        return settingsReadyPromise
          .then(() => nativeJson.apply(response, args))
          .then((payload) => filterHomeFeed(payload, 'Response.json'));
      };
      diagnostics.hooks.responseJson = true;
    }

    const nativeText = Response.prototype.text;
    if (typeof nativeText === 'function') {
      Response.prototype.text = function (...args) {
        if (!isTargetUrl(this.url)) return nativeText.apply(this, args);
        diagnostics.matchingResponsesSeen += 1;
        const response = this;
        return settingsReadyPromise
          .then(() => nativeText.apply(response, args))
          .then((rawText) => filterJsonText(rawText, 'Response.text'));
      };
      diagnostics.hooks.responseText = true;
    }
  }

  // XHR: patch both the prototype and each instance immediately after open().
  // Some site bundles install own accessors on individual XHR objects, which
  // bypass a prototype-only getter patch.
  if (typeof XMLHttpRequest !== 'undefined' && XMLHttpRequest.prototype) {
    const proto = XMLHttpRequest.prototype;
    const nativeOpen = proto.open;
    const nativeResponse = Object.getOwnPropertyDescriptor(proto, 'response');
    const nativeResponseText = Object.getOwnPropertyDescriptor(proto, 'responseText');
    const xhrUrls = new WeakMap();
    const xhrTextCache = new WeakMap();

    function xhrIsTarget(xhr) {
      let responseUrl = '';
      try { responseUrl = xhr.responseURL || ''; } catch { /* Ignore read errors. */ }
      return isTargetUrl(responseUrl) || isTargetUrl(xhrUrls.get(xhr));
    }

    function filterCachedXhrText(xhr, raw, source) {
      if (!settingsReady) return raw;
      const cached = xhrTextCache.get(xhr);
      if (cached && cached.raw === raw) return cached.filtered;
      const filtered = filterJsonText(raw, source);
      xhrTextCache.set(xhr, { raw, filtered });
      return filtered;
    }

    function transformXhrValue(xhr, property, raw) {
      if (!xhrIsTarget(xhr)) return raw;
      diagnostics.matchingResponsesSeen += 1;
      if (property === 'response' && raw && typeof raw === 'object' && xhr.responseType === 'json') {
        return filterHomeFeed(raw, 'XMLHttpRequest.response');
      }
      if (typeof raw === 'string' && (property === 'responseText' || xhr.responseType === '' || xhr.responseType === 'text')) {
        return filterCachedXhrText(xhr, raw, `XMLHttpRequest.${property}`);
      }
      return raw;
    }

    function makeGetter(descriptor, property) {
      return function () {
        const raw = descriptor.get.call(this);
        return transformXhrValue(this, property, raw);
      };
    }

    if (nativeResponse?.get && nativeResponse.configurable) {
      Object.defineProperty(proto, 'response', {
        configurable: true,
        enumerable: nativeResponse.enumerable,
        get: makeGetter(nativeResponse, 'response')
      });
      diagnostics.hooks.xhrResponse = true;
    }

    if (nativeResponseText?.get && nativeResponseText.configurable) {
      Object.defineProperty(proto, 'responseText', {
        configurable: true,
        enumerable: nativeResponseText.enumerable,
        get: makeGetter(nativeResponseText, 'responseText')
      });
      diagnostics.hooks.xhrResponseText = true;
    }

    proto.open = function (method, url, ...rest) {
      const result = nativeOpen.call(this, method, url, ...rest);
      try {
        xhrUrls.set(this, String(url));
        xhrTextCache.delete(this);
        if (isTargetUrl(String(url))) {
          if (nativeResponse?.get && !Object.prototype.hasOwnProperty.call(this, 'response')) {
            Object.defineProperty(this, 'response', {
              configurable: true,
              enumerable: nativeResponse.enumerable,
              get: makeGetter(nativeResponse, 'response')
            });
            diagnostics.hooks.xhrInstanceResponse = true;
          }
          if (nativeResponseText?.get && !Object.prototype.hasOwnProperty.call(this, 'responseText')) {
            Object.defineProperty(this, 'responseText', {
              configurable: true,
              enumerable: nativeResponseText.enumerable,
              get: makeGetter(nativeResponseText, 'responseText')
            });
            diagnostics.hooks.xhrInstanceResponseText = true;
          }
        }
      } catch (error) {
        diagnostics.lastError = `Could not install XHR instance getter: ${String(error)}`;
      }
      return result;
    };
  }
})();
