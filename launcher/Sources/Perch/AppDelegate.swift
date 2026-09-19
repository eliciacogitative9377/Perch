import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var entries: [AppEntry] = []

    /// What the minimize hotkey put away, so the same key can bring it back.
    private var stashed: [String] = []

    private var searchPanel: SearchPanel?
    private var menuHotkey: Hotkey?
    private var toggleHotkey: Hotkey?
    private var cycleHotkey: Hotkey?
    private var warmTimer: Timer?
    /// Ctrl+<digit> straight to one app. Held so they stay registered.
    private var appHotkeys: [Hotkey] = []
    private var appsWindow: AppsWindow?
    /// The widgets drawn into the menu bar, when any are switched on.
    private var menuBarView: MenuBarView?
    /// The system block's hosted view, kept between menu rebuilds.
    private var systemPanel: SystemPanelView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        entries = Config.load()
        Recents.shared.start()

        Gesture.shared.onTap = { [weak self] in self?.searchPanel?.toggle() }
        if Prefs.gestureEnabled {
            Gesture.shared.start(fingers: Prefs.gestureFingers, taps: Prefs.gestureTaps)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Apps ▾"
        // A stable autosave name lets macOS remember where the user drags it,
        // which matters because macOS 26 hides menu bar items when crowded.
        statusItem.autosaveName = "PerchStatusItem"

        menu.delegate = self
        statusItem.menu = menu

        searchPanel = SearchPanel(source: { [weak self] in self?.entries ?? [] },
                                  onPick: { entry in WindowControl.toggle(entry) },
                                  onSetListed: { [weak self] changed, listed in
                                      self?.setListed(changed, listed)
                                  },
                                  isMarked: { [weak self] bundleID in
                                      self?.entries.first { $0.bundleID == bundleID }?.pinned ?? false
                                  },
                                  onSetMarked: { [weak self] entry, marked in
                                      self?.setMarked(entry, marked)
                                  })

        // One key: Ctrl+Space opens the search.  Where it appears is a
        // setting -- at the pointer by default, like the old menu did.
        menuHotkey = Hotkey(keyCode: Hotkey.Key.space, modifiers: .control) { [weak self] in
            self?.searchPanel?.toggle()
        }
        // Ctrl+Tab walks back through recently used apps, one press per step.
        // Note this takes Ctrl+Tab away from every app that uses it for tab
        // switching -- Chrome, Safari, terminals -- because a global hotkey
        // consumes the key. Turn it off in the menu if that bites.
        // Keep the window-state cache warm in the background so opening the
        // search panel never pays the full Accessibility sweep.
        warmTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            WindowControl.warmStaleStates()
        }
        warmTimer?.tolerance = 0.5

        if Prefs.cycleHotkeyEnabled {
            let cycle: () -> Void = { [weak self] in
                Recents.shared.cycleToNext(among: self?.markedBundleIDs)
            }
            cycleHotkey = Hotkey(keyCode: Hotkey.Key.tab, modifiers: .control, action: cycle)

            // ⌃Tab belongs to whichever app registered it first -- browsers and
            // terminals want it too -- and the loser is told nothing. Fall back
            // to ⌥Tab and say so, rather than a key that quietly does nothing.
            if cycleHotkey == nil {
                cycleHotkey = Hotkey(keyCode: Hotkey.Key.tab, modifiers: .option, action: cycle)
                if cycleHotkey != nil {
                    NSLog("Perch: ⌃Tab was already registered; using ⌥Tab for the app cycle")
                    Notify.show("⌃Tab was taken — using ⌥Tab to cycle apps",
                                symbol: "keyboard", for: 4)
                } else {
                    Notify.show("⌃Tab is taken by another app", symbol: "keyboard", for: 4)
                }
            }
        }

        toggleHotkey = Hotkey(keyCode: Hotkey.Key.grave, modifiers: .control) { [weak self] in
            self?.toggleFrontmost()
        }
        registerAppHotkeys()

        // One place that fans a sample out to whatever is on screen, rather
        // than each view reaching for the timer.
        Monitor.shared.onSample = { [weak self] in
            guard let self else { return }
            self.menuBarView?.cells = self.menuBarCells()
            self.resizeStatusItem()
            if let panel = self.systemPanel, panel.window != nil {
                panel.refresh(full: false)
            }
        }
        applyMenuBar()              // needs statusItem, so not before this point
        syncMonitor()

        if !WindowControl.isTrusted {
            WindowControl.requestAccessibility()
            Notify.show("Perch needs Accessibility to move windows", symbol: "hand.raised.fill", for: 3)
        }
    }

    /// One Ctrl+<key> per app that asked for one in the config.
    private func registerAppHotkeys() {
        appHotkeys.removeAll()
        for entry in entries {
            guard let shortcut = entry.shortcut,
                  let code = Hotkey.Key.code(for: shortcut) else { continue }
            if let hotkey = Hotkey(keyCode: code, modifiers: .control, action: {
                WindowControl.toggle(entry)
            }) {
                appHotkeys.append(hotkey)
            }
        }
    }

    // MARK: - Menu

    /// Rebuilt every time it opens, so the indicators are current without an
    /// application watcher running in the background.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        addSystemSection(to: menu)

        // With the app rows gone, this is the only way to reach an app from
        // the menu itself -- the hotkey and the gesture are not discoverable
        // from here, and clicking the status item should not be a dead end.
        let search = NSMenuItem(title: "Search Apps…",
                                action: #selector(openSearch), keyEquivalent: " ")
        search.target = self
        search.keyEquivalentModifierMask = .control
        menu.addItem(search)
        menu.addItem(.separator())

        // One click to add whatever you are in, instead of hand-editing JSON
        // and hunting for a bundle identifier.
        if let front = NSWorkspace.shared.frontmostApplication,
           let bundleID = front.bundleIdentifier,
           !entries.contains(where: { $0.bundleID == bundleID }),
           bundleID != Bundle.main.bundleIdentifier {
            let add = NSMenuItem(title: "Add \(front.localizedName ?? bundleID) to My Apps",
                                 action: #selector(addFrontmost), keyEquivalent: "")
            add.target = self
            menu.addItem(add)
        }

        let addApp = NSMenuItem(title: "Add App…",
                                action: #selector(browseForApps), keyEquivalent: "")
        addApp.target = self
        menu.addItem(addApp)

        let edit = NSMenuItem(title: "Edit Apps…",
                              action: #selector(editList), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)

        let editJSON = NSMenuItem(title: "Edit apps.json…",
                                  action: #selector(editListAsJSON), keyEquivalent: "")
        editJSON.target = self
        editJSON.isAlternate = true
        editJSON.keyEquivalentModifierMask = .option
        menu.addItem(editJSON)

        let reload = NSMenuItem(title: "Reload List",
                                action: #selector(reloadList), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)

        let atPointer = NSMenuItem(title: "Open Search at Pointer",
                                   action: #selector(toggleOpenAtPointer), keyEquivalent: "")
        atPointer.target = self
        atPointer.state = Prefs.openAtPointer ? .on : .off
        menu.addItem(atPointer)

        if Gesture.shared.isAvailable {
            let gesture = NSMenuItem(title: "Trackpad Gesture", action: nil, keyEquivalent: "")
            gesture.submenu = gestureSubmenu()
            menu.addItem(gesture)
        }

        let monitorItem = NSMenuItem(title: "System Monitor",
                                     action: #selector(toggleMonitor), keyEquivalent: "")
        monitorItem.target = self
        monitorItem.state = Prefs.systemMonitor ? .on : .off
        menu.addItem(monitorItem)

        let menuBar = NSMenuItem(title: "Show in Menu Bar", action: nil, keyEquivalent: "")
        menuBar.submenu = menuBarSubmenu()
        menu.addItem(menuBar)

        let autoHide = NSMenuItem(title: "Hide Search on Outside Click",
                                  action: #selector(toggleHideOnOutsideClick), keyEquivalent: "")
        autoHide.target = self
        autoHide.state = Prefs.hideOnOutsideClick ? .on : .off
        menu.addItem(autoHide)

        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        if !WindowControl.isTrusted {
            let warn = NSMenuItem(title: "⚠︎ Grant Accessibility…",
                                  action: #selector(openAccessibility), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Perch",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// CPU / memory / network / disk / battery / temperature as one hosted
    /// view, so the columns line up and the charts are a real size. The view
    /// outlives the rebuild -- it holds the chart state and is cheap to keep.
    private func addSystemSection(to menu: NSMenu) {
        guard Prefs.systemMonitor else { return }

        let panel = systemPanel ?? {
            let view = SystemPanelView()
            systemPanel = view
            return view
        }()
        panel.refresh(full: true)

        let item = NSMenuItem()
        item.view = panel
        menu.addItem(item)

        // The panel cannot carry a hover submenu of its own -- a hosted view
        // gets the mouse, not the menu -- so the connection detail hangs off
        // its own row underneath.
        let details = NSMenuItem(title: "Connection Details", action: nil, keyEquivalent: "")
        details.submenu = networkSubmenu()
        menu.addItem(details)

        menu.addItem(.separator())
    }

    /// Connection detail, the way Stats shows it when you open its network
    /// popup: interface, addresses, Wi-Fi radio, DNS, session totals.
    private func networkSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let info = NetworkInfo.current()
        let monitor = Monitor.shared

        func line(_ text: String) {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.attributedTitle = NSAttributedString(
                string: text,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)])
            submenu.addItem(item)
        }

        line(String(format: "Down   %@", SystemStats.rate(monitor.latest.rx)))
        line(String(format: "Up     %@", SystemStats.rate(monitor.latest.tx)))
        submenu.addItem(.separator())
        line("Session  ↓\(SystemStats.bytes(monitor.sessionRx))  ↑\(SystemStats.bytes(monitor.sessionTx))")
        submenu.addItem(.separator())

        if let interface = info.primaryInterface { line("Interface   \(interface)") }
        if let ip = info.localIP { line("Local IP    \(ip)") }
        if let router = info.router { line("Router      \(router)") }
        if !info.dns.isEmpty { line("DNS         \(info.dns.joined(separator: ", "))") }

        if info.wifiInterface != nil {
            submenu.addItem(.separator())
            if let ssid = info.ssid {
                line("Wi-Fi       \(ssid)")
            } else if info.ssidBlocked {
                line("Wi-Fi       (name needs Location permission)")
            }
            if let rssi = info.rssi {
                line("Signal      \(rssi) dBm  \(NetworkInfo.signalQuality(rssi))")
            }
            if let rate = info.txRate { line(String(format: "Tx rate     %.0f Mbps", rate)) }
            if let channel = info.channel { line("Channel     \(channel)") }
            if let mac = info.macAddress { line("MAC         \(mac)") }
        }

        submenu.addItem(.separator())
        let publicItem = NSMenuItem(
            title: NetworkInfo.publicIP.map { "Public IP   \($0)" } ?? "Look up public IP…",
            action: #selector(lookUpPublicIP), keyEquivalent: "")
        publicItem.target = self
        submenu.addItem(publicItem)

        return submenu
    }

    @objc private func lookUpPublicIP() {
        NetworkInfo.lookUpPublicIP { address in
            Notify.show(address.map { "Public IP: \($0)" } ?? "Could not reach the lookup service",
                        for: 4)
        }
    }

    @objc private func openSearch() {
        searchPanel?.show()
    }

    /// The apps marked for Ctrl+Tab, or nil when none are. Marking is the
    /// switch: mark a few apps and Ctrl+Tab walks only those; mark nothing and
    /// it falls back to recents, so the key never does nothing.
    private var markedBundleIDs: Set<String>? {
        let marked = Set(entries.filter { $0.pinned }.map { $0.bundleID })
        return marked.isEmpty ? nil : marked
    }

    private func setMarked(_ entry: AppEntry, _ marked: Bool) {
        guard let index = entries.firstIndex(where: { $0.bundleID == entry.bundleID }) else {
            var added = entry
            added.pinned = marked
            entries.append(added)
            Config.save(entries)
            Notify.show(marked ? "Added and marked \(entry.name)" : "Added \(entry.name)",
                        symbol: "plus.circle.fill")
            return
        }
        entries[index].pinned = marked
        Config.save(entries)
        Notify.show(marked ? "\(entry.name) joins ⌃Tab" : "\(entry.name) left ⌃Tab",
                    symbol: marked ? "arrow.left.arrow.right" : "minus.circle")
    }

    @objc private func addFrontmost() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier else { return }
        setListed([AppEntry(name: front.localizedName ?? bundleID, bundleID: bundleID)], true)
    }

    /// Add or drop apps from the configured list, for the search panel's
    /// options menu, the file picker, and the "Add <app>" menu row. Saves and
    /// re-registers the hotkeys, so a removed app stops answering its
    /// Ctrl+digit. Takes a list because the picker allows several at once, and
    /// six HUDs in a row is not a report.
    private func setListed(_ changed: [AppEntry], _ listed: Bool) {
        var touched: [String] = []
        for entry in changed {
            let known = entries.contains { $0.bundleID == entry.bundleID }
            if listed {
                guard !known else { continue }
                entries.append(entry)
            } else {
                guard known else { continue }
                entries.removeAll { $0.bundleID == entry.bundleID }
            }
            touched.append(entry.name)
        }
        guard !touched.isEmpty else { return }

        Config.save(entries)
        registerAppHotkeys()
        let what = touched.count == 1 ? touched[0] : "\(touched.count) apps"
        Notify.show(listed ? "Added \(what)" : "Removed \(what)",
                    symbol: listed ? "plus.circle.fill" : "minus.circle.fill")
    }

    /// Reachable from the menu as well as the search panel, for an app that
    /// has never been opened and so appears in neither.
    @objc private func browseForApps() {
        AppChooser.run { [weak self] added in self?.setListed(added, true) }
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard entries.indices.contains(sender.tag) else { return }
        WindowControl.toggle(entries[sender.tag])
    }

    private func popUpMenuAtPointer() {
        // popUp(in: nil) takes screen coordinates, which is what
        // NSEvent.mouseLocation already gives us.
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: - Hotkey actions

    /// One key for both directions: after minimizing, the app is no longer
    /// frontmost, so pressing it again can only mean "bring back what I just
    /// put away".
    private func toggleFrontmost() {
        if let last = stashed.popLast() {
            if !WindowControl.restore(last) { Notify.show("Nothing to restore", symbol: "arrow.uturn.backward") }
            return
        }
        if let bundleID = WindowControl.minimizeFrontmost() {
            stashed.append(bundleID)
        }
    }

    // MARK: - List management

    @objc private func editList() {
        let window = AppsWindow(entries: entries) { [weak self] updated in
            guard let self else { return }
            self.entries = updated
            self.registerAppHotkeys()
        }
        appsWindow = window
        window.present()
    }

    @objc private func editListAsJSON() {
        Config.save(entries)
        NSWorkspace.shared.open(Config.fileURL)
    }

    @objc private func reloadList() {
        entries = Config.load()
        Recents.shared.start()

        Gesture.shared.onTap = { [weak self] in self?.searchPanel?.toggle() }
        if Prefs.gestureEnabled {
            Gesture.shared.start(fingers: Prefs.gestureFingers, taps: Prefs.gestureTaps)
        }
        registerAppHotkeys()
        Notify.show("Reloaded \(entries.count) apps")
    }

    @objc private func toggleOpenAtPointer() {
        Prefs.openAtPointer.toggle()
        Notify.show(Prefs.openAtPointer ? "Search opens at the pointer"
                                        : "Search opens centred")
    }

    @objc private func toggleMonitor() {
        Prefs.systemMonitor.toggle()
        syncMonitor()
        Notify.show(Prefs.systemMonitor ? "System monitor on" : "System monitor off")
    }

    // MARK: - Menu bar widgets

    private func menuBarSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let shown = Prefs.menuBarItems
        for item in MenuBarItem.allCases {
            if item == .temperature && !Temperature.isAvailable { continue }
            let row = NSMenuItem(title: item.title,
                                 action: #selector(toggleMenuBarItem(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = item.rawValue
            row.state = shown.contains(item.rawValue) ? .on : .off
            submenu.addItem(row)
        }
        return submenu
    }

    @objc private func toggleMenuBarItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        var shown = Prefs.menuBarItems
        if shown.contains(raw) { shown.remove(raw) } else { shown.insert(raw) }
        Prefs.menuBarItems = shown
        applyMenuBar()
        syncMonitor()
    }

    /// What each switched-on reading currently says, in a fixed order.
    private func menuBarCells() -> [MenuBarView.Cell] {
        let shown = Prefs.menuBarItems
        let latest = Monitor.shared.latest

        return MenuBarItem.allCases.compactMap { item in
            guard shown.contains(item.rawValue) else { return nil }
            switch item {
            case .cpu:
                return .stat(label: item.label, value: String(format: "%.0f%%", latest.cpu))
            case .memory:
                return .stat(label: item.label, value: String(format: "%.0f%%", latest.memory))
            case .disk:
                guard let percent = latest.diskPercent else { return nil }
                return .stat(label: item.label, value: String(format: "%.0f%%", percent))
            case .temperature:
                guard let temperature = latest.temperature else { return nil }
                return .stat(label: item.label, value: String(format: "%.0f°", temperature))
            case .network:
                return .speed(up: SystemStats.rate(latest.tx),
                              down: SystemStats.rate(latest.rx))
            }
        }
    }

    /// Hosts the widget view in the status item, or takes it back out.
    ///
    /// The view goes inside the button as a subview and the button keeps an
    /// empty image, which is how Stats does it (Kit/module/widget.swift). The
    /// title has to go: a button draws its title over any subview.
    private func applyMenuBar() {
        guard let button = statusItem.button else { return }

        guard !Prefs.menuBarItems.isEmpty else {
            menuBarView?.removeFromSuperview()
            menuBarView = nil
            button.image = nil
            button.title = "Apps ▾"
            statusItem.length = NSStatusItem.variableLength
            return
        }

        let view = menuBarView ?? {
            let view = MenuBarView(frame: button.bounds)
            view.autoresizingMask = [.width, .height]
            button.addSubview(view)
            menuBarView = view
            return view
        }()
        button.title = ""
        button.image = NSImage()
        view.cells = menuBarCells()
        resizeStatusItem()
    }

    /// The status item has no intrinsic width once it hosts a view, so the
    /// length follows the drawing -- and only when it actually changes, since
    /// assigning it relays out the whole menu bar.
    private func resizeStatusItem() {
        guard let view = menuBarView else { return }
        let width = max(view.fittingWidth, 30)
        if abs(statusItem.length - width) > 0.5 {
            statusItem.length = width
        }
    }

    /// The sampler feeds both the menu's panel and the menu bar, so it runs if
    /// either wants it.
    private func syncMonitor() {
        if Prefs.systemMonitor || !Prefs.menuBarItems.isEmpty {
            Monitor.shared.start()
        } else {
            Monitor.shared.stop()
        }
    }

    @objc private func toggleHideOnOutsideClick() {
        Prefs.hideOnOutsideClick.toggle()
        Notify.show(Prefs.hideOnOutsideClick
                    ? "Search hides when you click away"
                    : "Search stays open — Escape to close")
    }

    /// Each option carries what macOS already does with that gesture, since
    /// this layer can only observe touches -- it cannot swallow them, so a
    /// clashing choice fires both actions.
    private func gestureSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let options: [(title: String, fingers: Int, taps: Int, note: String?)] = [
            ("Off", 0, 0, nil),
            ("4-finger tap", 4, 1, nil),
            ("3-finger tap", 3, 1, nil),
            ("2-finger double tap", 2, 2, "also right-clicks + Smart Zoom"),
        ]
        for option in options {
            let enabled = Prefs.gestureEnabled
            let selected = option.fingers == 0
                ? !enabled
                : enabled && Prefs.gestureFingers == option.fingers
                          && Prefs.gestureTaps == option.taps
            let title = option.note.map { "\(option.title)  —  \($0)" } ?? option.title
            let item = NSMenuItem(title: title, action: #selector(pickGesture(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.state = selected ? .on : .off
            item.tag = option.fingers * 10 + option.taps
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func pickGesture(_ sender: NSMenuItem) {
        let fingers = sender.tag / 10
        let taps = sender.tag % 10

        Gesture.shared.stop()
        guard fingers > 0 else {
            Prefs.gestureEnabled = false
            Notify.show("Trackpad gesture off")
            return
        }
        Prefs.gestureFingers = fingers
        Prefs.gestureTaps = taps
        Prefs.gestureEnabled = true

        if Gesture.shared.start(fingers: fingers, taps: taps) {
            var message = taps > 1 ? "\(fingers)-finger double tap opens search"
                                   : "\(fingers)-finger tap opens search"
            if fingers == 2 {
                message += " — macOS still right-clicks"
            }
            Notify.show(message, for: 4)
        } else {
            Prefs.gestureEnabled = false
            Notify.show("Could not read the trackpad — check Input Monitoring", for: 4)
        }
    }

    @objc private func toggleGesture() {
        Prefs.gestureEnabled.toggle()
        if Prefs.gestureEnabled {
            if Gesture.shared.start() {
                Notify.show("Three-finger tap opens search")
            } else {
                Prefs.gestureEnabled = false
                Notify.show("Could not read the trackpad — check Input Monitoring", for: 3)
            }
        } else {
            Gesture.shared.stop()
            Notify.show("Three-finger tap off")
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let wanted = !LoginItem.isEnabled
        if LoginItem.setEnabled(wanted) {
            Notify.show(wanted ? "Perch will launch at login" : "Launch at login off")
        } else {
            Notify.show("Launch at login: \(LoginItem.statusDescription)", for: 3)
        }
    }

    @objc private func openAccessibility() {
        WindowControl.requestAccessibility()
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
