import AppKit

/// The app-switcher half of Perch: the Ctrl+Space search panel, the per-app
/// hotkeys, the minimize/restore key and the trackpad gesture.
///
/// Kept as one controller rather than folded into AppDelegate so the two
/// halves of the app stay separable -- the monitoring side is Stats' module
/// system and knows nothing about this, and this knows nothing about modules.
final class Launcher {

    static let shared = Launcher()

    private var entries: [AppEntry] = []
    private var searchPanel: SearchPanel?
    private var appsWindow: AppsWindow?

    private var searchHotkey: Hotkey?
    private var minimizeHotkey: Hotkey?
    private var cycleHotkey: Hotkey?
    private var warmTimer: Timer?
    /// Ctrl+<digit> straight to one app. Held so they stay registered.
    private var appHotkeys: [Hotkey] = []

    /// What the minimize hotkey put away, so the same key can bring it back.
    private var stashed: [String] = []

    private init() {}

    func start() {
        entries = Config.load()
        Recents.shared.start()

        searchPanel = SearchPanel(source: { [weak self] in self?.entries ?? [] },
                                  onPick: { entry in WindowControl.toggle(entry) },
                                  onSetListed: { [weak self] changed, listed in
                                      self?.setListed(changed, listed)
                                  },
                                  onEditApps: { [weak self] in self?.editApps() })

        searchHotkey = Hotkey(keyCode: Hotkey.Key.space, modifiers: .control) { [weak self] in
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
            cycleHotkey = Hotkey(keyCode: Hotkey.Key.tab, modifiers: .control) {
                Recents.shared.cycleToNext()
            }
        }

        minimizeHotkey = Hotkey(keyCode: Hotkey.Key.grave, modifiers: .control) { [weak self] in
            self?.toggleFrontmost()
        }
        registerAppHotkeys()

        Gesture.shared.onTap = { [weak self] in self?.searchPanel?.toggle() }
        if Prefs.gestureEnabled {
            Gesture.shared.start(fingers: Prefs.gestureFingers, taps: Prefs.gestureTaps)
        }

        // Raising a window needs no permission; minimizing one does.
        if !WindowControl.isTrusted {
            WindowControl.requestAccessibility()
            Notify.show("Perch needs Accessibility to move windows", for: 3)
        }
    }

    func showSearch() {
        searchPanel?.show()
    }

    func toggleSearch() {
        searchPanel?.toggle()
    }

    // MARK: - The app list

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

    /// Add or drop apps from the list, saving and re-registering the hotkeys
    /// so a removed app stops answering its Ctrl+digit. Takes a list because
    /// the file picker allows several at once, and six HUDs is not a report.
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
        Notify.show(listed ? "Added \(what)" : "Removed \(what)")
    }

    func editApps() {
        let window = AppsWindow(entries: entries) { [weak self] updated in
            guard let self else { return }
            self.entries = updated
            self.registerAppHotkeys()
        }
        appsWindow = window
        window.present()
    }

    func reload() {
        entries = Config.load()
        registerAppHotkeys()
        Notify.show("Reloaded \(entries.count) apps")
    }

    // MARK: - Minimize / restore

    /// One key for both directions: after minimizing, the app is no longer
    /// frontmost, so pressing it again can only mean "bring back what I just
    /// put away".
    private func toggleFrontmost() {
        if let last = stashed.popLast() {
            if !WindowControl.restore(last) { Notify.show("Nothing to restore") }
            return
        }
        if let bundleID = WindowControl.minimizeFrontmost() {
            stashed.append(bundleID)
        }
    }

    // MARK: - Gesture

    func applyGesture() {
        if Prefs.gestureEnabled {
            if !Gesture.shared.start(fingers: Prefs.gestureFingers, taps: Prefs.gestureTaps) {
                Prefs.gestureEnabled = false
                Notify.show("Could not read the trackpad — check Input Monitoring", for: 3)
            }
        } else {
            Gesture.shared.stop()
        }
    }
}
