(() => {
  'use strict';

  if (window.__rvLocalAccessoryMainLoaded) return;
  window.__rvLocalAccessoryMainLoaded = true;

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
    'data-thumbnail-target-id', 'thumbnail-target-id', 'data-catalog-item-id'
  ];
  const MESSAGE_SOURCE = 'rv-local-accessory-main';

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

  function findWearAction(event) {
    const path = typeof event.composedPath === 'function' ? event.composedPath() : [event.target];
    for (const node of path) {
      if (!(node instanceof Element)) continue;
      if (!node.matches('button, [role="button"], a, input[type="button"]')) continue;

      const label = [
        node.textContent,
        node.getAttribute('aria-label'),
        node.getAttribute('title'),
        node.getAttribute('data-testid'),
        node.getAttribute('data-testid-name'),
        node.getAttribute('data-action'),
        typeof node.className === 'string' ? node.className : ''
      ].filter(Boolean).join(' ').replace(/\s+/g, ' ').toLowerCase();

      if (/\bwear\b|add to avatar|\bequip\b|put on/.test(label)) return node;
    }
    return null;
  }

  function isAccessoryWearAction(action) {
    let node = action;

    for (let depth = 0; node && depth < 9; depth += 1, node = node.parentElement) {
      for (const attribute of TYPE_ATTRIBUTES) {
        const classification = classifyType(node.getAttribute?.(attribute));
        if (classification !== null) return classification;
      }

      const labels = [
        node.getAttribute?.('aria-label'),
        node.getAttribute?.('title'),
        node.getAttribute?.('data-testid'),
        node.getAttribute?.('data-testid-name'),
        node.getAttribute?.('alt'),
        typeof node.className === 'string' ? node.className : ''
      ];

      for (const label of labels) {
        const classification = classifyType(label);
        if (classification !== null) return classification;
      }
    }

    const selectedTabs = document.querySelectorAll(
      '[role="tab"][aria-selected="true"], [role="tab"][aria-current="page"], ' +
      '[aria-selected="true"], .tab-active'
    );

    for (const tab of selectedTabs) {
      const style = getComputedStyle(tab);
      if (style.display === 'none' || style.visibility === 'hidden' || !tab.getClientRects().length) continue;
      const classification = classifyType(
        `${tab.textContent || ''} ${tab.getAttribute('aria-label') || ''} ${tab.getAttribute('data-testid') || ''}`
      );
      if (classification !== null) return classification;
    }

    // Unknown Wear actions are intercepted conservatively on the Avatar editor.
    return true;
  }

  function parseAssetIdFromHref(value) {
    if (!value) return null;
    const match = String(value).match(/\/(?:catalog|asset|library)\/(\d{1,16})(?:[/?#]|$)/i);
    if (!match) return null;
    const id = Number(match[1]);
    return Number.isSafeInteger(id) && id > 0 ? id : null;
  }

  function parseNumericAttribute(value) {
    if (!value || !/^\d{1,16}$/.test(String(value).trim())) return null;
    const id = Number(value);
    return Number.isSafeInteger(id) && id > 0 ? id : null;
  }

  function getAssetId(action) {
    // Prefer a real Roblox catalog/asset URL: generic data-id values on
    // React wrappers can refer to unrelated UI records.
    const directLink = action.matches('a[href]') ? action : null;
    const directHrefId = parseAssetIdFromHref(directLink?.getAttribute('href'));
    if (directHrefId) return directHrefId;

    let node = action;
    for (let depth = 0; node && depth < 10; depth += 1, node = node.parentElement) {
      const links = [];
      if (node.matches?.('a[href]')) links.push(node);
      if (node.querySelectorAll) {
        links.push(...node.querySelectorAll(
          'a[href*="/catalog/"], a[href*="/asset/"], a[href*="/library/"]'
        ));
      }

      for (const link of links) {
        const id = parseAssetIdFromHref(link.getAttribute('href'));
        if (id) return id;
      }

      for (const attribute of ID_ATTRIBUTES) {
        const id = parseNumericAttribute(node.getAttribute?.(attribute));
        if (id) return id;
      }

      // Stop once the item card has been inspected; do not scan page ancestors.
      if (node.matches?.(
        '.item-card, [data-testid*="item-card" i], [data-testid*="asset-card" i], ' +
        '[data-testid*="catalog-item" i], [class*="item-card" i]'
      )) {
        break;
      }
    }

    return null;
  }

  function recordError(message) {
    if (document.documentElement) {
      document.documentElement.dataset.rvLocalAccessoryError = String(message).slice(0, 180);
    }
  }

  function onClick(event) {
    if (!location.pathname.startsWith('/my/avatar')) return;

    const action = findWearAction(event);
    if (!action || !isAccessoryWearAction(action)) return;

    // Capture in MAIN world at window level, before Roblox's React handlers
    // and the extension's legacy isolated-world click listener.
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();

    const assetId = getAssetId(action);
    if (!assetId) {
      recordError('Accessory click intercepted, but the card asset ID could not be identified.');
      return;
    }

    delete document.documentElement.dataset.rvLocalAccessoryError;
    window.postMessage({
      source: MESSAGE_SOURCE,
      type: 'EQUIP_ACCESSORY',
      assetId
    }, location.origin);
  }

  window.addEventListener('click', onClick, true);
})();
