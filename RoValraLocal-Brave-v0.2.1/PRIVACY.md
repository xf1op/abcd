# Privacy statement

RoValra Local v0.2.1 contains no analytics or telemetry implementation. It has no developer-controlled backend. Settings and recent-server selections are stored locally through the browser extension storage API.

The home-feed filter hooks the Roblox page response locally and removes unused sections/metadata from the JavaScript object before Roblox renders it. It does not create or redirect a request. The original combined response is still delivered by Roblox to the browser and parsed once; this filter does not reduce transferred bytes.

Network requests added by this extension:

- `avatar.roblox.com/v2/avatar/users/{userId}/outfits` — requested only when the user presses **Load** on a Roblox profile page; credentials are omitted.
- `avatar.roblox.com/v4/avatar` — requested on the user's own Avatar page when the accessory counter is enabled; the request includes Roblox browser credentials so Roblox can return the current authenticated avatar.

No IP address is collected by extension code or sent to a separate analytics provider. As with any direct connection to a website, Roblox receives ordinary network connection information, including the connecting IP address, when these Roblox endpoints are contacted.

If a region-provider extension is configured, RoValra Local sends it only the Place ID and server ID through local extension messaging. That other extension's privacy practices are outside this project's control.
