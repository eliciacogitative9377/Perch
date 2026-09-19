# Attribution

The system-monitor portion of this repository — everything at the top level
except `launcher/` — is a rename of **Stats** by Serhiy Mytrovtsiy.

- Upstream: <https://github.com/exelban/stats>
- Licence: MIT, `LICENSE` (unmodified — Copyright © 2019 Serhiy Mytrovtsiy)

MIT permits copying, modifying and renaming, on the condition that the
copyright notice above is retained. It is, and must stay that way in anything
built or shared from this repo.

## What was changed in the rename

| Change | Why |
| ------ | --- |
| Whole-word `Stats` → `Perch` in 107 text files | the product name only — identifiers like `SystemStats`, `driveStats`, `renderStats` were deliberately left alone, since they refer to statistics rather than the app |
| `eu.exelban.Stats*` → `com.sagar.perch*` bundle IDs | a fork must not claim the original's identifiers |
| `Stats/` → `Perch/`, `Stats.xcodeproj` → `Perch.xcodeproj`, scheme, entitlements, SMC helper plist | file and target names |
| `Makefile`: `BUNDLE_ID` → `com.sagar.perch` | it still read `eu.exelban.$(APP)`, which no longer matched the project settings |
| **Auto-updater neutralised** | see below |

## The auto-updater — important

Upstream, `Perch/AppDelegate.swift` constructs:

```swift
Updater(github: "exelban/stats", url: "https://api.mac-stats.com/release/latest")
```

and `updater.install()` replaces the running application with whatever it
downloads. Left pointing upstream in a rename, this fork would quietly
download the real Stats release and **overwrite itself with it**.

It is now pointed at a non-existent feed so it fails harmlessly. Repoint both
values at your own release feed before turning updates back on.

## Unlinked from upstream

Every outward link and service now reads from `Branding` in
`Kit/constants.swift`, so there is one place to repoint:

| Was | Now |
| --- | --- |
| Bug report → `github.com/exelban/stats/issues` | `Branding.issuesURL` |
| Release notes → `exelban/stats/releases/tag/…` | `Branding.releaseNotesURL(_:)` |
| GitHub Sponsors / PayPal / Ko-fi / Patreon buttons (Settings, Support, Setup) | removed; a single GitHub button, plus an optional one if `Branding.donationURL` is set |
| `.github/FUNDING.yml` (upstream's sponsor tiers) | deleted — it would have put a Sponsor button on this repo paying upstream |
| `paypal` / `ko-fi` / `patreon` image assets | deleted, now unreferenced |
| `System Perch` buttons opening `www.system-stats.com` | removed |
| Remote module's `api` / `oauth` / `broker` / `app.system-stats.com` | `Branding.remoteServiceHost`, which ships as `nil`; `SystemStats.start()` returns immediately, so nothing dials out |
| `Remote()` in the `modules` list | removed — it is a client for upstream's accounts, broker and device registry, and a fork has nothing to connect it to |
| Public IP via `api.mac-stats.com/ip` | `ifconfig.co/ip` — [echoip](https://github.com/mpolden/echoip), MIT and self-hostable |
| `eu.exelban.*` dispatch queue labels | `com.sagar.perch.*` |
| README badges, screenshots from `cdn.mac-stats.com`, upstream release/uninstall/legacy links, Homebrew `brew install stats` | removed or pointed at this repo |
| `System Stats` left in et/fi/hr/ja/ko translations | now `System Perch` |

The only outbound hosts left in a built app are `ifconfig.co/ip` (public IP,
on demand), `api.github.com/repos/<Branding.repository>` (update check, which
404s until the repo exists), `updates.invalid` (the dead updater feed), and
`google.com` as the Net module's default connectivity-check host, which is
configurable in its settings.

## Deliberately NOT removed

MIT is conditional on retaining the copyright notice, so these stay:

- `LICENSE` — unmodified, Copyright © 2019 Serhiy Mytrovtsiy
- the `Created by Serhiy Mytrovtsiy` / `Copyright © … Serhiy Mytrovtsiy` headers
  in the source files (194 files)
- this file, and the upstream URL at the top of it

Stripping those while keeping the code would put the fork in breach of the
licence it is distributed under. "Unlinking" here means not routing users,
bug reports, money or network traffic to upstream — not erasing authorship.

`Kit/lldb/libleveldb.a` is a binary and was not scanned.

## `launcher/`

Unrelated to Stats. That is the original Perch — a small native menu bar app
launcher and window switcher, written from scratch, MIT, `launcher/LICENSE`.
It builds with Command Line Tools alone; the Stats-derived app needs full
Xcode.
