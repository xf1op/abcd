'use strict';

(() => {
  const STORAGE_DEFAULTS = {
    sidebarEnabled: true,
    sidebarCollapsed: true,
    sidebarButtonsEnabled: true,
    sidebarButtonProfileCard: true,
    sidebarButtonHome: true,
    sidebarButtonProfile: true,
    sidebarButtonRobloxPlus: true,
    sidebarButtonMessages: true,
    sidebarButtonFriends: true,
    sidebarButtonAvatar: true,
    sidebarButtonInventory: true,
    sidebarButtonTrade: true,
    sidebarButtonCommunities: true,
    sidebarButtonNewsroom: true,
    sidebarButtonOfficialStore: true,
    sidebarButtonGiftCards: true,
    sidebarButtonPlusPromo: true
  };
  const ENABLED_ATTRIBUTE = 'data-rvlocal-sidebar-enabled';
  const ROOT_ATTRIBUTE = 'data-rvlocal-sidebar-state';
  const DESKTOP_ATTRIBUTE = 'data-rvlocal-sidebar-desktop';
  const MAIN_ATTRIBUTE = 'data-rvlocal-sidebar-main';
  const READY_ATTRIBUTE = 'data-rvlocal-nav-ready';
  const STYLE_ID = 'rvlocal-sidebar-collapse-style';
  const BUTTON_ID = 'rvlocal-sidebar-toggle';
  const NAV_SELECTOR = '.left-nav';
  const MAIN_SELECTOR = '#container-main';
  const LAYOUT_SELECTOR = `${NAV_SELECTOR},#wrap,${MAIN_SELECTOR}`;
  const PROFILE_LINK_SELECTOR = 'nav > ul > li > a[href="/users/profile"]';
  const BUTTON_SETTINGS = [
    ['sidebarButtonProfileCard', 'profile-card', 'nav > ul > li:has(> a[href="/users/profile"])'],
    ['sidebarButtonHome', 'home', 'nav > ul > li:has(> a[href$="/home"])'],
    ['sidebarButtonProfile', 'profile', 'nav > ul > li:has(> a[href*="/users/profile"]:not([href="/users/profile"]))'],
    ['sidebarButtonRobloxPlus', 'roblox-plus', 'nav > ul > li:has(> a[href$="/plus"]:not(.gap-y-medium))'],
    ['sidebarButtonMessages', 'messages', 'nav > ul > li:has(> a[href*="/my/messages"])'],
    ['sidebarButtonFriends', 'friends', 'nav > ul > li:has(> a[href*="/users/friends"])'],
    ['sidebarButtonAvatar', 'avatar', 'nav > ul > li:has(> a[href*="/my/avatar"])'],
    ['sidebarButtonInventory', 'inventory', 'nav > ul > li:has(> a[href*="/users/inventory"])'],
    ['sidebarButtonTrade', 'trade', 'nav > ul > li:has(> a[href*="/trades"])'],
    ['sidebarButtonCommunities', 'communities', 'nav > ul > li:has(> a[href*="/communities"])'],
    ['sidebarButtonNewsroom', 'newsroom', 'nav > ul > li:has(> a[href^="https://blog.roblox.com"])'],
    ['sidebarButtonOfficialStore', 'official-store', 'nav > ul > li:has(> button)'],
    ['sidebarButtonGiftCards', 'gift-cards', 'nav > ul > li:has(> a[href*="/giftcards-us"])'],
    ['sidebarButtonPlusPromo', 'plus-promo', 'nav > ul > li:has(> a.gap-y-medium[href$="/plus"])']
  ];
  const NAV_BUTTON_STORAGE_KEYS = BUTTON_SETTINGS.map(([key]) => key);
  const STYLE_RULES = BUTTON_SETTINGS.map(([, attribute, selector]) =>
    `html[data-rvlocal-hide-${attribute}="true"] .left-nav ${selector} { display: none !important; }`
  ).join('\n');
  const STYLES = `
html[${READY_ATTRIBUTE}="false"] .left-nav {
  visibility: hidden !important;
}
${STYLE_RULES}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"][${ROOT_ATTRIBUTE}="collapsed"] .left-nav {
  width: 64px !important;
  min-width: 64px !important;
  max-width: 64px !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"][${ROOT_ATTRIBUTE}="collapsed"] .left-nav > div:first-child {
  width: 63px !important;
  min-width: 63px !important;
  max-width: 63px !important;
  flex: 0 0 63px !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"][${ROOT_ATTRIBUTE}="collapsed"] .left-nav > div:first-child > div:first-child {
  width: 63px !important;
  min-width: 63px !important;
  max-width: 63px !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"][${ROOT_ATTRIBUTE}="collapsed"] .left-nav > div:first-child > div:first-child > div:first-child {
  width: 63px !important;
  min-width: 63px !important;
  padding-left: 4px !important;
  padding-right: 4px !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"][${ROOT_ATTRIBUTE}="collapsed"] .left-nav nav,
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"][${ROOT_ATTRIBUTE}="collapsed"] .left-nav nav > ul {
  width: 100% !important;
  min-width: 0 !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"][${ROOT_ATTRIBUTE}="collapsed"] .left-nav nav > ul > li {
  width: 100% !important;
  min-width: 0 !important;
  display: flex !important;
  justify-content: center !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"][${ROOT_ATTRIBUTE}="collapsed"] .left-nav nav > ul > li > a:not([href="/plus"]),
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"][${ROOT_ATTRIBUTE}="collapsed"] .left-nav nav > ul > li > button {
  width: 48px !important;
  min-width: 48px !important;
  max-width: 48px !important;
  height: 48px !important;
  min-height: 48px !important;
  margin-left: auto !important;
  margin-right: auto !important;
  padding: 0 !important;
  gap: 0 !important;
  justify-content: center !important;
  align-items: center !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"][${ROOT_ATTRIBUTE}="collapsed"] .left-nav nav > ul > li > a:not([href="/plus"]) > span:nth-of-type(n + 2),
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"][${ROOT_ATTRIBUTE}="collapsed"] .left-nav nav > ul > li > button > span:nth-of-type(n + 2) {
  display: none !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"][${ROOT_ATTRIBUTE}="collapsed"] .left-nav nav > ul > li:has(> a[href="/plus"]) {
  display: none !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"][${MAIN_ATTRIBUTE}="true"][${ROOT_ATTRIBUTE}="collapsed"] #container-main {
  margin-left: 64px !important;
  width: calc(100% - 64px) !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"] .left-nav #${BUTTON_ID} {
  position: absolute !important;
  z-index: 1003 !important;
  top: 50% !important;
  right: -11px !important;
  display: flex !important;
  width: 22px !important;
  height: 44px !important;
  align-items: center !important;
  justify-content: center !important;
  padding: 0 !important;
  border: 1px solid rgba(128, 128, 128, .38) !important;
  border-left: 0 !important;
  border-radius: 0 8px 8px 0 !important;
  background: var(--color-surface-0, #191b20) !important;
  color: var(--color-content-default, #d7dce2) !important;
  box-shadow: 2px 1px 5px rgba(0, 0, 0, .12) !important;
  cursor: pointer !important;
  transform: translateY(-50%) !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"] .left-nav #${BUTTON_ID}:hover {
  background: var(--color-state-hover, rgba(128, 128, 128, .2)) !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"] .left-nav #${BUTTON_ID}:focus-visible {
  outline: 2px solid var(--color-focus, #6ea8fe) !important;
  outline-offset: 2px !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"] .left-nav #${BUTTON_ID} span {
  width: 7px !important;
  height: 7px !important;
  border-top: 2px solid currentColor !important;
  border-right: 2px solid currentColor !important;
  transform: rotate(45deg) !important;
}
html[${ENABLED_ATTRIBUTE}="true"][${DESKTOP_ATTRIBUTE}="true"] .left-nav #${BUTTON_ID}[data-collapsed="false"] span {
  transform: rotate(-135deg) !important;
}
`;

  let enabled = true;
  let collapsed = true;
  let sidebarButtonsEnabled = true;
  let buttonSettings = { ...STORAGE_DEFAULTS };
  let toggleButton = null;
  let observer = null;
  let navMediaObserver = null;
  let observedNav = null;
  let updateQueued = false;
  let started = false;
  const savedImageSources = new WeakMap();

  function installStyles() {
    const root = document.documentElement;
    if (!root) return;
    root.setAttribute(READY_ATTRIBUTE, 'false');
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = STYLES;
    (document.head || root).appendChild(style);
  }

  function updateNavigationLabels() {
    const nav = document.querySelector(NAV_SELECTOR);
    if (!nav) return;

    for (const item of nav.querySelectorAll('a,button')) {
      if (item.id === BUTTON_ID || item.matches('a.gap-y-medium')) continue;
      const label = String(item.textContent || '').replace(/\s+/g, ' ').trim();
      if (!label) continue;
      if (!item.hasAttribute('aria-label')) item.setAttribute('aria-label', label);
      if (enabled && collapsed && !item.hasAttribute('title')) {
        item.setAttribute('title', label);
        item.dataset.rvlocalTooltip = 'true';
      } else if ((!enabled || !collapsed) && item.dataset.rvlocalTooltip === 'true') {
        item.removeAttribute('title');
        delete item.dataset.rvlocalTooltip;
      }
    }
  }

  function updateToggle() {
    if (toggleButton) {
      toggleButton.dataset.collapsed = String(collapsed);
      toggleButton.setAttribute('aria-label', collapsed ? 'Expand sidebar' : 'Collapse sidebar');
      toggleButton.title = collapsed ? 'Expand sidebar' : 'Collapse sidebar';
    }
    updateNavigationLabels();
  }

  function setCollapsed(value, persist = false) {
    collapsed = value === true;
    if (enabled) {
      document.documentElement?.setAttribute(ROOT_ATTRIBUTE, collapsed ? 'collapsed' : 'expanded');
      updateToggle();
    } else {
      document.documentElement?.removeAttribute(ROOT_ATTRIBUTE);
      updateNavigationLabels();
    }
    if (persist) chrome.storage.local.set({ sidebarCollapsed: collapsed }).catch(() => {});
  }

  function syncProfileAvatarMedia() {
    const nav = document.querySelector(NAV_SELECTOR);
    const profileLink = nav?.querySelector(PROFILE_LINK_SELECTOR);
    if (!profileLink) return;
    const suppress = sidebarButtonsEnabled && buttonSettings.sidebarButtonProfileCard === false;

    for (const image of profileLink.querySelectorAll('img,source')) {
      if (suppress) {
        let saved = savedImageSources.get(image);
        if (!saved) {
          saved = {};
          savedImageSources.set(image, saved);
        }
        for (const attribute of ['src', 'srcset', 'sizes']) {
          if (image.hasAttribute(attribute)) {
            saved[attribute] = image.getAttribute(attribute);
            image.removeAttribute(attribute);
          }
        }
      } else {
        const saved = savedImageSources.get(image);
        if (!saved) continue;
        for (const attribute of ['src', 'srcset', 'sizes']) {
          if (saved[attribute] !== undefined && !image.hasAttribute(attribute)) {
            image.setAttribute(attribute, saved[attribute]);
          }
        }
        savedImageSources.delete(image);
      }
    }
  }

  function applySidebarButtonSettings(settings) {
    sidebarButtonsEnabled = settings.sidebarButtonsEnabled !== false;
    buttonSettings = { ...buttonSettings, ...settings };
    const root = document.documentElement;
    if (!root) return;

    for (const [key, attribute] of BUTTON_SETTINGS) {
      if (sidebarButtonsEnabled && settings[key] === false) root.setAttribute(`data-rvlocal-hide-${attribute}`, 'true');
      else root.removeAttribute(`data-rvlocal-hide-${attribute}`);
    }
    attachNavMediaObserver(document.querySelector(NAV_SELECTOR));
  }

  function setEnabled(value) {
    enabled = value === true;
    const root = document.documentElement;
    if (!root) return;

    if (enabled) {
      root.setAttribute(ENABLED_ATTRIBUTE, 'true');
      root.setAttribute(ROOT_ATTRIBUTE, collapsed ? 'collapsed' : 'expanded');
      updateToggle();
      scheduleLayoutUpdate();
      return;
    }

    root.removeAttribute(ENABLED_ATTRIBUTE);
    root.removeAttribute(DESKTOP_ATTRIBUTE);
    root.removeAttribute(MAIN_ATTRIBUTE);
    root.removeAttribute(ROOT_ATTRIBUTE);
    const button = document.getElementById(BUTTON_ID);
    button?.remove();
    toggleButton = null;
    updateNavigationLabels();
  }

  function attachToggle() {
    if (!enabled) return false;
    const nav = document.querySelector(NAV_SELECTOR);
    if (!nav) {
      toggleButton = null;
      return false;
    }

    const existing = nav.querySelector(`#${BUTTON_ID}`);
    if (existing) {
      toggleButton = existing;
      updateToggle();
      return true;
    }

    const button = document.createElement('button');
    button.id = BUTTON_ID;
    button.type = 'button';
    button.setAttribute('aria-label', collapsed ? 'Expand sidebar' : 'Collapse sidebar');
    button.title = collapsed ? 'Expand sidebar' : 'Collapse sidebar';
    button.innerHTML = '<span aria-hidden="true"></span>';
    button.addEventListener('click', () => setCollapsed(!collapsed, true));
    nav.appendChild(button);
    toggleButton = button;
    updateToggle();
    return true;
  }

  function updateDesktopMode() {
    const root = document.documentElement;
    if (!root) return false;
    if (!enabled) {
      root.removeAttribute(DESKTOP_ATTRIBUTE);
      root.removeAttribute(MAIN_ATTRIBUTE);
      return false;
    }

    const nav = document.querySelector(NAV_SELECTOR);
    if (!nav) {
      root.removeAttribute(DESKTOP_ATTRIBUTE);
      root.removeAttribute(MAIN_ATTRIBUTE);
      toggleButton = null;
      return false;
    }

    const navStyle = getComputedStyle(nav);
    const navRect = nav.getBoundingClientRect();
    const largeViewport = window.innerWidth >= 1024;
    const desktopVisible = largeViewport && navStyle.visibility === 'visible' &&
      navStyle.display !== 'none' && navRect.width > 0;
    root.setAttribute(DESKTOP_ATTRIBUTE, String(desktopVisible));

    const main = document.querySelector(MAIN_SELECTOR);
    const mainOffset = main ? Number.parseFloat(getComputedStyle(main).marginLeft) || 0 : 0;
    root.setAttribute(MAIN_ATTRIBUTE, String(desktopVisible && mainOffset > 0));

    if (desktopVisible) attachToggle();
    else updateNavigationLabels();
    return true;
  }

  function attachNavMediaObserver(nav) {
    const shouldWatch = sidebarButtonsEnabled && buttonSettings.sidebarButtonProfileCard === false;
    if (!shouldWatch) {
      navMediaObserver?.disconnect();
      navMediaObserver = null;
      observedNav = null;
      syncProfileAvatarMedia();
      return;
    }
    if (!nav || observedNav === nav) {
      syncProfileAvatarMedia();
      return;
    }
    navMediaObserver?.disconnect();
    observedNav = nav;
    syncProfileAvatarMedia();
    navMediaObserver = new MutationObserver(() => syncProfileAvatarMedia());
    navMediaObserver.observe(nav, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['src', 'srcset', 'sizes']
    });
  }

  function scheduleLayoutUpdate() {
    if (updateQueued) return;
    updateQueued = true;
    const run = () => {
      updateQueued = false;
      const nav = document.querySelector(NAV_SELECTOR);
      if (nav) attachNavMediaObserver(nav);
      attachToggle();
      updateDesktopMode();
    };
    if (typeof requestAnimationFrame === 'function') requestAnimationFrame(run);
    else setTimeout(run, 0);
  }

  function nodeContainsLayoutElement(node) {
    if (!node || node.nodeType !== Node.ELEMENT_NODE) return false;
    return node.matches(LAYOUT_SELECTOR) || Boolean(node.querySelector(LAYOUT_SELECTOR));
  }

  function startObserver() {
    if (observer || !document.documentElement) return;
    observer = new MutationObserver((records) => {
      for (const record of records) {
        if (record.type === 'attributes') {
          if (record.target === document.documentElement || record.target === document.body || record.target.matches?.(LAYOUT_SELECTOR)) {
            scheduleLayoutUpdate();
            return;
          }
        } else {
          for (const node of [...record.addedNodes, ...record.removedNodes]) {
            if (nodeContainsLayoutElement(node)) {
              const nav = node.matches?.(NAV_SELECTOR) ? node : node.querySelector?.(NAV_SELECTOR);
              if (nav) attachNavMediaObserver(nav);
              scheduleLayoutUpdate();
              return;
            }
          }
          if (record.target.nodeType === Node.ELEMENT_NODE && record.target.closest?.(NAV_SELECTOR)) {
            syncProfileAvatarMedia();
          }
        }
      }
    });
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class']
    });
  }

  function finishInitialization(settings) {
    applySidebarButtonSettings(settings);
    collapsed = settings.sidebarCollapsed !== false;
    setEnabled(settings.sidebarEnabled !== false);
    setCollapsed(collapsed);
    document.documentElement?.removeAttribute(READY_ATTRIBUTE);
    scheduleLayoutUpdate();
  }

  function start() {
    if (started) return;
    started = true;
    installStyles();
    startObserver();

    chrome.storage.local.get(STORAGE_DEFAULTS)
      .then(finishInitialization)
      .catch(() => finishInitialization(STORAGE_DEFAULTS));

    chrome.storage.onChanged.addListener((changes, area) => {
      if (area !== 'local') return;
      if (Object.hasOwn(changes, 'sidebarCollapsed')) {
        setCollapsed(changes.sidebarCollapsed.newValue !== false);
      }
      if (Object.hasOwn(changes, 'sidebarEnabled')) {
        setEnabled(changes.sidebarEnabled.newValue !== false);
      }
      if (Object.hasOwn(changes, 'sidebarButtonsEnabled') || NAV_BUTTON_STORAGE_KEYS.some((key) => Object.hasOwn(changes, key))) {
        chrome.storage.local.get(STORAGE_DEFAULTS).then(applySidebarButtonSettings).catch(() => {});
      }
    });

    window.addEventListener('resize', scheduleLayoutUpdate, { passive: true });
    window.addEventListener('popstate', scheduleLayoutUpdate);
    window.addEventListener('hashchange', scheduleLayoutUpdate);
    window.addEventListener('pageshow', scheduleLayoutUpdate);
    window.addEventListener('DOMContentLoaded', scheduleLayoutUpdate, { once: true });
    window.addEventListener('load', scheduleLayoutUpdate, { once: true });
  }

  if (document.documentElement) start();
  else {
    const earlyObserver = new MutationObserver(() => {
      if (!document.documentElement) return;
      earlyObserver.disconnect();
      start();
    });
    earlyObserver.observe(document, { childList: true, subtree: true });
    document.addEventListener('DOMContentLoaded', () => {
      earlyObserver.disconnect();
      start();
    }, { once: true });
  }
})();
