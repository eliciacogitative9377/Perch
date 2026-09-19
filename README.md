<p align="center">
  <img src="Perch/Supporting%20Files/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="120" alt="Perch icon">
</p>

<h1 align="center">Perch</h1>

<p align="center">
  A native macOS menu bar app launcher, window switcher, and system monitor — all in one.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-12%2B-blue?style=flat-square&logo=apple" alt="macOS 12+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/badge/Release-1.0-purple?style=flat-square" alt="Release 1.0">
  <img src="https://img.shields.io/badge/No%20Telemetry-✓-brightgreen?style=flat-square" alt="No Telemetry">
</p>

---

## What is Perch?

**Perch** is a lightweight, native macOS app that lives entirely in your menu bar. It combines two things:

- 🚀 **App Launcher & Window Switcher** — a curated list of your apps, accessible via a Spotlight-style search panel or a single hotkey. Perch shows each app's real icon, a running indicator, and does the right thing on click — launch, focus, minimise, or restore.
- 📊 **System Monitor** — live CPU, RAM, disk, network, and temperature readings drawn directly in the menu bar, with a mini graph popup on click (styled like Stats).

No Dock clutter. No separate apps. Just one **`Apps ▾`** item in the menu bar.

---

## Features

### App Launcher
| App state | Click does |
|---|---|
| Not running | Launch it |
| Running, window behind | Bring it to front |
| Running and frontmost | Minimise it |
| Minimised or hidden | Restore + focus |
| Full screen | Shows a notice (macOS limitation) |
| Menu-bar-only app | Activate it |

- **Spotlight-style search panel** — `⌃Space` opens a floating search panel at the pointer. Type to fuzzy-filter, press Return or click to switch.
- **MRU ordering** — recently used apps float to the top automatically.
- **Trackpad gesture** — configurable multi-finger tap opens the search panel (default: two-finger double tap).
- **Per-app hotkeys** — assign `⌃1` … `⌃9` shortcuts to jump to specific apps instantly.
- **`⌃Tab` app cycle** — walks through recently used apps one step at a time (can be turned off if it conflicts with your browser/terminal).
- **`⌃\`` toggle** — minimises the frontmost app; press again to restore it.

### System Monitor
Live readings drawn as compact widgets in the menu bar itself:

| Widget | What it shows |
|---|---|
| **CPU** | usage % |
| **RAM** | usage % |
| **Disk** | read/write speed |
| **Network** | ↑↓ throughput |
| **Temperature** | CPU die temp |

Click any widget in the menu to see a scrolling chart and detailed breakdown.

### Menu Bar Indicators
The menu bar status item shows running indicators next to each configured app:

```
●  Google Chrome      running, window on screen
○  Reminders          running, but minimised/hidden
   Firefox            not running
```

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌃Space` | Open / close the search panel |
| `⌃`` ` `` ` | Minimise frontmost app (press again to restore) |
| `⌃Tab` | Cycle to the previously used app |
| `⌃1` … `⌃9` | Jump directly to a pinned app (configured per-app) |

---

## Installation

### Build from Source

Requires **Xcode** (or Xcode Command Line Tools for the launcher only).

```bash
# Clone the repo
git clone https://github.com/sagardn/Perch.git
cd Perch

# Build with Xcode
open Perch.xcodeproj
# Product → Archive → Distribute App → Copy App
```

Move `Perch.app` to your `/Applications` folder and launch it.

> **Note:** There is no Homebrew formula or pre-built download yet. `brew install stats` installs the upstream app, not this fork.

### Launcher only (no Xcode needed)

The `launcher/` subdirectory is a standalone Swift Package that needs only the Command Line Tools:

```bash
cd launcher
swift build -c release
cp .build/release/Perch /usr/local/bin/perch
```

### Uninstall

```bash
sh /Applications/Perch.app/Contents/Resources/Scripts/uninstall.sh
```

This quits Perch and removes:
- The SMC helper (`/Library/LaunchDaemons/com.sagar.perch.SMC.Helper.plist` and `/Library/PrivilegedHelperTools/com.sagar.perch.SMC.Helper`)
- `Perch.app`
- Application data (`~/Library/Application Support/Perch`, widget containers, and `com.sagar.perch` defaults)

If the app is already in the Trash, run it from the repo directly:
```bash
sh Kit/scripts/uninstall.sh
```

---

## Requirements

- **macOS 12 Monterey** or newer
- Only stable macOS releases are supported (not betas)
- **Accessibility permission** is required for window switching (Perch will prompt on first launch)

---

## Configuration

Apps are stored in a JSON config file. The easiest way to add an app is:

1. Switch to the app you want to add
2. Click **`Apps ▾`** in the menu bar
3. Click **"Add [App Name]"** — it appears automatically when you have an unlisted app in front

To assign a `⌃N` hotkey or set a custom name, edit the config file directly:

```
~/Library/Application Support/Perch/apps.json
```

```json
[
  { "name": "Chrome",   "bundleID": "com.google.Chrome",         "shortcut": "1" },
  { "name": "Terminal", "bundleID": "com.apple.Terminal",        "shortcut": "2" },
  { "name": "Slack",    "bundleID": "com.tinyspeck.slackmacgap", "shortcut": "3" }
]
```

---

## Settings

Access settings from the **`Apps ▾`** menu → **Settings**.

| Setting | Default | Description |
|---|---|---|
| Search opens at pointer | On | Panel appears under the mouse cursor |
| Trackpad gesture | On (2-finger double-tap) | Gesture to open the search panel |
| Hide on outside click | On | Dismiss the panel when you click elsewhere |
| Ctrl+Tab cycle | On | Walk through recent apps with ⌃Tab |
| System monitor | On | Sample CPU/RAM/network on a timer |
| Menu bar widgets | CPU + RAM | Which readings appear in the status item |

---

## Privacy

Perch makes **no network requests** except one optional lookup:

- **`https://ifconfig.co/ip`** — fetches your public IP, shown in the Network popup when you open it. This is the only outbound call Perch ever makes, and it only fires when you open that popup. The service runs [echoip](https://github.com/mpolden/echoip) (MIT licensed, self-hostable).

Update checks are **disabled** in this fork. No analytics, no telemetry, no crash reporting.

---

## FAQs

<details>
<summary><strong>How do I change the order of menu bar icons?</strong></summary>

macOS controls the order, not Perch. To rearrange: hold `⌘` and drag the icon to the position you want.

</details>

<details>
<summary><strong>Perch icons don't appear in the menu bar</strong></summary>

macOS 26 introduced a privacy control under **System Settings → Menu Bar**. Toggle **Perch** ON there.

</details>

<details>
<summary><strong>How do I reduce Perch's CPU or energy impact?</strong></summary>

Disable the system monitor modules you don't need. Sensors and Bluetooth are the most expensive. Disabling them can cut CPU usage by up to 50%.

</details>

<details>
<summary><strong>Desktop widgets not showing data</strong></summary>

Enable **macOS widgets** in Perch Settings. It's off by default to avoid overloading `chronod`.

</details>

<details>
<summary><strong>Sensors show incorrect CPU/GPU core count</strong></summary>

Sensor names are thermal zones, not individual cores. Apple changes SMC keys with each SoC. "CPU Efficient Core 1" means one sensor in the efficiency cluster, not a specific core.

</details>

---

## Project Structure

```
Perch/
├── Perch/              # Main app target (SwiftUI settings, setup, views)
├── Kit/                # Shared framework: widgets, types, helpers
├── Modules/            # System monitor modules: CPU, RAM, Disk, Net, GPU, Battery, Sensors…
├── launcher/           # Standalone Swift Package: menu bar launcher + window switcher
│   └── Sources/Perch/
│       ├── SearchPanel.swift     # Spotlight-style search panel
│       ├── SystemPanel.swift     # Live system stats popup
│       ├── WindowControl.swift   # Accessibility-based window management
│       ├── Gesture.swift         # Trackpad gesture recognition
│       └── Recents.swift         # MRU app ordering
├── SMC/                # Privileged helper for SMC sensor access
├── Widgets/            # macOS desktop widget extension
└── Makefile            # Build, notarise, sign, package
```

---

## Open Source, Not Open Contribution

Perch is open source under the MIT license — you are free to read it, learn from it, fork it, and build your own version.

It is **not** an open-contribution project. Unsolicited pull requests may be closed without review. If you want to change or add something, please open an issue first. Translations and language fixes are always welcome.

The best ways to support the project: report bugs, improve translations, and propose ideas through issues.

---

## License

[MIT License](LICENSE)

```
Copyright (c) 2019 Serhiy Mytrovtsiy (Stats, the work this is derived from)
Copyright (c) 2026 Sagar (Perch, modifications)
```

Perch is a fork of [Stats](https://github.com/exelban/stats). Upstream copyright notices are retained in source headers. Full attribution is in [NOTICE.md](NOTICE.md).
