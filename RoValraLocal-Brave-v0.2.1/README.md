# RoValra Local (Brave / Chromium) — v0.2.1

A small, local-first Roblox browser extension starter. This build is intentionally a partial test build, not a complete RoValra replacement.

## Privacy model

- All extension settings and recent-server history are stored in `chrome.storage.local` on this browser profile.
- There is no analytics, telemetry, account system, crash reporting, or RoValra-owned server.
- There are no requests to external analytics, geolocation, CDN, or other third-party services.
- The only direct network requests added by this build are to `avatar.roblox.com` for public outfit listings and the authenticated user's current avatar accessory list.
- Public outfit requests omit credentials. The current-avatar request includes Roblox session credentials and is sent only to `avatar.roblox.com` to read the current user's own avatar.
- Server-region lookups use an optional local extension-to-extension message bridge. No network-based region lookup is built in.
- The extension does not read, extract, store, or transmit the Roblox `.ROBLOSECURITY` cookie.

## Included in this test build

1. Home-feed filtering: at `document_start`, a small main-world hook filters the `/discovery-api/omni-recommendation` payload before Roblox page code consumes it, covering `Response.json()`, `Response.text()`, and XHR response getters. By default it keeps only Continue and Favorites (topic IDs `100000003` and `100000001`), removes duplicate Recommended For You rows and Standout Games, and prunes unused `contentMetadata.Game` entries.
2. Sidebar collapse and hide toggles. Roblox DOM selectors change over time, so these are best-effort and may need tuning against your current layout.
3. Avatar accessory counter using Roblox's current `/v4/avatar` API.
4. An experimental accessory guard. It blocks a Wear/Add click only if the page markup exposes the clicked item's accessory type and the current avatar already has 10 or more supported accessory types. If type metadata is missing, the guard deliberately fails open rather than blocking unrelated clothing.
5. Public profile outfits button using Roblox's current `/v2/avatar/users/{userId}/outfits` endpoint.
6. Recent server selections, storing at most five unique server IDs per Place ID in local storage.
7. Optional region-provider bridge for another installed extension. It is inactive unless you enter that extension's ID.

## Known limitations

- Important home-feed limitation: the request body you inspected has no topic include/exclude field. The feed is one combined response, so this filter cannot stop Roblox from generating or transmitting the unwanted sections. The browser still downloads and parses the response once; the hook then removes unwanted sections and unused game metadata before Roblox application code receives the JSON object. This reduces retained data and page rendering work, but not network bandwidth or the browser parser’s initial cost. Blocking the entire endpoint would also remove Continue and Favorites. If Roblox changes the response shape or uses a transport the hook cannot observe, the filter fails open and leaves the response unchanged. A page-console diagnostic is exposed immediately as `window.__rvLocalFeedDiagnostics`.
- Recent servers are recorded when you click a recognizable server row. The browser page cannot guarantee that the Roblox client successfully joined that server, so the label is `selected`, not `joined`.
- Roblox changes page markup frequently. The sidebar and accessory click guard need testing on your exact Brave/Roblox layout. The accessory guard is intentionally fail-open when asset type metadata cannot be identified.
- The region bridge is a contract, not a built-in integration with a named extension yet. See `REGION_PROVIDER.md`.
- The profile outfit request returns the first 25 public outfits only. Private outfits are not available through this public endpoint.

## Install in Brave

1. Extract `RoValraLocal-Brave.zip` to a normal folder.
2. Open `brave://extensions`.
3. Enable **Developer mode**.
4. Click **Load unpacked**.
5. Select the extracted folder containing `manifest.json`.
6. Open `www.roblox.com` and test the settings from the extension toolbar popup.

When files are changed, return to `brave://extensions` and click the extension's reload icon, then refresh the Roblox tab.

## Home-feed implementation notes

- The main-world hook is injected at `document_start`; a separate isolated-world bridge reads only the three home-filter settings from `chrome.storage.local`. The page-console diagnostic `window.__rvLocalFeedDiagnostics` exists as soon as the hook installs and tracks which response hooks are available and whether the target endpoint was observed.
- The hook does not make requests, add host permissions, or send data anywhere. It only modifies the in-memory response object or JSON text for the exact Roblox omni-recommendation endpoint.
- It keeps the response metadata map entries whose IDs are referenced by retained Game recommendations. This assumes the current `contentMetadata.Game` map is keyed by game/universe ID; Roblox may change this undocumented response format.

## Permissions

- `storage`: only used for local settings and recent-server history.
- Host permission `https://avatar.roblox.com/*`: needed for the public profile outfit endpoint and authenticated current-avatar read. No other website host permission is requested.

No `tabs`, `cookies`, `history`, `webRequest`, `debugger`, `scripting`, or `unlimitedStorage` permission is requested.
