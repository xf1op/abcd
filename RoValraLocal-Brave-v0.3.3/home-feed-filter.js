'use strict';

(() => {
  const GUARD = '__roValraLocalHomeFeedFilterInstalled__';
  if (window[GUARD]) return;
  window[GUARD] = true;

  const VERSION = '0.3.2';
  const DEFAULTS = Object.freeze({ cleanHomePage: true });
  const ENDPOINT_PATH = '/discovery-api/omni-recommendation';
  const KEEP_TOPIC_IDS = new Set([100000001, 100000003]);
  const EXCLUDED_TOPIC_IDS = new Set([600000000, 100000000, 100000008]);

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
    textResponsesRewritten: 0,
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

  function collectRetainedContentTypes(sorts) {
    const types = new Set();
    for (const sort of sorts) {
      if (!Array.isArray(sort?.recommendationList)) continue;
      for (const item of sort.recommendationList) {
        if (item && item.contentId !== undefined && item.contentId !== null) {
          types.add(String(item.contentType || 'Game'));
        }
      }
    }
    return types;
  }

  function pruneUnusedMetadata(payload, retainedGameIds, retainedContentTypes) {
    const metadata = payload?.contentMetadata;
    if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) return { games: 0, buckets: 0 };

    let games = 0;
    let buckets = 0;
    const gameMap = metadata.Game;
    if (gameMap && typeof gameMap === 'object' && !Array.isArray(gameMap)) {
      for (const id of Object.keys(gameMap)) {
        if (!retainedGameIds.has(String(id))) {
          delete gameMap[id];
          games += 1;
        }
      }
    }

    // Continue and Favorites are game-only feed topics. Keep only metadata
    // buckets actually referenced by the retained recommendation items.
    for (const key of Object.keys(metadata)) {
      if (!retainedContentTypes.has(key)) {
        delete metadata[key];
        buckets += 1;
      }
    }
    return { games, buckets };
  }

  function isExcludedLayoutNode(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
    for (const key of ['topicId', 'sortId', 'feedTopicId']) {
      const id = Number(value[key]);
      if (Number.isFinite(id) && EXCLUDED_TOPIC_IDS.has(id)) return true;
    }
    for (const key of ['topic', 'title', 'name', 'label', 'sortName', 'displayName']) {
      const label = String(value[key] || '').trim().toLowerCase();
      if (label === 'friends' || label === 'friends are playing' || label === 'friends activity' ||
          label === 'standout games' || label === 'recommended for you') return true;
    }
    return false;
  }

  function pruneExcludedLayoutNodes(value, stats) {
    if (!value || typeof value !== 'object') return value;
    if (Array.isArray(value)) {
      const kept = [];
      for (const item of value) {
        if (isExcludedLayoutNode(item)) {
          stats.removed += 1;
          continue;
        }
        const result = pruneExcludedLayoutNodes(item, stats);
        kept.push(result);
      }
      return kept;
    }
    for (const key of Object.keys(value)) {
      const child = value[key];
      if (isExcludedLayoutNode(child)) {
        delete value[key];
        stats.removed += 1;
      } else if (child && typeof child === 'object') {
        value[key] = pruneExcludedLayoutNodes(child, stats);
      }
    }
    return value;
  }

  function filterHomeFeed(payload, source) {
    if (!settingsReady || !settings.cleanHomePage) return payload;
    if (!payload || typeof payload !== 'object' || filteredPayloads.has(payload) ||
        payload.pageType !== 'Home' || !Array.isArray(payload.sorts)) return payload;

    const originalSortCount = payload.sorts.length;
    const keptSorts = payload.sorts.filter((sort) => shouldKeepSort(sort));
    payload.sorts = keptSorts;

    const retainedGameIds = collectRetainedGameIds(keptSorts);
    const retainedContentTypes = collectRetainedContentTypes(keptSorts);
    const metadataStats = pruneUnusedMetadata(payload, retainedGameIds, retainedContentTypes);

    // The retained topics contain game cards only. This string-ID metadata map
    // belongs to the discarded non-game recommendation sections.
    let removedStringIdMetadata = 0;
    if (retainedContentTypes.size === 1 && retainedContentTypes.has('Game') &&
        payload.contentMetadataByStringId && typeof payload.contentMetadataByStringId === 'object') {
      removedStringIdMetadata = Object.keys(payload.contentMetadataByStringId).length;
      delete payload.contentMetadataByStringId;
    }

    const layoutStats = { removed: 0 };
    for (const key of ['globalLayoutData', 'sdui']) {
      if (payload[key] && typeof payload[key] === 'object') {
        payload[key] = pruneExcludedLayoutNodes(payload[key], layoutStats);
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
      removedGameMetadata: metadataStats.games,
      removedMetadataBuckets: metadataStats.buckets,
      removedStringIdBuckets: removedStringIdMetadata,
      removedLayoutNodes: layoutStats.removed
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
      filterHomeFeed(payload, source);
      // filterHomeFeed mutates and returns the same object. Test the WeakSet
      // marker rather than object identity, otherwise the original JSON string
      // would be returned unchanged and Roblox would still render removed sorts.
      if (!filteredPayloads.has(payload)) return rawText;
      diagnostics.textResponsesRewritten += 1;
      return JSON.stringify(payload);
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
