# Perch

A native macOS menu bar app launcher and window switcher. Replaces the Dock.

Perch puts an **`Apps ▾`** menu in your menu bar. Each row shows the app's real
icon and a Dock-style running indicator, and clicking it does the sensible
thing for that app's current state.

```
●  Google Chrome      running, window on screen
○  Reminders          running, but minimized or hidden
   Firefox            not running
```

| App state                 | Click does          |
| ------------------------- | ------------------- |
| Not running               | launch it           |
| Running, but **behind**   | bring it to front   |
| Running and **frontmost** | minimize it         |
| **Minimized** or hidden   | restore + focus it  |
| Full screen               | shows a notice (macOS can't minimize these) |
| No window (menu-bar app)  | activate it         |

## Hotkeys

| Key        | Action                                                   |
| ---------- | -------------------------------------------------------- |
| **⌃Space** | open the menu at the mouse pointer                        |
| **⌃`**     | minimize the frontmost app — press again to bring it back |
| **⌃1**…**⌃9** | jump straight to one app, no menu (set per app in the config) |

Both are one-handed and deliberately **not** Control+letter: a global hotkey
swallows the key in every app, and in a shell `^A` is beginning-of-line, `^U`
is kill-line, and `^M` *is* Return. `Space` and `` ` `` cost nothing.

## Build

Needs only the **Command Line Tools** — no Xcode.

```bash
./build.sh            # release
./build.sh debug      # debug
open Perch.app
```

`build.sh` compiles with SwiftPM, assembles the `.app` bundle by hand, and
signs it.

### Signing — read this before you iterate

By default the bundle is **ad-hoc signed**, which has no stable identity. macOS
then keys the Accessibility grant to the binary's *hash*, and that hash changes
on every build — so **every rebuild silently revokes Accessibility**.

The symptom is confusing rather than obvious: apps still launch and still come
to the front, but nothing minimizes. Raising a window needs no permission;
minimizing one does.

To fix it permanently, create a self-signed code-signing certificate once:

1. Open **Keychain Access**
2. Menu: **Keychain Access → Certificate Assistant → Create a Certificate…**
3. Name `Perch Dev`, Identity Type **Self Signed Root**,
   Certificate Type **Code Signing**, then Create

Then build with it:

```bash
PERCH_IDENTITY="Perch Dev" ./build.sh
```

The identity is stable across rebuilds, so the Accessibility grant sticks.
Grant it once and stop thinking about it.

## First run

Perch needs **Accessibility** permission to minimize and raise other apps'
windows. On first launch it will prompt; grant it in
**System Settings → Privacy & Security → Accessibility**, then restart Perch.

Without it Perch still launches apps and shows the menu, but cannot minimize,
restore or raise anything, and the minimized `○` indicator won't work.

### If `Apps ▾` doesn't appear in the menu bar

It's almost certainly **hidden, not missing**. macOS 26 collapses menu bar
items when the bar is crowded, behind a **`«`** button. Click the `«`, then
**⌘-drag** `Apps ▾` out of the hidden group. Perch sets a stable
`autosaveName`, so the position sticks.

Confirm it exists at any time:

```bash
osascript -e 'tell application "System Events" to tell process "Perch" \
  to get {title, size} of every menu bar item of menu bar 1'
```

⌃Space works even while the item is hidden.

## The app list

Not compiled in — it's JSON, so adding an app is an edit, not a rebuild:

```
~/Library/Application Support/Perch/apps.json
```

Use **Apps ▾ → Edit App List…** to open it, then **Reload List** to apply.

```json
{ "name" : "VLC", "bundleID" : "org.videolan.vlc", "shortcut" : "0" }
```

`shortcut` is optional — a single character `0`–`9`, pressed with Control, that
jumps straight to that app using the same click behaviour (raise if behind,
minimize if frontmost, restore if minimized).

Find a bundle ID with:

```bash
osascript -e 'id of app "VLC"'
```

Bundle IDs are used rather than app names on purpose: a name breaks when the
app renames itself or when the process name differs from the app name — for
example Antigravity IDE runs as a process called `Electron`.

Apps you don't have installed are harmless; clicking shows a "not installed"
notice.

## Layout

```
Package.swift                 SwiftPM manifest
Info.plist                    bundle metadata (LSUIElement = menu-bar-only)
build.sh                      compile + assemble + ad-hoc sign
Sources/Perch/
    main.swift                entry point, .accessory activation policy
    AppDelegate.swift         status item, menu, indicators, hotkey actions
    AppEntry.swift            the app list model + JSON config
    WindowControl.swift       all Accessibility / window logic
    Hotkey.swift              global hotkeys via Carbon
    Notify.swift              small HUD, like Hammerspoon's hs.alert
    LoginItem.swift           launch at login via SMAppService
```

## Notes on things that look like bugs but aren't

**Full-screen windows cannot be minimized.** macOS refuses. Hiding the app as
a substitute was tried and deliberately rejected: `Cmd-H` tears down the
full-screen space, after which the app reports zero windows while `AXHidden`
stays `false`, and nothing can bring it back. Perch shows a notice and leaves
the window alone.

**Finder's desktop is a fake window.** Finder publishes the desktop as an
`AXScrollArea` alongside real windows, and `AXMainWindow` can point at it once
Finder is frontmost. It can't be minimized, so `WindowControl` ignores
anything whose role isn't `AXWindow`.

**A minimized window has no `AXMainWindow`.** That's why `targetWindow` falls
back to the app's window list and prefers a minimized one — that's the window
a click wants to restore.

**Menu-bar-only apps** (Dropbox, Tailscale, OpenVPN Connect) have no window,
so a click can only activate them.

**Launchpad was removed in macOS 26.** The default list points at its
replacement, `/System/Applications/Apps.app` (`com.apple.apps.launcher`).

## Relationship to the Hammerspoon version

Perch is a native rewrite of a Hammerspoon `init.lua` that did the same job
(kept at `~/Downloads/hammerspoon-apps-menu/`). Behaviour is deliberately
identical; the differences are that Perch is a standalone `.app` with no
Hammerspoon dependency, and the app list is JSON rather than Lua.

**Run one or the other, not both** — they compete for the same hotkeys and
you'd get two `Apps ▾` items in the menu bar.

## Why this isn't a fork of Stats

[Stats](https://github.com/exelban/stats) was considered as a starting point.
It is MIT licensed, so forking and renaming it is allowed provided the
copyright notice is kept — but it was the wrong base:

- Stats is a **system monitor** (CPU, GPU, disk, battery, sensors), not a
  launcher. Renaming it would give you a system monitor called Perch, and the
  launcher would still need writing.
- It is **43,527 lines of Swift across 119 files**, built with `xcodebuild`
  plus archive and notarize steps, so it needs **full Xcode** (~17 GB).
  Perch builds with Command Line Tools in about 30 seconds.
- Its own README says it is "open source, but not open contribution".

A clone is kept at `../stats-src` for reference. Its launch-at-login uses a
separate helper bundle, the pre-Ventura approach; Perch uses `SMAppService`
instead, which needs no helper on macOS 13+.

## Licence

MIT.
