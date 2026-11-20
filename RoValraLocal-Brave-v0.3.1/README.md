# RoValra Local 0.3.1

A lightweight, local-first Brave/Chromium extension for Roblox page customizations.

## Changes in 0.3.1

- Replaced the three separate homepage controls with one **Clean up Home page** toggle.
- When enabled, the feed response is reduced to Continue and Favorites; Friends, Standout Games, and recommendation sections are removed from the returned `sorts` data.
- Expanded the DOM fallback to recognize plain `div`/`span` heading markup as well as semantic headings, so it can hide known unwanted sections even when Roblox changes the markup.
- Added compact diagnostics for which section labels were hidden.
- Broadened Chat-action discovery on profile pages and added a short profile-action probe if no Chat action can be identified.
- Outfits still load only after the profile's **Outfits** button is opened; fetched public outfits are cached in memory for the current profile only.

## Install / update in Brave

1. Extract this ZIP to a normal folder.
2. Open `brave://extensions` and enable **Developer mode**.
3. For a new install, choose **Load unpacked** and select the `RoValraLocal-Brave-v0.3.1` folder.
4. To update an existing unpacked install, copy the new files over the old extension folder (keep the same folder path), then click **Reload** on its card in `brave://extensions`.
5. Refresh Roblox tabs after reloading the extension.

Keeping the same unpacked extension folder path preserves its extension ID and locally stored settings. The old homepage preference keys are no longer used; the new `cleanHomePage` setting defaults to enabled.

## Privacy / network behavior

- No analytics, telemetry, remote configuration, or third-party data endpoints are included.
- Public outfits are requested from `avatar.roblox.com` with `credentials: omit` when the Outfits panel is opened.
- The current-avatar accessory count is requested from `avatar.roblox.com` using the logged-in Roblox session.
- Homepage filtering does not prevent Roblox from downloading its combined `omni-recommendation` response. It modifies the response exposed to page code where the hooks apply and hides recognized unwanted sections in the rendered DOM as a fallback.
- The optional region-provider feature uses extension-to-extension messaging only when a provider ID is configured; the other extension may have its own network behavior.

## Diagnostics

Homepage, run in DevTools:

```js
({
  network: window.__rvLocalFeedDiagnostics,
  domHidden: document.documentElement.dataset.rvLocalFeedDomHidden,
  domUnresolved: document.documentElement.dataset.rvLocalFeedDomUnresolved,
  domLabels: document.documentElement.dataset.rvLocalFeedDomLabels
})
```

Expected network result with cleanup enabled: `retainedTopics` should contain only Continue and Favorites. `domLabels` shows the names of the DOM sections hidden by the fallback.

Profile page, run:

```js
document.documentElement.dataset.rvLocalOutfitButton
```

Expected result: `attached`. If it still says `waiting-for-chat-action`, run this compact probe and copy the returned text (not the full DOM):

```js
(() => {
  const root = document.querySelector('#profile-container') ||
    document.querySelector('[data-testid*="profile-header"]') ||
    document.querySelector('main') || document.body;
  return document.documentElement.dataset.rvLocalOutfitProbe ||
    [...root.querySelectorAll('button,a,[role="button"],[tabindex]')]
      .filter(el => el.getClientRects().length)
      .slice(0, 12)
      .map(el => [el.tagName.toLowerCase(), (el.innerText || el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 24), el.getAttribute('aria-label') || '', el.getAttribute('title') || '', el.getAttribute('data-testid') || '', (typeof el.className === 'string' ? el.className : '').slice(0, 36)].filter(Boolean).join('|'))
      .join(' ; ') || 'NO_VISIBLE_PROFILE_ACTIONS';
})()
```

The probe returns at most 12 short lines, rather than full HTML, so it is much easier to copy and share.
