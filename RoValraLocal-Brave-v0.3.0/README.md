# RoValra Local 0.3.0

A lightweight Brave/Chromium extension for local Roblox page customizations.

## Changes in 0.3.0

- Homepage feed interception remains in place, with extra XHR instance-level response getter handling.
- Added a DOM fallback for the known Friends, Recommended For You, and Standout Games homepage sections. This hides rendered sections if Roblox reconstructs them from its layout/cache data.
- Added DOM diagnostics to the page root: `data-rv-local-feed-dom-hidden` and `data-rv-local-feed-dom-unresolved`.
- Replaced the large public-outfits profile block with a compact **Outfits** button inserted beside the profile's **Chat** action. The popover fetches public outfits on first open and caches that list in memory for the current profile only.
- Updated the popup copy so it does not imply that the combined Roblox feed response is no longer downloaded.

## Install in Brave

1. Extract this ZIP to a normal folder.
2. Open `brave://extensions`.
3. Enable **Developer mode**.
4. Choose **Load unpacked** and select the extracted `RoValraLocal-Brave-v0.3.0` folder.
5. Reload any open Roblox tabs.

To update an existing unpacked install while preserving its extension ID and local settings, copy the new files over the existing unpacked extension folder (keep that folder path unchanged), then click **Reload** on its card in `brave://extensions`. Loading the new folder as a separate unpacked extension may create a different extension ID and a separate settings store.

## Privacy / network behavior

- No analytics, telemetry, or remote configuration are included.
- Public outfits are requested from `avatar.roblox.com` with `credentials: omit` when the Outfits popover is opened.
- The current-avatar accessory count is requested from `avatar.roblox.com` using the logged-in Roblox session.
- Homepage filtering does not prevent Roblox from downloading its combined `omni-recommendation` response. It modifies the response exposed to page code where the hooks apply and hides known unwanted sections in the rendered DOM as a fallback.
- The optional region-provider feature uses local extension-to-extension messaging only when a provider ID is configured.

## Feed diagnostics

On the Roblox homepage, run in DevTools:

```js
({
  network: window.__rvLocalFeedDiagnostics,
  domHidden: document.documentElement.dataset.rvLocalFeedDomHidden,
  domUnresolved: document.documentElement.dataset.rvLocalFeedDomUnresolved
})
```

The response diagnostics show whether the network hooks filtered a matching response. The DOM values show how many unwanted section containers were hidden and how many matching headings could not be mapped to a safe container.

On a profile page, this value indicates whether the Chat action was found:

```js
document.documentElement.dataset.rvLocalOutfitButton
```

Expected value: `attached`. If it says `waiting-for-chat-action`, run this on the profile page and share the output so the Chat selector can be matched to the current Roblox markup:

```js
[...document.querySelectorAll('main button,main a,main [role="button"],main [data-testid]')]
  .filter(el => /chat/i.test([
    el.innerText,
    el.getAttribute('aria-label'),
    el.getAttribute('title'),
    el.getAttribute('data-testid'),
    el.className
  ].join(' ')))
  .map(el => ({
    tag: el.tagName,
    text: el.innerText?.trim(),
    aria: el.getAttribute('aria-label'),
    title: el.getAttribute('title'),
    testId: el.getAttribute('data-testid'),
    html: el.outerHTML.slice(0, 1000)
  }));
```
