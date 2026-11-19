'use strict';

(() => {
  const GUARD = '__roValraLocalHomeFeedFilterInstalled__';
  if (window[GUARD]) return;
  window[GUARD] = true;

  const DEFAULTS = Object.freeze({
    hideStandout: true,
    hideRecommended: true,
    keepOnlyContinueAndFavorites: true
  });

  const ENDPOINT_PATH = '/discovery-api/omni-recommendation';
  const KEEP_TOPIC_IDS = new Set([100000001, 100000003]);
  const STANDOUT_TOPIC_IDS = new Set([100000008]);
  const RECOMMENDED_TOPIC_IDS = new Set([100000000]);

  let settings = { ...DEFAULTS };
  let settingsReady = false;
  let resolveSettingsReady;
  const settingsReadyPromise = new Promise((resolve) => {
    resolveSettingsReady = resolve;
  });

  // Visible immediately in the Roblox page's DevTools console, even before
  // the first omni-recommendation response arrives.
  const diagnostics = {
    installed: true,
    version: '0.2.1',
    endpoint: `https://apis.roblox.com${ENDPOINT_PATH}`,
    settingsReady: false,
    hooks: {
      responseJson: false,
      responseText: false,
      xhrResponse: false,
      xhrResponseText: false
    },
    matchingResponsesSeen: 0,
    filteredResponses: 0,
    lastFilter: null,
    lastError: null
  };
  window.__rvLocalFeedDiagnostics = diagnostics;
  window.__rvLocalFeedLastFilter = { status: 'installed', version: diagnostics.version };

  function updateLastFilter(result) {
    diagnostics.lastFilter = result;
    window.__rvLocalFeedLastFilter = result;
  }

  function normalizeSettings(input) {
    return {
      hideStandout: input?.hideStandout === true,
      hideRecommended: input?.hideRecommended === true,
      keepOnlyContinueAndFavorites: input?.keepOnlyContinueAndFavorites === true
    };
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
    if (!message || message.__rvLocalFeedBridge !== 'settings') return;
    applySettings(message.settings);
  });

  // Fail open to configured defaults if extension storage is unavailable.
  setTimeout(() => {
    if (!settingsReady) applySettings(DEFAULTS);
  }, 1200);

  function isTargetUrl(urlValue) {
    if (typeof urlValue !== 'string' || !urlValue) return false;
    try {
      const url = new URL(urlValue, location.href);
      return url.hostname === 'apis.roblox.com' && url.pathname === ENDPOINT_PATH;
    } catch {
      return false;
    }
  }

  function isTargetResponse(response) {
    return !!response && isTargetUrl(response.url);
  }

  function topicIdOf(sort) {
    const id = Number(sort?.topicId);
    return Number.isFinite(id) ? id : null;
  }

  function topicNameOf(sort) {
    return String(sort?.topic || '').trim().toLowerCase();
  }

  function shouldKeepSort(sort, currentSettings) {
    const id = topicIdOf(sort);
    const name = topicNameOf(sort);

    if (currentSettings.keepOnlyContinueAndFavorites) {
      return KEEP_TOPIC_IDS.has(id) ||
        name === 'continue' || name === 'favorites' || name === 'favourites';
    }

    if (currentSettings.hideStandout && (STANDOUT_TOPIC_IDS.has(id) || name.includes('standout'))) {
      return false;
    }
    if (currentSettings.hideRecommended && (
      RECOMMENDED_TOPIC_IDS.has(id) ||
      name.includes('recommended') ||
      name.includes('sponsored') ||
      name.includes('discover')
    )) {
      return false;
    }
    return true;
  }

  function collectRetainedGameIds(sorts) {
    const ids = new Set();
    for (const sort of sorts) {
      if (!Array.isArray(sort?.recommendationList)) continue;
      for (const item of sort.recommendationList) {
        if (!item || (item.contentType && item.contentType !== 'Game')) continue;
        if (item.contentId !== undefined && item.contentId !== null) {
          ids.add(String(item.contentId));
        }
      }
    }
    return ids;
  }

  function pruneGameMetadata(payload, retainedGameIds) {
    const metadata = payload?.contentMetadata;
    if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) return 0;

    // Roblox currently groups game metadata under contentMetadata.Game.
    // Only prune that known bucket; preserve unknown buckets for compatibility.
    const gameMap = metadata.Game;
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

  function filterHomeFeed(payload, currentSettings, source) {
    if (!payload || payload.pageType !== 'Home' || !Array.isArray(payload.sorts)) {
      return payload;
    }

    const originalSortCount = payload.sorts.length;
    const keptSorts = payload.sorts.filter((sort) => shouldKeepSort(sort, currentSettings));
    payload.sorts = keptSorts;

    const retainedGameIds = collectRetainedGameIds(keptSorts);
    const removedGameMetadata = pruneGameMetadata(payload, retainedGameIds);

    // Remove the named non-game metadata buckets from the response's string-ID
    // map when only Continue/Favorites are retained.
    if (currentSettings.keepOnlyContinueAndFavorites &&
        payload.contentMetadataByStringId &&
        typeof payload.contentMetadataByStringId === 'object') {
      for (const key of ['RecommendedFriend', 'CatalogAvatar']) {
        if (Object.prototype.hasOwnProperty.call(payload.contentMetadataByStringId, key)) {
          delete payload.contentMetadataByStringId[key];
        }
      }
    }

    const result = {
      status: 'filtered',
      source,
      removedSections: Math.max(0, originalSortCount - keptSorts.length),
      retainedSections: keptSorts.length,
      retainedTopics: keptSorts.map((sort) => String(sort?.topic || sort?.topicId || 'unknown')),
      retainedGameIds: retainedGameIds.size,
      removedGameMetadata
    };
    diagnostics.filteredResponses += 1;
    updateLastFilter(result);
    return payload;
  }

  function filterJsonText(rawText, currentSettings, source) {
    if (typeof rawText !== 'string' || !rawText) return rawText;
    try {
      const payload = JSON.parse(rawText);
      const filtered = filterHomeFeed(payload, currentSettings, source);
      return filtered === payload ? rawText : JSON.stringify(filtered);
    } catch (error) {
      diagnostics.lastError = `Could not filter ${source}: ${String(error)}`;
      return rawText;
    }
  }

  // Fetch-based path used by modern page code, including cloned Responses.
  if (typeof Response !== 'undefined' && Response.prototype) {
    const originalJson = Response.prototype.json;
    if (typeof originalJson === 'function') {
      Response.prototype.json = function (...args) {
        if (!isTargetResponse(this)) return originalJson.apply(this, args);
        diagnostics.matchingResponsesSeen += 1;
        const response = this;
        return settingsReadyPromise
          .then(() => originalJson.apply(response, args))
          .then((payload) => filterHomeFeed(payload, settings, 'Response.json'));
      };
      diagnostics.hooks.responseJson = true;
    }

    const originalText = Response.prototype.text;
    if (typeof originalText === 'function') {
      Response.prototype.text = function (...args) {
        if (!isTargetResponse(this)) return originalText.apply(this, args);
        diagnostics.matchingResponsesSeen += 1;
        const response = this;
        return settingsReadyPromise
          .then(() => originalText.apply(response, args))
          .then((text) => filterJsonText(text, settings, 'Response.text'));
      };
      diagnostics.hooks.responseText = true;
    }
  }

  // XHR-based path: some Roblox bundles parse responseText instead of calling
  // Response.json(). The native getters are preserved for every other URL/type.
  if (typeof XMLHttpRequest !== 'undefined' && XMLHttpRequest.prototype) {
    const xhrProto = XMLHttpRequest.prototype;
    const originalOpen = xhrProto.open;
    const xhrUrls = new WeakMap();

    xhrProto.open = function (method, url, ...rest) {
      try { xhrUrls.set(this, String(url)); } catch { /* WeakMap is best-effort. */ }
      return originalOpen.call(this, method, url, ...rest);
    };

    function xhrIsTarget(xhr) {
      let responseUrl = '';
      try { responseUrl = xhr.responseURL || ''; } catch { /* Ignore getter failures. */ }
      return isTargetUrl(responseUrl) || isTargetUrl(xhrUrls.get(xhr));
    }

    const responseDescriptor = Object.getOwnPropertyDescriptor(xhrProto, 'response');
    if (responseDescriptor?.get && responseDescriptor.configurable) {
      Object.defineProperty(xhrProto, 'response', {
        configurable: responseDescriptor.configurable,
        enumerable: responseDescriptor.enumerable,
        get: function () {
          const raw = responseDescriptor.get.call(this);
          if (!xhrIsTarget(this)) return raw;
          diagnostics.matchingResponsesSeen += 1;
          if (this.responseType === 'json' && raw && typeof raw === 'object') {
            return filterHomeFeed(raw, settings, 'XMLHttpRequest.response');
          }
          if (typeof raw === 'string' && (this.responseType === '' || this.responseType === 'text')) {
            return filterJsonText(raw, settings, 'XMLHttpRequest.response');
          }
          return raw;
        }
      });
      diagnostics.hooks.xhrResponse = true;
    }

    const responseTextDescriptor = Object.getOwnPropertyDescriptor(xhrProto, 'responseText');
    if (responseTextDescriptor?.get && responseTextDescriptor.configurable) {
      Object.defineProperty(xhrProto, 'responseText', {
        configurable: responseTextDescriptor.configurable,
        enumerable: responseTextDescriptor.enumerable,
        get: function () {
          const raw = responseTextDescriptor.get.call(this);
          if (!xhrIsTarget(this)) return raw;
          diagnostics.matchingResponsesSeen += 1;
          return filterJsonText(raw, settings, 'XMLHttpRequest.responseText');
        }
      });
      diagnostics.hooks.xhrResponseText = true;
    }
  }
})();
