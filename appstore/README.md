# Publishing Window Grids on the Mac App Store

Everything that can be prepared in the repository is here. The steps marked **you** need your Apple Developer account and cannot be scripted from this repo.

## Status

| Item | State |
| --- | --- |
| Sandboxed universal build (`scripts/build-appstore.sh`) | ready; `--local` builds and runs |
| Entitlements (`Resources/AppStore.entitlements`) | ready |
| App icon with 1024 px size (`Resources/AppIcon.icns`) | ready |
| Screenshots, 2880 × 1800 (`appstore/screenshots/`) | ready |
| Marketing / support site | https://r2rka1.github.io/mac-window-grids/ |
| Privacy policy | https://r2rka1.github.io/mac-window-grids/privacy.html |
| Listing text | below |
| Apple Developer Program membership, certificates, app record | **you** |

## Steps

1. **You:** join the [Apple Developer Program](https://developer.apple.com/programs/) (paid). The "Apple Development" certificate currently in the keychain cannot sign App Store builds.
2. **You:** at developer.apple.com → Certificates, IDs & Profiles:
   - register the App ID `io.github.r2rka1.WindowGrids` (or your own; pass it as `BUNDLE_ID`), no extra capabilities;
   - create an **Apple Distribution** and a **Mac Installer Distribution** certificate and install both in the keychain;
   - create a **Mac App Store Connect** provisioning profile for the App ID and download it.
3. **You:** in [App Store Connect](https://appstoreconnect.apple.com) create a new macOS app with that bundle ID. If the name is taken, pick a variant; the display name is one line in `Resources/Info.plist`.
4. Build and sign:
   ```sh
   PROFILE=~/Downloads/WindowGrids.provisionprofile VERSION=1.0 BUILD=1 ./scripts/build-appstore.sh
   ```
   This writes `build/appstore/WindowGrids.pkg`.
5. **You:** upload the package with the Transporter app (or `xcrun altool`, the script prints the command).
6. **You:** fill in the listing from the text below, upload `appstore/screenshots/*.png`, answer the privacy questionnaire with **Data Not Collected**, set the price to Free, and submit for review.

Try the sandboxed build on this Mac first: `./scripts/build-appstore.sh --local && open build/appstore/WindowGrids.app`.

## Listing

- **Name:** Window Grids
- **Subtitle:** Saved window layouts, one hotkey
- **Category:** Productivity
- **Price:** Free
- **Age rating:** 4+
- **Copyright:** 2026 Arthur Artsabliuk
- **Support URL:** https://github.com/r2rka1/mac-window-grids/issues
- **Marketing URL:** https://r2rka1.github.io/mac-window-grids/
- **Privacy Policy URL:** https://r2rka1.github.io/mac-window-grids/privacy.html
- **Keywords:** window manager,tiling,snap,grid,layout,split screen,resize,arrange,workspace,menu bar

**Promotional text**

Build a grid, drop your apps into its cells, and switch between whole window arrangements with one keystroke.

**Description**

Window Grids arranges your app windows on a grid, remembers which app goes in which cell, and switches between saved arrangements with a hotkey.

• Flexible grids: every column has its own width and its own number of rows. One half-width column next to three rows, a wide main area with a narrow stack, or a plain 3 × 2.
• Drag apps into cells: the editor lists your running apps. Drop one onto a cell to place it there.
• Shift-drag any window: hold Shift while dragging a window and the grid appears. Drop on a cell and the window snaps to it. Add Control to stretch it over several cells.
• Saved layouts: make one for coding, one for writing, one for calls. Each remembers its grid and its apps.
• Instant switching: Control-Option-1 to 9, or the menu bar menu. Every app moves to its cell; apps that are not running are launched.
• Capture: snap everything on screen to the nearest cells and store it as a layout.
• Multiple displays supported.

Window Grids needs Accessibility access to move other apps' windows; macOS asks for it on first launch. It makes no network requests and collects nothing.

**Screenshots**

1. `1.png`: layout editor
2. `2.png`: grid overlay while dragging
3. `3.png`: layouts and hotkeys (dark)

Regenerate them with `WindowGrids --render-store appstore/screenshots` (example data only).

## App privacy

Data Not Collected. The app makes no network requests. It uses the Accessibility API only to position windows, and stores layouts in its own container.

## Notes for App Review

- The app lives in the menu bar (octopus icon, no Dock icon). Choose "Edit Layouts…" to open the editor.
- It needs Accessibility access (System Settings → Privacy & Security → Accessibility) to move and resize other apps' windows. This is the app's core function; the Accessibility API is used only to read and set window position and size and to raise windows.
- To test: grant access, open two apps, hold Shift while dragging a window, and drop it on a cell. Or press "Apply" in the editor.
- No account, no network access, no in-app purchases.

## Not yet verified

Moving windows through the Accessibility API from inside the sandbox could not be exercised in the environment this was prepared in. Other sandboxed window managers on the Mac App Store work this way, but run the `--local` build, grant it Accessibility access, and check Shift-drag and Apply before submitting. In the sandbox, layouts are stored in the app's container, so the App Store edition starts with the default layouts.
