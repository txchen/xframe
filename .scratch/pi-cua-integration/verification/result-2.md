# Pi CUA smoke: result 2

Status: **partly passed.**

- Connected: the CUA tool loaded and Finder access worked.
- Clicked: a CUA click opened the View menu, and fresh AX confirmed it.
- Closed: the menu closed, confirmed by fresh AX, but **Esc did not close it**. The AX Cancel action did.
- Screenshots: both were taken through the CUA screenshot API, but neither showed real content, only plain white images.

## Timeline

1. The tool `mcp__cua_repl__js` was present. `../extension-status.json` said `state: connected` and listed both tools.
2. The first call was exactly `await cua.getState();`. It listed Unity Hub, Finder, Ghostty and Xcode, with no browsers and no errors.
3. Before approval, `cua.getApp("com.apple.finder")` and then `cua.getApp("Finder")` both failed with `Computer Use was not approved to use Finder`. After the parent session said it was asking the user, I made no more retries.
4. The user approved Finder access, and the parent session sent the answer through respond_to_permission. I did not approve anything myself.
5. `let app = await cua.getApp("com.apple.finder")` succeeded. Initial AX:
   - `Window: "Desktop", App: Finder.`
   - `0 scroll area (disabled) desktop`
   - `1 menu bar`, with children 2 Finder / 3 File / 4 Edit / 5 View / 6 Go / 7 Window / 8 Help
   - focus: `9 container desktop`
6. `app.getScreenshot()` returned a 3840x2160 image (shown at 2000x1125). It was **plain white**: no icons, no wallpaper, no menu bar. This was the CUA image of Finder's "Desktop" window only. Since it shows nothing, it does not prove the desktop itself looked like that.
7. `app.click(5)` (View), then `getAXState()` gave a new tree:
   - `1 View, Secondary Actions: Cancel, Pick` → `2 menu Secondary Actions: Cancel`
   - Menu items, starting with disabled entries: as Icons / as List / as Columns / as Gallery
   - Then: Use Stacks, Sort By (submenu: None, Snap to Grid, Name, Kind, Date Last Opened, Date Added, Date Modified, Date Created, Size, Tags), Clean Up…, Hide Tab Bar…, Show View Options, Enter Full Screen and others
   - So the click really opened the View menu.
8. A screenshot with the menu open failed with: `Screenshot unavailable for /System/Library/CoreServices/Finder.app.` I did not retry.
9. `app.pressKey("Escape")`, then `getAXState({ disableDiffing: true })`: the full tree **still showed the View menu open** (`0 View ... / 1 menu ...`). **Esc did not close it.**
10. Fallback: I used the menu's own exposed AX action, `app.performSecondaryAction(1, "Cancel")`. A fresh full AX read then showed the menu closed:
    - back to `0 scroll area desktop`
    - `1 menu bar`, children 2–8 (Finder…Help)
    - focus: `9 container desktop`
11. A screenshot after closing was again plain white, 3840x2160.

## Same binding throughout

From step 5 on, every action used the same `app` binding:

- `getScreenshot`
- `click(5)`
- `getAXState`
- `pressKey`
- `performSecondaryAction`
- `getAXState({disableDiffing:true})`
- `getScreenshot`

These ran as separate tool calls. Each one worked on the existing binding without calling `getApp` again, so state carried over between calls.

## Rules kept

- No bash, osascript or CGEvent was used in place of the UI.
- No permissions were approved by me, and the permission mechanism was not changed.
- The extension was not edited.
- XFrame was not restarted.
- No games were started and no system settings were changed.
- Every action stayed inside this one Finder check: reading the screen, opening View, closing the menu.

## Open issues

- **Esc did nothing** while the menu was open. A likely cause is that a key sent to a background Finder does not reach the menu loop. Not checked further.
- **The two screenshots were plain white** and **the screenshot with the menu open failed**. As a result, **there is no image of the open menu**; that state is shown only by AX.

---

# Round 2: re-test with a normal Finder window

Status: **partly passed.**

- Screenshot: **a normal window now gives a real screenshot.** Earlier the Desktop window gave a plain white image.
- Screenshot with a menu open: **still fails.**
- Esc: **still does not close the menu**, even after raising and focusing the window.

All actions used the same `app` binding from round 1. I did not call `getApp` again.

## Steps and evidence

1. **Opened a normal window** using only CUA clicks, with no file or setting changes:
   - `app.click(3)` (File). AX showed the File menu, with `3 New Finder Window`.
   - `app.click(3)` (New Finder Window). A full AX read then showed:
     - `Window: "Recents", App: Finder.`
     - `0 standard window Recents, ID: FinderWindow, Secondary Actions: Raise`
     - sidebar, toolbar, status bar `0 items`
     - menu bar items `60`–`67`
     - focus: `37 collection icon view`
2. **Screenshot of the Recents window:** `app.getScreenshot()` returned a single image object, 132147 bytes, 2284x1454. **It shows real content:**
   - Red, yellow and green window buttons at the top left; back and forward arrows; the title "Recents".
   - Toolbar: icon / list / column / gallery buttons, a Group menu, Share, Tags, a "…" button, and a Search box.
   - Sidebar: Recents (selected), Shared.
     - Favorites: Applications, Desktop, Documents, Downloads, code, OneDrive, 3DPrint.
     - Locations: iCloud Drive, OneDrive, hibiki, AirDrop, Network, Trash.
     - Tags: Gray, Purple, Orange (the rest are cut off).
   - The main area is empty white, which matches the AX status bar `0 items`.

   **Finding:** with a normal window the screenshot shows real content that matches the AX tree. Earlier, the Finder "Desktop" window gave a plain white image. Only one comparison was made, so this is **not proven**, but it suggests the white image came from what CUA captures for the Desktop window, not from a fault in sending the image.
3. **View menu with the normal window:** `app.click(64)` worked. AX showed `1 View, Secondary Actions: Cancel, Pick` / `2 menu`. With a window present, items are now enabled: as Icons / as List / as Columns / as Gallery, Use Groups, Show Tab Bar, Show Path Bar, Show Status Bar, Enter Full Screen and so on.
4. **Screenshot with the menu open:** `app.getScreenshot({emit:false})` failed with `Screenshot unavailable for /System/Library/CoreServices/Finder.app.` This is the same as round 1, so it is **not** specific to the Desktop window. It seems to happen whenever a menu is open.
5. **Esc, first attempt:** `app.pressKey("Escape")`, then a full AX read. The **View menu was still open.**
6. Closed the menu with `performSecondaryAction(1, "Cancel")`. AX was back to the `standard window Recents` tree.
7. **Focus, then Esc again:**
   - The docs have no `activate` API. I used the AX actions that were actually exposed:
     - `performSecondaryAction(0, "Raise")` on the window
     - `app.click(37)` on the empty icon view (no change to files)
   - `getAXState()` reported no change; focus was still `37 icon view`.
   - `app.click(64)` opened View again; AX showed `1 View … / 2 menu`.
   - `pressKey("Escape")`, then a full AX read: **the menu was still open.**
8. Closed the menu with `performSecondaryAction(1, "Cancel")`. AX was back to the `standard window Recents` tree with menu bar items 60–67 and focus on 37.

## Results

| Item | Result |
|---|---|
| Real screenshot of a normal window | **Passed.** 2284x1454 image with real content, matching AX. |
| Screenshot of the Desktop window | Plain white, 3840x2160. **Not accepted.** |
| Screenshot with a menu open | **Failed** both times: `Screenshot unavailable for …/Finder.app` |
| CUA click opens View, confirmed by AX | **Passed**, in both rounds |
| Esc closes the menu | **Failed** in both rounds, including after Raise and focus. Both times AX showed the menu still open. |
| AX Cancel closes the menu | **Passed**, confirmed by AX |
| Reusing the same binding | **Passed.** One `app` variable was used across all calls from getApp onward. |

## Current UI state

The Finder "Recents" window I opened is **still open**; it was left for the parent session to compare. No menu is open. No files or settings were changed.

## Rules kept

- Only CUA was used.
- No new permission prompts appeared, and I approved nothing myself.
- No bash, osascript or CGEvent was used for UI actions.
