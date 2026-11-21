RoValra Local 0.4.10

Features
- Profile outfit gallery: adds an Outfits control immediately to the left of the profile avatar 3D view toggle, reusing the detected Roblox 3D button class and native state-layer markup. Opens a responsive 5–8-column gallery of outfit thumbnails and names. Selecting a card shows its outfit ID, which can be copied.
- Outfits are requested only after the gallery is opened. Outfit lists use Roblox Avatar API v2 and preview images use the Roblox Thumbnails API. The first request loads up to 100 editable avatar outfits (`itemsPerPage=100&isEditable=true&outfitType=Avatar`); further results can be loaded in another page. Preview images are requested in batches of up to 100 and lazy-loaded.
- The profile outfit gallery can be enabled or disabled from the extension popup.
- Optional compact Roblox navigation: collapses the left navigation to a 64px icon rail with an edge toggle. The compact-sidebar feature can be enabled or disabled in the extension popup.
- The sidebar expanded/collapsed state is saved locally and persists across Roblox pages and browser navigation.
- Optional sidebar button customization: independently hide or show the profile picture row, Home, Profile, Roblox Plus, Messages, Friends, Avatar, Inventory, Trade, Communities, Newsroom, Official Store, Buy Gift Cards and the Roblox Plus promotion.
- Sidebar buttons disabled in Settings are physically removed from the navigation DOM before the sidebar is revealed. Their original nodes are retained and restored when re-enabled; a lightweight observer watches only the navigation list for Roblox-recreated entries.
- When the profile picture row is disabled, RoValra removes its avatar image source before detaching the row and restores it when re-enabled. The browser may already have started a request by the time Roblox inserts the row.
- On desktop pages with the standard left navigation layout, the main content shifts to match the compact sidebar width and reclaims the freed space.
- The compact sidebar clips horizontal overflow in its scroll container, removing the horizontal scrollbar while keeping normal vertical scrolling available.
- Classic 3D accessory limit: up to 10 hats, hair, face, neck, shoulder, front, back, waist, ear and eye accessories.
- Optional homepage cleanup: keep Continue and Favorites while filtering Friends, Standout Games and recommendation sections.

The compact sidebar and button customization apply across pages on www.roblox.com, not just Home. The profile outfit gallery appears on user profile pages when Roblox renders its 3D avatar control. The extension only modifies the left navigation and the main content's left offset when Roblox uses that layout. It does not modify the top bar or Roblox's mobile navigation. Use the Compact sidebar switch to turn the compact feature off. Use Customize sidebar buttons to enable or disable all individual button settings; the per-button controls let you choose which entries remain visible.

Not changed by the accessory limit
Heads, body parts, layered clothing and accessories, eyebrows, eyelashes, animations, emotes and all other asset types keep Roblox's native behaviour.

Install
1. Extract this ZIP into a normal folder.
2. Open brave://extensions in Brave or Chromium.
3. Enable Developer mode.
4. Choose Load unpacked and select the extracted RoValraLocal-0.4.10 folder.
5. Refresh any open Roblox tabs.

To update an existing unpacked installation, replace its files with these files and reload the extension from the browser's extensions page. Keep the same extension folder path to retain its extension ID and local settings.

The homepage cleanup keeps the Continue and Favorites sections from Roblox's combined homepage feed response. The browser still makes the combined feed request; the extension filters its response locally. The DOM fallback removes any matching unwanted sections that are still inserted by the page.

Outfit visibility follows the data Roblox makes available through its public API; private or restricted outfit lists are not bypassed. Outfit API requests are made without sending Roblox account cookies. Settings are stored locally in the browser profile. The extension does not include analytics, telemetry, outfit tools, server-region tools, accessory counters or notifications.
