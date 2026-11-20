(() => {
  'use strict';

  if (window.__rvLocalAccessoryBridgeLoaded) return;
  window.__rvLocalAccessoryBridgeLoaded = true;

  const MESSAGE_SOURCE = 'rv-local-accessory-main';
  const inFlight = new Set();

  function setError(message) {
    if (document.documentElement) {
      document.documentElement.dataset.rvLocalAccessoryError = String(message).slice(0, 180);
    }
  }

  function updateCounter(count) {
    if (!Number.isFinite(count)) return;

    const label = document.querySelector('#rv-local-accessory-widget [data-rv-count]');
    if (label) label.textContent = `${count}/10 accessories equipped`;

    if (document.documentElement) {
      document.documentElement.dataset.rvLocalAccessoryCount = String(count);
      document.documentElement.dataset.rvLocalAccessoryPending = '0';
    }
  }

  window.addEventListener('message', (event) => {
    if (event.source !== window || event.origin !== location.origin) return;

    const message = event.data;
    if (!message || message.source !== MESSAGE_SOURCE || message.type !== 'EQUIP_ACCESSORY') return;

    const assetId = Number(message.assetId);
    if (!Number.isSafeInteger(assetId) || assetId <= 0 || inFlight.has(assetId)) return;

    inFlight.add(assetId);

    chrome.runtime.sendMessage(
      { type: 'EQUIP_ACCESSORY', assetId },
      (response) => {
        inFlight.delete(assetId);

        if (chrome.runtime.lastError || !response || response.error) {
          setError(chrome.runtime.lastError?.message || response?.error || 'Accessory update failed.');
          return;
        }

        delete document.documentElement.dataset.rvLocalAccessoryError;
        updateCounter(Number(response.count));
      }
    );
  });
})();
