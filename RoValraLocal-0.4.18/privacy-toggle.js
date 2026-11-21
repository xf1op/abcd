'use strict';

(() => {
  const ITEM_ID = 'rvlocal-privacy-nav-item';
  const MENU_ID = 'rvlocal-privacy-menu';
  const STYLE_ID = 'rvlocal-privacy-style';
  const SETTINGS = [
    {
      key: 'whoCanSeeMyInventory',
      label: 'Inventory',
      values: [
        'NoOne',
        'Friends',
        'FriendsAndFollowing',
        'FriendsFollowingAndFollowers',
        'AllUsers'
      ]
    },
    {
      key: 'whoCanSeeMyOnlineStatus',
      label: 'Online status',
      values: [
        'NoOne',
        'TrustedFriends',
        'Friends',
        'FriendsAndFollowing',
        'FriendsFollowingAndFollowers',
        'AllUsers'
      ]
    },
    {
      key: 'whoCanJoinMeInExperiences',
      label: 'Current experience',
      values: [
        'NoOne',
        'TrustedFriends',
        'Friends',
        'Following',
        'Followers',
        'All'
      ]
    }
  ];
  const VALUE_LABELS = {
    NoOne: 'No one',
    TrustedFriends: 'Trusted friends',
    Friends: 'Friends',
    FriendsAndFollowing: 'Friends and following',
    Following: 'Friends and following',
    FriendsFollowingAndFollowers: 'Friends, following and followers',
    Followers: 'Friends, following and followers',
    AllUsers: 'Everyone',
    AllAuthenticatedUsers: 'Everyone',
    All: 'Everyone'
  };
  const CSS = `
#${ITEM_ID} {
  position: relative;
  display: flex;
  align-items: center;
  flex: 0 0 auto;
  z-index: 20;
}
#${ITEM_ID} .rvlocal-privacy-trigger {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  min-width: 40px;
  padding: 0;
  border: 0;
  border-radius: var(--radius-medium, 8px);
  background: transparent;
  color: var(--color-content-default, inherit);
  cursor: pointer;
}
#${ITEM_ID} .rvlocal-privacy-trigger:hover,
#${ITEM_ID} .rvlocal-privacy-trigger[aria-expanded="true"] {
  background: var(--color-state-hover, transparent);
}
#${ITEM_ID} .rvlocal-privacy-trigger:focus-visible {
  outline: 2px solid var(--color-system-emphasis, currentColor);
  outline-offset: 2px;
}
#${ITEM_ID} .rvlocal-privacy-icon {
  display: block;
  width: 22px;
  height: 22px;
  fill: currentColor;
}
#${MENU_ID} {
  position: absolute;
  z-index: 2147482500;
  top: calc(100% + 4px);
  right: 0;
  width: 350px;
  max-width: calc(100vw - 16px);
  padding: 4px 0;
  overflow: hidden;
  border: 1px solid var(--color-content-muted, rgba(127,127,127,.65));
  border-color: color-mix(in srgb, var(--color-content-default, #393b3d) 24%, var(--color-surface-0, #fff));
  border-radius: var(--radius-medium, 8px);
  background: var(--color-surface-0, transparent);
  color: var(--color-content-default, inherit);
  box-shadow: var(--shadow-medium, none);
  font: 13px/1.35 "Builder Sans", "Helvetica Neue", Arial, sans-serif;
}
#${MENU_ID}[hidden] { display: none !important; }
#${MENU_ID}:not([hidden]) { display: block !important; }
#${MENU_ID} * { box-sizing: border-box; }
#${MENU_ID} .rvlocal-privacy-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  min-height: 43px;
  padding: 5px 10px;
}
#${MENU_ID} .rvlocal-privacy-row + .rvlocal-privacy-row {
  border-top: 1px solid var(--color-divider, transparent);
}
#${MENU_ID} .rvlocal-privacy-label {
  display: block;
  flex: 0 0 112px;
  min-width: 0;
  margin: 0;
  color: var(--color-content-default, inherit);
  font-size: 13px;
  line-height: 17px;
  font-weight: 500;
}
#${MENU_ID} .rvlocal-privacy-select {
  display: block;
  flex: 1 1 auto;
  width: 0;
  min-width: 0;
  height: 32px;
  min-height: 32px;
  margin: 0;
  padding: 0 8px;
  border: 1px solid var(--color-border, var(--color-divider, transparent));
  border-radius: var(--radius-small, 4px);
  background: var(--color-surface-1, var(--color-surface-0, transparent));
  color: var(--color-content-default, inherit);
  font: inherit;
  font-size: 12px;
  line-height: 16px;
  cursor: pointer;
}
#${MENU_ID} .rvlocal-privacy-select:hover:not(:disabled) {
  border-color: var(--color-content-muted, currentColor);
}
#${MENU_ID} .rvlocal-privacy-select:focus-visible {
  border-color: var(--color-system-emphasis, currentColor);
  outline: 2px solid var(--color-system-emphasis, currentColor);
  outline-offset: 1px;
}
#${MENU_ID} .rvlocal-privacy-select:disabled {
  cursor: default;
  opacity: .6;
}
#${MENU_ID} .rvlocal-privacy-status {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
}
@media (max-width: 380px) {
  #${MENU_ID} .rvlocal-privacy-label { flex-basis: 96px; }
}
`;

  let item = null;
  let trigger = null;
  let menu = null;
  let status = null;
  let selects = {};
  let settings = null;
  let settingOptions = {};
  let opening = false;
  let applying = false;

  function installStyles() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = CSS;
    (document.head || document.documentElement).appendChild(style);
  }

  function settingValue(payload, key) {
    const entry = payload?.[key] ?? null;
    const value = entry?.currentValue ?? entry?.value ?? entry;
    return typeof value === 'string' && value.length > 0 && value.length <= 64 ? value : null;
  }

  function optionValue(option) {
    if (typeof option === 'string') return option;
    if (!option || typeof option !== 'object') return null;
    const value = option.value ?? option.Value ?? option.enumValue ?? option.key ?? option.name ?? option.id;
    return typeof value === 'string' && value.length > 0 && value.length <= 64 ? value : null;
  }

  function availableOptions(payload, setting, currentValue) {
    const entry = payload?.[setting.key];
    const raw = entry?.options ?? entry?.allowedValues ?? entry?.availableOptions ?? entry?.values;
    const list = Array.isArray(raw) ? raw : raw && typeof raw === 'object' ? Object.values(raw) : [];
    const supplied = new Set(list.map(optionValue).filter(Boolean));
    const options = setting.values.filter((value) => !supplied.size || supplied.has(value));
    if (
      currentValue &&
      !options.includes(currentValue) &&
      !(setting.key === 'whoCanSeeMyInventory' && currentValue === 'TrustedFriends')
    ) options.push(currentValue);
    return options.length ? options : setting.values.slice();
  }

  function optionLabel(value) {
    return VALUE_LABELS[value] || value;
  }

  function setStatus(message) {
    if (status) status.textContent = message || '';
    if (trigger && message) trigger.title = `Privacy controls: ${message}`;
    else if (trigger) trigger.title = 'Privacy controls';
  }

  function setUnavailable() {
    for (const setting of SETTINGS) {
      const select = selects[setting.key];
      if (!select) continue;
      select.replaceChildren();
      const option = document.createElement('option');
      option.value = '';
      option.textContent = 'Unavailable';
      select.appendChild(option);
      select.disabled = true;
    }
  }

  function setBusy(value) {
    for (const setting of SETTINGS) {
      const select = selects[setting.key];
      if (select) select.disabled = value || !settings || !settingOptions[setting.key]?.length;
    }
  }

  function renderSettings(payload) {
    const values = {};
    const options = {};

    for (const setting of SETTINGS) {
      const value = settingValue(payload, setting.key);
      if (!value) throw new Error('Roblox did not return all three privacy settings.');
      values[setting.key] = value;
      options[setting.key] = availableOptions(payload, setting, value);
    }

    settings = values;
    settingOptions = options;

    for (const setting of SETTINGS) {
      const select = selects[setting.key];
      select.replaceChildren();
      for (const value of options[setting.key]) {
        const option = document.createElement('option');
        option.value = value;
        option.textContent = optionLabel(value);
        select.appendChild(option);
      }
      select.value = values[setting.key];
    }
  }

  function applyRobloxTheme() {
    if (!menu) return;
    const background = getComputedStyle(menu).backgroundColor;
    const channels = background.match(/[\d.]+/g);
    if (!channels || channels.length < 3) return;
    const [red, green, blue] = channels.slice(0, 3).map(Number);
    const luminance = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255;
    menu.style.colorScheme = luminance < 0.5 ? 'dark' : 'light';
  }

  async function send(type, extra = {}) {
    const result = await chrome.runtime.sendMessage({ type, ...extra });
    if (!result?.ok) throw new Error(result?.message || 'Roblox privacy request failed.');
    return result.payload;
  }

  async function readSettings() {
    const payload = await send('RVLOCAL_PRIVACY_GET');
    renderSettings(payload);
    return settings;
  }

  async function refreshSettings() {
    if (opening || applying) return;
    opening = true;
    setBusy(true);
    setStatus('Loading settings');
    applyRobloxTheme();
    try {
      await readSettings();
      setStatus('');
    } catch (error) {
      settings = null;
      settingOptions = {};
      setUnavailable();
      setStatus(error instanceof Error ? error.message : 'Could not load privacy settings');
    } finally {
      opening = false;
      setBusy(false);
    }
  }

  async function saveSetting(key, value) {
    const setting = SETTINGS.find((entry) => entry.key === key);
    if (!setting || applying || !settings || !settingOptions[key]?.includes(value)) return;

    applying = true;
    setBusy(true);
    setStatus('Saving setting');
    try {
      await send('RVLOCAL_PRIVACY_SET', { values: { [key]: value } });
      const payload = await send('RVLOCAL_PRIVACY_GET');
      const confirmed = settingValue(payload, key);
      renderSettings(payload);
      if (confirmed !== value) throw new Error('Roblox did not confirm the privacy update');
      setStatus('');
    } catch (error) {
      try {
        await readSettings();
      } catch {
        settings = null;
        settingOptions = {};
        setUnavailable();
      }
      setStatus(error instanceof Error ? error.message : 'Could not update privacy setting');
    } finally {
      applying = false;
      setBusy(false);
    }
  }

  function createMenu() {
    menu = document.createElement('div');
    menu.id = MENU_ID;
    menu.className = 'dropdown-menu new-dropdown-menu rvlocal-privacy-menu';
    menu.hidden = true;
    menu.setAttribute('role', 'dialog');
    menu.setAttribute('aria-label', 'Privacy settings');

    for (const setting of SETTINGS) {
      const row = document.createElement('div');
      row.className = 'rvlocal-privacy-row';

      const label = document.createElement('label');
      label.className = 'rvlocal-privacy-label';
      label.htmlFor = `rvlocal-privacy-${setting.key}`;
      label.textContent = setting.label;

      const select = document.createElement('select');
      select.className = 'form-control rvlocal-privacy-select';
      select.id = `rvlocal-privacy-${setting.key}`;
      select.disabled = true;
      select.addEventListener('change', () => saveSetting(setting.key, select.value));

      selects[setting.key] = select;
      row.append(label, select);
      menu.appendChild(row);
    }

    status = document.createElement('span');
    status.className = 'rvlocal-privacy-status';
    status.setAttribute('role', 'status');
    status.setAttribute('aria-live', 'polite');
    menu.appendChild(status);
    return menu;
  }

  function createItem() {
    item = document.createElement('li');
    item.id = ITEM_ID;
    item.className = 'navbar-icon-item';

    trigger = document.createElement('button');
    trigger.type = 'button';
    trigger.className = 'btn-navigation-nav-settings-md rvlocal-privacy-trigger';
    trigger.setAttribute('aria-label', 'Privacy controls');
    trigger.setAttribute('aria-haspopup', 'dialog');
    trigger.setAttribute('aria-expanded', 'false');
    trigger.setAttribute('aria-controls', MENU_ID);
    trigger.title = 'Privacy controls';
    trigger.innerHTML = '<svg class="rvlocal-privacy-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.5 4.5 5.4v5.2c0 5.1 3.1 9.2 7.5 10.9 4.4-1.7 7.5-5.8 7.5-10.9V5.4L12 2.5Zm0 2.2 5.3 2v3.9c0 3.9-2.2 7.2-5.3 8.7-3.1-1.5-5.3-4.8-5.3-8.7V6.7l5.3-2Zm0 2.7a3.1 3.1 0 0 0-3.1 3.1v.7h-.8v4.3h7.8v-4.3h-.8v-.7A3.1 3.1 0 0 0 12 7.4Zm-1.3 3.1a1.3 1.3 0 1 1 2.6 0v.7h-2.6v-.7Z"/></svg>';
    trigger.addEventListener('click', () => {
      const willOpen = menu.hidden;
      menu.hidden = !willOpen;
      trigger.setAttribute('aria-expanded', String(willOpen));
      if (willOpen) refreshSettings();
    });

    item.append(trigger, createMenu());
    return item;
  }

  function findNavList() {
    return document.querySelector('#right-navigation-header .navbar-right.rbx-navbar-right > ul.rbx-navbar-icon-group') ||
      document.querySelector('#right-navigation-header .rbx-navbar-right > ul.navbar-right');
  }

  function attach() {
    if (item?.isConnected) return true;
    const list = findNavList();
    if (!list) return false;
    const profile = list.querySelector(':scope > li.age-bracket-label') ||
      Array.from(list.children).find((entry) => entry.querySelector('a[href*="/users/"][href*="/profile"]'));
    if (!profile) return false;
    installStyles();
    list.insertBefore(createItem(), profile);
    return true;
  }

  function closeMenu() {
    if (!menu || menu.hidden) return;
    menu.hidden = true;
    trigger?.setAttribute('aria-expanded', 'false');
  }

  document.addEventListener('click', (event) => {
    if (item?.isConnected && !item.contains(event.target)) closeMenu();
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') closeMenu();
  });

  function start() {
    const observer = new MutationObserver(() => {
      if (!item?.isConnected) attach();
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
    attach();
  }

  if (document.documentElement) start();
  else document.addEventListener('DOMContentLoaded', start, { once: true });
})();
