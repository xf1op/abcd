RoValra Local v0.3.4 — accessory manager replacement files

Copy these three files into your existing RoValra Local v0.3.3 extension folder,
replacing background.js and manifest.json and adding accessory-manager.js.
Keep the existing content.js, content.css, popup files, and home-feed files.

Then open brave://extensions and press Reload on RoValra Local. Refresh the
Roblox Avatar page afterwards.

Behaviour:
- Under 10 equipped accessories: keep every existing asset and add the clicked one.
- At 10/10: replace exactly one randomly selected currently equipped accessory.
- Selection is random per full-cap click. No equip history, timestamps, or per-item
  storage is used.
- A complete avatar asset list is submitted through Roblox's v4 avatar update API,
  preserving layered-accessory metadata.
- Accessory clicks are handled before the old click limiter and Roblox's native
  single-item wear handler. No bottom toast or confirmation prompt is shown.

Important limitation:
The manager identifies the clicked item ID from the Roblox item card. If Roblox
changes its page markup so the ID cannot be read, the click is safely stopped and
a silent diagnostic is written to:
document.documentElement.dataset.rvLocalAccessoryError

No Roblox session token or cookie is read or stored by this extension code.
