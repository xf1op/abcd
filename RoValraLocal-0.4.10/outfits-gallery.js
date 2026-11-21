'use strict';

(() => {
  const STORAGE_DEFAULTS = { profileOutfitsEnabled: true };
  const PAGE_SIZE = 100;
  const BUTTON_ID = 'rvlocal-profile-outfits-button';
  const MODAL_ID = 'rvlocal-profile-outfits-modal';
  const STYLE_ID = 'rvlocal-profile-outfits-style';
  const ROUTE_EVENT = 'rvlocal:route-change';
  const CSS = `
#${MODAL_ID} {
  position: fixed;
  inset: 0;
  z-index: 2147483000;
  display: none;
  align-items: center;
  justify-content: center;
  padding: 24px;
  background: rgba(5, 7, 11, .76);
  color: #edf1f6;
  font: 14px/1.4 system-ui, -apple-system, "Segoe UI", sans-serif;
}
#${MODAL_ID}[data-open="true"] { display: flex; }
#${MODAL_ID} * { box-sizing: border-box; }
#${MODAL_ID} .rvlocal-outfits-dialog {
  display: flex;
  flex-direction: column;
  width: min(1180px, calc(100vw - 32px));
  max-height: min(880px, calc(100vh - 48px));
  min-height: 300px;
  overflow: hidden;
  border: 1px solid rgba(145,155,170,.25);
  border-radius: 14px;
  background: #171a20;
  box-shadow: 0 24px 80px rgba(0,0,0,.5);
}
#${MODAL_ID} .rvlocal-outfits-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 16px 20px;
  border-bottom: 1px solid #303640;
}
#${MODAL_ID} .rvlocal-outfits-heading { min-width: 0; }
#${MODAL_ID} .rvlocal-outfits-title { margin: 0; color: #f4f6f8; font-size: 19px; font-weight: 700; }
#${MODAL_ID} .rvlocal-outfits-subtitle { margin: 3px 0 0; color: #9da7b5; font-size: 12px; }
#${MODAL_ID} .rvlocal-outfits-close {
  display: inline-flex; align-items: center; justify-content: center;
  width: 34px; height: 34px; flex: 0 0 auto;
  border: 1px solid #3a424e; border-radius: 8px;
  background: #222730; color: #e8edf4; font-size: 22px; line-height: 1; cursor: pointer;
}
#${MODAL_ID} .rvlocal-outfits-status { padding: 10px 20px 0; color: #aab4c1; font-size: 12px; }
#${MODAL_ID} .rvlocal-outfits-grid-wrap { min-height: 0; overflow: auto; padding: 14px 18px 18px; }
#${MODAL_ID} .rvlocal-outfits-grid {
  display: grid;
  grid-template-columns: repeat(8, minmax(0, 1fr));
  gap: 14px 12px;
}
#${MODAL_ID} .rvlocal-outfit-card {
  display: flex; flex-direction: column; align-items: stretch; min-width: 0;
  padding: 7px; border: 1px solid transparent; border-radius: 10px;
  background: #20252d; color: #f0f3f6; text-align: left; cursor: pointer;
}
#${MODAL_ID} .rvlocal-outfit-card:hover { background: #292f39; border-color: #465160; }
#${MODAL_ID} .rvlocal-outfit-card[aria-pressed="true"] { border-color: #75aaff; background: #273348; }
#${MODAL_ID} .rvlocal-outfit-image-wrap {
  display: flex; align-items: center; justify-content: center; width: 100%; aspect-ratio: 1;
  overflow: hidden; border-radius: 7px; background: #11151b;
}
#${MODAL_ID} .rvlocal-outfit-image { display: block; width: 100%; height: 100%; object-fit: contain; }
#${MODAL_ID} .rvlocal-outfit-placeholder { color: #788596; font-size: 11px; text-align: center; padding: 6px; }
#${MODAL_ID} .rvlocal-outfit-name {
  display: -webkit-box; min-height: 34px; margin: 8px 2px 1px; overflow: hidden;
  color: #edf1f6; font-size: 12px; font-weight: 600; line-height: 1.35;
  -webkit-box-orient: vertical; -webkit-line-clamp: 2;
}
#${MODAL_ID} .rvlocal-outfit-card-id { display: none; margin: 2px 2px 0; color: #9bbdf0; font-size: 10px; }
#${MODAL_ID} .rvlocal-outfit-card[aria-pressed="true"] .rvlocal-outfit-card-id { display: block; }
#${MODAL_ID} .rvlocal-outfits-selection {
  display: flex; align-items: center; justify-content: space-between; gap: 12px;
  padding: 12px 20px; border-top: 1px solid #303640; background: #1c2027;
}
#${MODAL_ID} .rvlocal-outfits-selected-text { min-width: 0; color: #cbd3dd; font-size: 12px; overflow-wrap: anywhere; }
#${MODAL_ID} .rvlocal-outfits-actions { display: flex; flex: 0 0 auto; align-items: center; gap: 8px; }
#${MODAL_ID} .rvlocal-outfits-action {
  min-height: 32px; padding: 0 12px; border: 1px solid #3d4857; border-radius: 7px;
  background: #252d39; color: #edf3fb; font-size: 12px; font-weight: 600; cursor: pointer;
}
#${MODAL_ID} .rvlocal-outfits-action:disabled { opacity: .45; cursor: default; }
#${MODAL_ID} .rvlocal-outfits-load-wrap { display: flex; justify-content: center; padding: 0 18px 16px; }
#${MODAL_ID} .rvlocal-outfits-empty { grid-column: 1 / -1; padding: 40px 16px; color: #aeb8c5; text-align: center; }
@media (max-width: 1150px) { #${MODAL_ID} .rvlocal-outfits-grid { grid-template-columns: repeat(7, minmax(0,1fr)); } }
@media (max-width: 1000px) { #${MODAL_ID} .rvlocal-outfits-grid { grid-template-columns: repeat(6, minmax(0,1fr)); } }
@media (max-width: 820px) { #${MODAL_ID} .rvlocal-outfits-grid { grid-template-columns: repeat(5, minmax(0,1fr)); } }
@media (max-width: 650px) {
  #${MODAL_ID} { padding: 10px; }
  #${MODAL_ID} .rvlocal-outfits-dialog { width: calc(100vw - 20px); max-height: calc(100vh - 20px); }
  #${MODAL_ID} .rvlocal-outfits-grid { grid-template-columns: repeat(4, minmax(0,1fr)); gap: 9px; }
  #${MODAL_ID} .rvlocal-outfits-grid-wrap { padding: 10px; }
  #${MODAL_ID} .rvlocal-outfits-header { padding: 12px; }
}
@media (max-width: 440px) { #${MODAL_ID} .rvlocal-outfits-grid { grid-template-columns: repeat(2, minmax(0,1fr)); } }
`;

  let enabled = true;
  let currentUserId = null;
  let trigger = null;
  let discoveryObserver = null;
  let modal = null;
  let page = 1;
  let hasMore = false;
  let loading = false;
  let loadedUserId = null;
  let outfits = [];
  let thumbnails = new Map();
  let selectedOutfit = null;
  let bodyOverflowBefore = '';
  let routeKey = '';

  function profileUserId() {
    const match = location.pathname.match(/^\/users\/(\d+)\/profile\/?$/);
    return match ? match[1] : null;
  }

  function installStyles() {
    if (!document.documentElement || document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = CSS;
    (document.head || document.documentElement).appendChild(style);
  }

  function normalized(value) {
    return String(value || '').replace(/\s+/g, ' ').trim().toLowerCase();
  }

  function is3DControl(element) {
    if (!(element instanceof Element)) return false;
    const labels = [
      element.getAttribute('aria-label'),
      element.getAttribute('title'),
      element.getAttribute('data-testid'),
      element.getAttribute('data-test'),
      typeof element.className === 'string' ? element.className : element.className?.baseVal,
      element.querySelector('svg,[data-testid],[aria-label],[title]')?.getAttribute('data-testid'),
      element.querySelector('svg,[data-testid],[aria-label],[title]')?.getAttribute('aria-label'),
      element.querySelector('svg,[data-testid],[aria-label],[title]')?.getAttribute('title'),
      element.textContent
    ].map(normalized).filter(Boolean);
    return labels.some((label) =>
      /^(3d|3d view|view 3d|view in 3d|switch to 3d|show 3d)$/.test(label) ||
      /(?:^|[-_ ])(?:3d)(?:[-_ ]|$)/.test(label)
    );
  }

  function find3DControl() {
    const main = document.querySelector('#container-main') || document.querySelector('main') || document.body;
    if (!main) return null;
    const selectors = [
      'button[aria-label]', 'button[title]', 'button[data-testid]',
      '[role="button"][aria-label]', '[role="button"][title]',
      'a[aria-label]', 'a[title]', 'button', '[role="button"]'
    ];
    const seen = new Set();
    for (const selector of selectors) {
      for (const element of main.querySelectorAll(selector)) {
        if (seen.has(element)) continue;
        seen.add(element);
        if (!is3DControl(element)) continue;
        if (element.id === BUTTON_ID || element.closest(`#${MODAL_ID}`)) continue;
        const rect = element.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) return element;
      }
    }
    return null;
  }

  function createTrigger(control) {
    const button = document.createElement('button');
    button.id = BUTTON_ID;
    button.type = 'button';
    button.className = typeof control.className === 'string'
      ? control.className
      : 'foundation-web-button relative clip group/interactable focus-visible:outline-focus disabled:outline-none cursor-pointer flex items-center justify-center stroke-none padding-y-none select-none radius-medium text-label-large height-1200 padding-x-medium bg-action-standard content-action-standard';
    button.innerHTML = `
      <div aria-hidden="true" data-testid="foundation-web-state-layer" class="absolute inset-[0] transition-colors group-hover/interactable:bg-[var(--color-state-hover)] group-active/interactable:bg-[var(--color-state-press)] group-disabled/interactable:bg-none"></div>
      <span class="flex items-center min-width-0 gap-small">
        <span class="padding-y-xsmall text-truncate-end text-no-wrap">Outfits</span>
      </span>`;
    button.style.textDecoration = 'none';
    button.setAttribute('aria-label', 'Show this user’s outfits');
    button.setAttribute('aria-haspopup', 'dialog');
    button.setAttribute('aria-expanded', 'false');
    button.addEventListener('click', () => toggleGallery());
    control.insertAdjacentElement('beforebegin', button);
    trigger = button;
    return button;
  }

  function stopDiscovery() {
    discoveryObserver?.disconnect();
    discoveryObserver = null;
  }

  function tryAttachTrigger() {
    if (!enabled || !currentUserId || !profileUserId()) return false;
    if (trigger?.isConnected) {
      trigger.dataset.userId = currentUserId;
      return true;
    }
    const control = find3DControl();
    if (!control) return false;
    createTrigger(control).dataset.userId = currentUserId;
    stopDiscovery();
    return true;
  }

  function startDiscovery() {
    if (!enabled || !currentUserId || trigger?.isConnected || discoveryObserver || !document.documentElement) return;
    tryAttachTrigger();
    if (trigger?.isConnected) return;
    discoveryObserver = new MutationObserver((records) => {
      if (!enabled || !profileUserId()) {
        stopDiscovery();
        return;
      }
      for (const record of records) {
        for (const node of record.addedNodes) {
          if (node.nodeType !== Node.ELEMENT_NODE) continue;
          if (node.matches?.('button,[role="button"],a') && is3DControl(node)) {
            if (tryAttachTrigger()) return;
          }
          if (node.querySelector?.('button[aria-label],button[title],button[data-testid],[role="button"][aria-label],[role="button"][title]')) {
            if (tryAttachTrigger()) return;
          }
        }
      }
    });
    discoveryObserver.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['aria-label', 'title', 'data-testid', 'data-test'],
      characterData: true
    });
  }

  function removeTrigger() {
    trigger?.remove();
    trigger = null;
  }

  function handleRouteChange() {
    const nextId = profileUserId();
    const nextKey = `${location.pathname}:${nextId || ''}`;
    if (nextKey === routeKey) {
      if (nextId && enabled) {
        currentUserId = nextId;
        if (!trigger?.isConnected) startDiscovery();
      }
      return;
    }
    routeKey = nextKey;
    stopDiscovery();
    if (!nextId) {
      currentUserId = null;
      removeTrigger();
      closeGallery();
      resetGalleryState();
      return;
    }
    if (currentUserId !== nextId) {
      removeTrigger();
      closeGallery();
      resetGalleryState();
    }
    currentUserId = nextId;
    if (!enabled) {
      removeTrigger();
      closeGallery();
      return;
    }
    startDiscovery();
  }

  function createModal() {
    const overlay = document.createElement('div');
    overlay.id = MODAL_ID;
    overlay.innerHTML = `
      <section class="rvlocal-outfits-dialog" role="dialog" aria-modal="true" aria-labelledby="rvlocal-outfits-title">
        <header class="rvlocal-outfits-header">
          <div class="rvlocal-outfits-heading">
            <h2 class="rvlocal-outfits-title" id="rvlocal-outfits-title">Outfits</h2>
            <p class="rvlocal-outfits-subtitle" data-role="subtitle"></p>
          </div>
          <button class="rvlocal-outfits-close" type="button" aria-label="Close outfits">×</button>
        </header>
        <div class="rvlocal-outfits-status" data-role="status" aria-live="polite">Open to load outfits.</div>
        <div class="rvlocal-outfits-grid-wrap">
          <div class="rvlocal-outfits-grid" data-role="grid"></div>
        </div>
        <div class="rvlocal-outfits-load-wrap">
          <button class="rvlocal-outfits-action" type="button" data-role="load-more" hidden>Load more</button>
        </div>
        <footer class="rvlocal-outfits-selection">
          <div class="rvlocal-outfits-selected-text" data-role="selected">Select an outfit to view its ID.</div>
          <div class="rvlocal-outfits-actions">
            <button class="rvlocal-outfits-action" type="button" data-role="copy-id" disabled>Copy ID</button>
          </div>
        </footer>
      </section>`;

    overlay.addEventListener('click', (event) => {
      if (event.target === overlay) closeGallery();
    });
    overlay.querySelector('.rvlocal-outfits-close').addEventListener('click', closeGallery);
    overlay.querySelector('[data-role="load-more"]').addEventListener('click', () => loadOutfitPage(false));
    overlay.querySelector('[data-role="copy-id"]').addEventListener('click', copySelectedId);
    document.body.appendChild(overlay);
    modal = overlay;
    return modal;
  }

  function resetGalleryState() {
    page = 1;
    hasMore = false;
    loading = false;
    loadedUserId = null;
    outfits = [];
    thumbnails = new Map();
    selectedOutfit = null;
    if (modal) {
      modal.querySelector('[data-role="grid"]').replaceChildren();
      modal.querySelector('[data-role="status"]').textContent = 'Open to load outfits.';
      modal.querySelector('[data-role="subtitle"]').textContent = '';
      modal.querySelector('[data-role="selected"]').textContent = 'Select an outfit to view its ID.';
      modal.querySelector('[data-role="copy-id"]').disabled = true;
      modal.querySelector('[data-role="load-more"]').hidden = true;
    }
  }

  function openGallery() {
    if (!enabled || !currentUserId) return;
    if (!modal) createModal();
    modal.dataset.open = 'true';
    trigger?.setAttribute('aria-expanded', 'true');
    bodyOverflowBefore = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    if (loadedUserId !== currentUserId && !loading) loadOutfitPage(true);
  }

  function closeGallery() {
    if (modal) modal.dataset.open = 'false';
    trigger?.setAttribute('aria-expanded', 'false');
    if (document.body) document.body.style.overflow = bodyOverflowBefore;
  }

  function toggleGallery() {
    if (modal?.dataset.open === 'true') closeGallery();
    else openGallery();
  }

  function setStatus(message) {
    if (modal) modal.querySelector('[data-role="status"]').textContent = message;
  }

  function normalizeOutfits(payload) {
    const list = Array.isArray(payload) ? payload :
      Array.isArray(payload?.data) ? payload.data :
      Array.isArray(payload?.outfits) ? payload.outfits :
      Array.isArray(payload?.items) ? payload.items : [];
    const normalizedItems = [];
    for (const item of list) {
      const id = String(item?.id ?? item?.userOutfitId ?? item?.outfitId ?? '');
      if (!/^\d{1,20}$/.test(id)) continue;
      if (item?.isEditable === false || item?.IsEditable === false) continue;
      normalizedItems.push({ id, name: String(item?.name ?? item?.Name ?? `Outfit ${id}`).trim().slice(0, 100) || `Outfit ${id}` });
    }
    return { items: normalizedItems, nextCursor: payload?.paginationToken || payload?.nextPageCursor || payload?.nextPageCursorValue || null };
  }

  function normalizeThumbnails(payload) {
    const list = Array.isArray(payload?.data) ? payload.data : Array.isArray(payload) ? payload : [];
    const result = new Map();
    for (const item of list) {
      const id = String(item?.targetId ?? item?.userOutfitId ?? item?.id ?? '');
      const imageUrl = String(item?.imageUrl ?? item?.image ?? '');
      if (!/^\d{1,20}$/.test(id) || !imageUrl) continue;
      try {
        const url = new URL(imageUrl);
        if (url.protocol === 'https:' && (url.hostname === 'rbxcdn.com' || url.hostname.endsWith('.rbxcdn.com'))) {
          result.set(id, url.href);
        }
      } catch {}
    }
    return result;
  }

  async function requestOutfits(userId, requestedPage) {
    return chrome.runtime.sendMessage({ type: 'RVLOCAL_OUTFITS_PAGE', userId, page: requestedPage });
  }

  async function requestThumbnails(ids) {
    return chrome.runtime.sendMessage({ type: 'RVLOCAL_OUTFITS_THUMBNAILS', outfitIds: ids });
  }

  function createOutfitCard(outfit) {
    const card = document.createElement('button');
    card.type = 'button';
    card.className = 'rvlocal-outfit-card';
    card.setAttribute('aria-pressed', 'false');
    card.dataset.outfitId = outfit.id;

    const imageWrap = document.createElement('span');
    imageWrap.className = 'rvlocal-outfit-image-wrap';
    const imageUrl = thumbnails.get(outfit.id);
    if (imageUrl) {
      const image = document.createElement('img');
      image.className = 'rvlocal-outfit-image';
      image.loading = 'lazy';
      image.decoding = 'async';
      image.alt = outfit.name;
      image.src = imageUrl;
      image.addEventListener('error', () => {
        image.remove();
        const placeholder = document.createElement('span');
        placeholder.className = 'rvlocal-outfit-placeholder';
        placeholder.textContent = 'Preview unavailable';
        imageWrap.appendChild(placeholder);
      }, { once: true });
      imageWrap.appendChild(image);
    } else {
      const placeholder = document.createElement('span');
      placeholder.className = 'rvlocal-outfit-placeholder';
      placeholder.textContent = 'Preview unavailable';
      imageWrap.appendChild(placeholder);
    }

    const name = document.createElement('span');
    name.className = 'rvlocal-outfit-name';
    name.textContent = outfit.name;
    const id = document.createElement('span');
    id.className = 'rvlocal-outfit-card-id';
    id.textContent = `ID: ${outfit.id}`;
    card.append(imageWrap, name, id);
    card.addEventListener('click', () => selectOutfit(outfit, card));
    return card;
  }

  function renderOutfits(newItems) {
    if (!modal) return;
    const grid = modal.querySelector('[data-role="grid"]');
    const fragment = document.createDocumentFragment();
    for (const outfit of newItems) fragment.appendChild(createOutfitCard(outfit));
    grid.appendChild(fragment);
    modal.querySelector('[data-role="subtitle"]').textContent = `${outfits.length} outfits · User ${currentUserId}`;
    const loadButton = modal.querySelector('[data-role="load-more"]');
    loadButton.hidden = !hasMore;
    loadButton.disabled = loading;
  }

  function selectOutfit(outfit, card) {
    selectedOutfit = outfit;
    if (!modal) return;
    for (const item of modal.querySelectorAll('.rvlocal-outfit-card')) {
      item.setAttribute('aria-pressed', String(item === card));
    }
    modal.querySelector('[data-role="selected"]').textContent = `${outfit.name} · Outfit ID: ${outfit.id}`;
    modal.querySelector('[data-role="copy-id"]').disabled = false;
  }

  async function copySelectedId() {
    if (!selectedOutfit) return;
    const copyButton = modal?.querySelector('[data-role="copy-id"]');
    try {
      await navigator.clipboard.writeText(selectedOutfit.id);
      if (copyButton) copyButton.textContent = 'Copied';
    } catch {
      if (copyButton) copyButton.textContent = selectedOutfit.id;
    }
    if (copyButton) {
      window.setTimeout(() => { if (copyButton.isConnected) copyButton.textContent = 'Copy ID'; }, 1200);
    }
  }

  function apiErrorMessage(result) {
    if (result?.status === 403 || result?.status === 401) return 'Roblox does not allow this outfit list to be viewed.';
    if (result?.status === 429) return 'Roblox is rate-limiting outfit requests. Try again shortly.';
    if (result?.status === 404) return 'This profile or its outfit list could not be found.';
    return result?.message || 'Could not load outfits from Roblox.';
  }

  async function loadOutfitPage(reset) {
    if (loading || !currentUserId || !modal) return;
    if (reset) resetGalleryState();
    loading = true;
    const requestedPage = page;
    setStatus(requestedPage === 1 ? 'Loading outfits…' : 'Loading more outfits…');
    const loadButton = modal.querySelector('[data-role="load-more"]');
    loadButton.disabled = true;

    try {
      const result = await requestOutfits(currentUserId, requestedPage);
      if (!result?.ok) throw new Error(apiErrorMessage(result));
      const normalized = normalizeOutfits(result.payload);
      const newItems = normalized.items.filter((item) => !outfits.some((existing) => existing.id === item.id));
      if (newItems.length) {
        const thumbResult = await requestThumbnails(newItems.map((item) => item.id));
        if (thumbResult?.ok) {
          const received = normalizeThumbnails(thumbResult.payload);
          for (const [id, url] of received) thumbnails.set(id, url);
        }
      }
      outfits.push(...newItems);
      hasMore = Boolean(normalized.nextCursor) || normalized.items.length >= PAGE_SIZE;
      page = requestedPage + 1;
      loadedUserId = currentUserId;
      renderOutfits(newItems);
      if (!outfits.length) {
        const empty = document.createElement('div');
        empty.className = 'rvlocal-outfits-empty';
        empty.textContent = 'No public outfits were returned for this user.';
        modal.querySelector('[data-role="grid"]').appendChild(empty);
        setStatus('No outfits available. Roblox may restrict this user’s outfit list.');
      } else {
        setStatus(`${outfits.length} outfits loaded.`);
      }
    } catch (error) {
      setStatus(error instanceof Error ? error.message : 'Could not load outfits from Roblox.');
      if (!outfits.length) {
        const empty = document.createElement('div');
        empty.className = 'rvlocal-outfits-empty';
        empty.textContent = 'Outfits could not be loaded. You can retry.';
        modal.querySelector('[data-role="grid"]').replaceChildren(empty);
      }
      hasMore = false;
      loadButton.hidden = outfits.length === 0;
    } finally {
      loading = false;
      loadButton.disabled = false;
      loadButton.hidden = !hasMore;
    }
  }

  function onKeydown(event) {
    if (event.key === 'Escape' && modal?.dataset.open === 'true') closeGallery();
  }

  function setEnabled(value) {
    enabled = value === true;
    if (!enabled) {
      stopDiscovery();
      removeTrigger();
      if (modal) modal.remove();
      modal = null;
      if (document.body) document.body.style.overflow = bodyOverflowBefore;
      return;
    }
    handleRouteChange();
  }

  function start() {
    installStyles();
    chrome.storage.local.get(STORAGE_DEFAULTS)
      .then((settings) => setEnabled(settings.profileOutfitsEnabled !== false))
      .catch(() => setEnabled(true));

    chrome.storage.onChanged.addListener((changes, area) => {
      if (area === 'local' && Object.hasOwn(changes, 'profileOutfitsEnabled')) {
        setEnabled(changes.profileOutfitsEnabled.newValue !== false);
      }
    });

    window.addEventListener(ROUTE_EVENT, handleRouteChange);
    window.addEventListener('popstate', handleRouteChange);
    window.addEventListener('hashchange', handleRouteChange);
    window.addEventListener('pageshow', handleRouteChange);
    document.addEventListener('keydown', onKeydown);
    handleRouteChange();
  }

  if (document.documentElement) start();
  else document.addEventListener('DOMContentLoaded', start, { once: true });
})();
