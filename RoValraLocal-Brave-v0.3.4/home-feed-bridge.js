'use strict';

(() => {
  const DEFAULTS = { cleanHomePage: true };

  function publish(settings) {
    window.postMessage({
      __rvLocalFeedBridge: 'settings',
      settings: { cleanHomePage: settings.cleanHomePage === true }
    }, location.origin);
  }

  chrome.storage.local.get(DEFAULTS).then(publish).catch(() => publish(DEFAULTS));
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'local' || !Object.hasOwn(changes, 'cleanHomePage')) return;
    chrome.storage.local.get(DEFAULTS).then(publish).catch(() => {});
  });
})();
