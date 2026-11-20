(() => {
  'use strict';

  if (window.__rvLocalAccessoryManagerLoaded) return;
  window.__rvLocalAccessoryManagerLoaded = true;

  const ACCESSORY_TYPE_IDS = new Set([
    8, 41, 42, 43, 44, 45, 46, 47,
    64, 65, 66, 67, 68, 69, 70, 71, 72, 76, 77
  ]);
  const NON_ACCESSORY_TYPE_IDS = new Set([
    2, 11, 12, 17, 18, 19, 27, 28, 29, 30, 31,
    48, 49, 50, 51, 52, 53, 54, 55, 61, 78, 79, 88, 89, 90, 92
  ]);
  const TYPE_ATTRIBUTES = [
    'data-asset-type-id', 'data-assettypeid', 'data-asset-type',
    'data-assettype', 'data-item-type-id', 'data-itemtypeid',
    'data-asset-type-name', 'data-item-type'
  ];
  const ID_ATTRIBUTES = [
    'data-asset-id', 'data-assetid', 'data-item-id', 'data-itemid',
    'data-thumbnail-target-id', 'thumbnail-target-id', 'data-id'
  ];

  const inFlight = new Set();
  let enabled = true;

  function classifyType(value) {
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

    if (/\b(accessor(?:y|ies)|hat|hair|neck|shoulder|front|back|waist|eyebrow|eyelash|left shoe|right shoe|dress skirt|jacket accessory|sweater accessory|shorts accessory|t ?shirt accessory|shirt accessory|pants accessory)\b/.test(normalized)) {
      return true;
    }
    if (/\b(t ?shirt|shirt|pants|head|face|gear|torso|left arm|right arm|left leg|right leg|animation|emote|body part|body)\b/.test(normalized)) {
      return false;
    }
    return null;
  }

  function isVisible(element) {
    if (!element || !element.isConnected) return false;
    const style = getComputedStyle(element);
    return style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      element.getClientRects().length > 0;
  }

  function findWearAction(target) {
    const element = target instanceof Element ? target : target?.parentElement;
    if (!(element instanceof Element)) return null;

    const action = element.closest(
      'button, [role="button"], a, input[type="button"], ' +
      '[data-testid*="wear" i], [data-action*="wear" i], [class*="wear" i], ' +
      '[data-testid*="equip" i], [data-action*="equip" i], [class*="equip" i]'
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

  function isAccessoryWearAction(target, action) {
    let node = action || (target instanceof Element ? target : target?.parentElement);

    for (let depth = 0; node && depth < 10; depth += 1, node = node.parentElement) {
      for (const attribute of TYPE_ATTRIBUTES) {
        const result = classifyType(node.getAttribute?.(attribute));
        if (result !== null) return result;
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

      for (const label of labels) {
        const result = classifyType(label);
        if (result !== null) return result;
      }
    }

    const tabs = document.querySelectorAll(
      '[role="tab"][aria-selected="true"], [role="tab"][aria-current="page"], ' +
      '[aria-selected="true"], .tab-active'
    );

    for (const tab of tabs) {
      if (!isVisible(tab)) continue;
      const result = classifyType(
        `${tab.textContent || ''} ${tab.getAttribute('aria-label') || ''} ${tab.getAttribute('data-testid') || ''}`
      );
      if (result !== null) return result;
    }

    // Match the previous limiter's fail-closed behaviour for unknown Wear cards.
    return true;
  }

  function parseNumericId(value) {
    if (value === null || value === undefined) return null;
    const raw = String(value).trim();
    if (!/^\d{1,16}$/.test(raw)) return null;
    const id = Number(raw);
    return Number.isSafeInteger(id) && id > 0 ? id : null;
  }

  function parseIdFromValue(value) {
    if (!value) return null;
    const raw = String(value);

    const pathMatch = raw.match(/\/(?:catalog|asset|library)\/(\d{1,16})(?:[/?#]|$)/i);
    if (pathMatch) return parseNumericId(pathMatch[1]);

    const labelledMatch = raw.match(/(?:asset|item|thumbnail|target)[\s_:#=/.-]*(\d{2,16})/i);
    if (labelledMatch) return parseNumericId(labelledMatch[1]);

    return null;
  }

  function getAssetId(action) {
    let node = action;

    for (let depth = 0; node && depth < 12; depth += 1, node = node.parentElement) {
      for (const attribute of ID_ATTRIBUTES) {
        const value = node.getAttribute?.(attribute);
        const id = parseNumericId(value) || parseIdFromValue(value);
        if (id) return id;
      }

      const href = node.getAttribute?.('href');
      const hrefId = parseIdFromValue(href);
      if (hrefId) return hrefId;

      const ownId = parseIdFromValue(node.id);
      if (ownId) return ownId;

      const testId = parseIdFromValue(
        node.getAttribute?.('data-testid') || node.getAttribute?.('data-testid-name')
      );
      if (testId) return testId;

      const attributes = node.attributes ? Array.from(node.attributes) : [];
      for (const attribute of attributes) {
        if (!/asset|item|thumbnail|target|catalog|(^|-)id$/i.test(attribute.name)) continue;
        const id = parseNumericId(attribute.value) || parseIdFromValue(attribute.value);
        if (id) return id;
      }

      // Look inside the current card for Roblox's thumbnail target or catalog link.
      const descendant = node.querySelector?.(
        'a[href*="/catalog/"], a[href*="/asset/"], a[href*="/library/"], ' +
        '[data-thumbnail-target-id], [thumbnail-target-id], [data-asset-id], [data-item-id]'
      );
      if (descendant) {
        for (const attribute of ID_ATTRIBUTES) {
          const value = descendant.getAttribute?.(attribute);
          const id = parseNumericId(value) || parseIdFromValue(value);
          if (id) return id;
        }
        const descendantId = parseIdFromValue(descendant.getAttribute?.('href'));
        if (descendantId) return descendantId;
      }

      if (node.matches?.('.item-card, [data-testid*="item-card" i], [data-testid*="asset-card" i]')) {
        break;
      }
    }

    return null;
  }

  function setInvisibleDiagnostic(key, value) {
    if (document.documentElement) {
      document.documentElement.dataset[key] = String(value).slice(0, 180);
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

  document.addEventListener('click', (event) => {
    if (!enabled || !location.pathname.startsWith('/my/avatar')) return;

    const action = findWearAction(event.target);
    if (!action || !isAccessoryWearAction(event.target, action)) return;

    // Own accessory Wear clicks before Roblox's handler and the old counter
    // listener. No page toast, bottom prompt, or native one-item equip call.
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();

    const assetId = getAssetId(action);
    if (!assetId) {
      setInvisibleDiagnostic('rvLocalAccessoryError', 'Could not identify the clicked accessory card ID.');
      return;
    }

    if (inFlight.has(assetId)) return;
    inFlight.add(assetId);

    chrome.runtime.sendMessage(
      { type: 'EQUIP_ACCESSORY', assetId },
      (response) => {
        inFlight.delete(assetId);

        if (chrome.runtime.lastError || !response || response.error) {
          setInvisibleDiagnostic(
            'rvLocalAccessoryError',
            chrome.runtime.lastError?.message || response?.error || 'Accessory update failed.'
          );
          return;
        }

        delete document.documentElement.dataset.rvLocalAccessoryError;
        updateCounter(Number(response.count));
      }
    );
  }, true);

  chrome.storage.local.get({ accessoryLimitEnabled: true }, (settings) => {
    enabled = settings.accessoryLimitEnabled !== false;
  });

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === 'local' && changes.accessoryLimitEnabled) {
      enabled = changes.accessoryLimitEnabled.newValue !== false;
    }
  });
})();
