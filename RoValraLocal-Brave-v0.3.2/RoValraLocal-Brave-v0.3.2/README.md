# RoValra Local 0.3.2

A lightweight, local-first Brave/Chromium extension for Roblox page customizations.

## Changes in 0.3.2

- Fixed the XHR/Fetch text-response path: the old implementation mutated a parsed object but accidentally returned the original JSON string. Text responses are now serialized with the removed sorts, so Roblox receives the cleaned feed instead of rendering the original sections.
- Feed cleanup now removes unwanted section containers from the DOM instead of applying `display: none`. Media URLs (`src`, `srcset`, `poster`, and inline background images) are cleared before the section is detached, helping cancel pending image/media loads.
- The DOM pruner starts at `document_start` and watches the document before Roblox finishes building the home feed.
- The combined feed response now drops metadata buckets not referenced by the retained Continue/Favorites items, drops non-game string-ID metadata when only Game content remains, and prunes explicitly identified excluded topic nodes from `globalLayoutData` and `sdui`.
- Added diagnostics for removed DOM sections, cleared media sources, removed metadata buckets, and pruned layout nodes.

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
3. For a new install, choose **Load unpacked** and select the `RoValraLocal-Brave-v0.3.2` folder.
4. To update an existing unpacked install, copy the new files over the old extension folder (keep the same folder path), then click **Reload** on its card in `brave://extensions`.
5. Refresh Roblox tabs after reloading the extension.

Keeping the same unpacked extension folder path preserves its extension ID and locally stored settings. The old homepage preference keys are no longer used; the new `cleanHomePage` setting defaults to enabled.

## Privacy / network behavior

- No analytics, telemetry, remote configuration, or third-party data endpoints are included.
- Public outfits are requested from `avatar.roblox.com` with `credentials: omit` when the Outfits panel is opened.
- The current-avatar accessory count is requested from `avatar.roblox.com` using the logged-in Roblox session.
- Homepage filtering cannot skip Roblox’s combined `omni-recommendation` request because Continue and Favorites are returned in that same response. It removes unwanted sorts and their unused metadata before page code receives the response, then physically removes any recognized unwanted section that Roblox still inserts. Media source attributes are cleared before removal to help cancel pending loads. Images belonging to the retained Continue/Favorites cards, Roblox navigation, or other page features still load normally; completed requests cannot be undone.
- The optional region-provider feature uses extension-to-extension messaging only when a provider ID is configured; the other extension may have its own network behavior.

## Diagnostics

Homepage, run in DevTools:

```js
({
  network: window.__rvLocalFeedDiagnostics,
  domRemoved: document.documentElement.dataset.rvLocalFeedDomRemoved,
  mediaCleared: document.documentElement.dataset.rvLocalFeedMediaCleared,
  domUnresolved: document.documentElement.dataset.rvLocalFeedDomUnresolved,
  domLabels: document.documentElement.dataset.rvLocalFeedDomLabels
})
```

Expected network result with cleanup enabled: `retainedTopics` should contain only Continue and Favorites. If the XHR text hook is used, `textResponsesRewritten` should increase. `domLabels` shows the names of sections physically removed by the fallback; `mediaCleared` counts media source attributes cleared before removal. Turning cleanup off after sections have been removed requires a page refresh to restore Roblox’s original sections.

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
