'use strict';

(() => {
  const DEFAULTS = {
    hideStandout: true,
    hideRecommended: true,
    keepOnlyContinueAndFavorites: true
  };

  const KEYS = Object.keys(DEFAULTS);

  function publish(settings) {
    const safeSettings = {};
    for (const key of KEYS) safeSettings[key] = settings[key] === true;

    window.postMessage({
      __rvLocalFeedBridge: 'settings',
      settings: safeSettings
    }, location.origin);
  }

  chrome.storage.local.get(DEFAULTS)
    .then(publish)
    .catch(() => publish(DEFAULTS));

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'local' || !KEYS.some((key) => Object.hasOwn(changes, key))) return;
    chrome.storage.local.get(DEFAULTS).then(publish).catch(() => {});
  });
})();
