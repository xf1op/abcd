RoValra Local 0.4.6

Features
- Optional compact Roblox navigation: collapses the left navigation to a 64px icon rail with an edge toggle. The compact-sidebar feature can be enabled or disabled in the extension popup.
- The sidebar expanded/collapsed state is saved locally and persists across Roblox pages and browser navigation.
- Optional sidebar button customization: independently hide or show the profile picture row, Home, Profile, Roblox Plus, Messages, Friends, Avatar, Inventory, Trade, Communities, Newsroom, Official Store, Buy Gift Cards and the Roblox Plus promotion.
- Sidebar button visibility is controlled by CSS installed at document start. The sidebar is kept invisible until saved settings are applied, preventing disabled items from flashing into view during initial loading.
- When the profile picture row is disabled, RoValra also removes its avatar image source after the row is inserted and restores it if the row is enabled again. This can cancel or avoid some avatar image loading, but browser timing means it cannot guarantee that no request ever starts.
- On desktop pages with the standard left navigation layout, the main content shifts to match the compact sidebar width and reclaims the freed space.
- Classic 3D accessory limit: up to 10 hats, hair, face, neck, shoulder, front, back, waist, ear and eye accessories.
- Optional homepage cleanup: keep Continue and Favorites while filtering Friends, Standout Games and recommendation sections.

The compact sidebar and button customization apply across pages on www.roblox.com, not just Home. The extension only modifies the left navigation and the main content's left offset when Roblox uses that layout. It does not modify the top bar or Roblox's mobile navigation. Use the Compact sidebar switch to turn the compact feature off. Use Customize sidebar buttons to enable or disable all individual button settings; the per-button controls let you choose which entries remain visible.

Not changed by the accessory limit
Heads, body parts, layered clothing and accessories, eyebrows, eyelashes, animations, emotes and all other asset types keep Roblox's native behaviour.

Install
1. Extract this ZIP into a normal folder.
2. Open brave://extensions in Brave or Chromium.
3. Enable Developer mode.
4. Choose Load unpacked and select the extracted RoValraLocal-0.4.6 folder.
5. Refresh any open Roblox tabs.

To update an existing unpacked installation, replace its files with these files and reload the extension from the browser's extensions page. Keep the same extension folder path to retain its extension ID and local settings.

The homepage cleanup keeps the Continue and Favorites sections from Roblox's combined homepage feed response. The browser still makes the combined feed request; the extension filters its response locally. The DOM fallback removes any matching unwanted sections that are still inserted by the page.

Settings are stored locally in the browser profile. The extension does not include analytics, telemetry, outfit tools, server-region tools, accessory counters or notifications.
