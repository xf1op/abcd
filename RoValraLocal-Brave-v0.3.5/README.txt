RoValra Local v0.3.5 — accessory equip fix

PATCH ZIP — apply these files over the existing RoValra Local v0.3.4 folder.
Keep the other existing files (content.js, content.css, home-feed files, popup
files) unchanged.

Files in this ZIP:
- manifest.json
- background.js
- accessory-main.js
- accessory-manager.js

Fixes:
- Captures the Avatar-page Wear click in the MAIN world at window capture phase,
  before Roblox's React click handlers and the legacy isolated-world limiter.
  The event is stopped before Roblox can also perform its category-based swap.
- Bridges the clicked asset ID into the extension's isolated world.
- Reads equipped assets from /v1/avatar, which matches the response shape the
  user verified in DevTools (`assets[].type.id`).
- Uses POST /v1/avatar/set-wearing-assets with the complete asset ID list.
- Below 10 accessories: preserves every current asset and adds the clicked one.
- At 10 or more: removes exactly ONE random currently equipped accessory, then
  adds the clicked one. It never loops to remove multiple accessories.
- Serializes equip requests and stores no accessory history or timestamps.
- No toast, popup, prompt, timer, observer, or polling is added.

After applying:
1. Replace the four files listed above in the same unpacked extension folder.
2. Open brave://extensions and Reload RoValra Local.
3. Refresh the Roblox Avatar editor.

Silent diagnostic:
document.documentElement.dataset.rvLocalAccessoryError

This ZIP is a source patch based on the public 0.3.4 GitHub folder, not a tested
live Roblox account build. Roblox can change its page selectors or API behaviour.
