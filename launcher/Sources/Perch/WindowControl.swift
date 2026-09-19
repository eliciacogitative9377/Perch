import AppKit
import ApplicationServices

/// What a menu row should show, and what a click should do.
enum AppState {
    case notRunning
    case noWindow      // menu-bar-only app: nothing to minimize
    case visible       // has a window on screen
    case minimized     // window minimized, or app hidden
    case fullScreen    // macOS refuses to minimize these
}

enum WindowControl {

    // MARK: - Accessibility

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt once; returns current trust state.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: - Small AX helpers

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func bool(_ element: AXUIElement, _ name: String) -> Bool {
        (attribute(element, name) as? Bool) ?? false
    }

    /// Finder publishes the desktop as an AXScrollArea alongside real windows.
    /// It cannot be minimized, so anything that is not a genuine AXWindow is
    /// ignored throughout.
    private static func isRealWindow(_ element: AXUIElement) -> Bool {
        (attribute(element, kAXRoleAttribute as String) as? String) == (kAXWindowRole as String)
    }

    private static func windows(of app: AXUIElement) -> [AXUIElement] {
        (attribute(app, kAXWindowsAttribute as String) as? [AXUIElement])?
            .filter(isRealWindow) ?? []
    }

    /// AXMainWindow is nil while an app's window is minimized, and for Finder
    /// it can be the desktop, so fall back to the app's real windows and
    /// prefer a minimized one -- that is the window a click wants to restore.
    private static func targetWindow(of app: AXUIElement) -> AXUIElement? {
        if let main = attribute(app, kAXMainWindowAttribute as String),
           CFGetTypeID(main) == AXUIElementGetTypeID() {
            let element = main as! AXUIElement
            if isRealWindow(element) { return element }
        }
        let all = windows(of: app)
        return all.first(where: { bool($0, kAXMinimizedAttribute as String) }) ?? all.first
    }

    // MARK: - State

    static func runningApp(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    // Each state() call is synchronous Accessibility IPC into another
    // process. Measured on this machine: ~183 ms to sweep 12 running apps,
    // with one slow app costing 29 ms on its own. The search panel rebuilds
    // on every keystroke, so typing six characters cost about a second of
    // blocked main thread. A short TTL removes all of that: window state
    // does not meaningfully change between keystrokes, and anything we
    // change ourselves invalidates its own entry immediately.
    //
    // Main-thread only, so a plain dictionary needs no locking.
    private static var stateCache: [String: (state: AppState, at: Date)] = [:]
    private static let stateTTL: TimeInterval = 5

    static func invalidateState(_ bundleID: String?) {
        guard let bundleID else { return }
        stateCache[bundleID] = nil
    }

    static func invalidateAllStates() { stateCache.removeAll() }

    /// Refresh a few stale entries so the panel never opens cold.
    ///
    /// Budgeted rather than exhaustive: a full sweep is ~260 ms of blocking
    /// IPC, which is fine spread a couple of apps at a time across a timer
    /// but not acceptable in one go on the main thread.
    static func warmStaleStates(limit: Int = 3) {
        let now = Date()
        var budget = limit
        for app in runningRegularApps() {
            guard budget > 0, let bundleID = app.bundleIdentifier else { break }
            if let cached = stateCache[bundleID],
               now.timeIntervalSince(cached.at) < stateTTL { continue }
            stateCache[bundleID] = (computeState(of: bundleID), now)
            budget -= 1
        }
    }

    static func state(of bundleID: String) -> AppState {
        if let cached = stateCache[bundleID],
           Date().timeIntervalSince(cached.at) < stateTTL {
            return cached.state
        }
        let fresh = computeState(of: bundleID)
        stateCache[bundleID] = (fresh, Date())
        return fresh
    }

    private static func computeState(of bundleID: String) -> AppState {
        guard let running = runningApp(bundleID) else { return .notRunning }
        if running.isHidden { return .minimized }

        let axApp = AXUIElementCreateApplication(running.processIdentifier)
        guard let window = targetWindow(of: axApp) else { return .noWindow }

        if bool(window, kAXMinimizedAttribute as String) { return .minimized }
        if bool(window, "AXFullScreen") { return .fullScreen }
        return .visible
    }

    // MARK: - Actions

    static func launch(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    static func activate(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private static func setMinimized(_ window: AXUIElement, _ minimized: Bool) {
        AXUIElementSetAttributeValue(window,
                                     kAXMinimizedAttribute as CFString,
                                     minimized as CFBoolean)
    }

    /// The click behaviour, mirroring the Dock but with restore folded in.
    ///
    /// not running      -> launch
    /// behind           -> bring to front
    /// frontmost        -> minimize
    /// minimized/hidden -> restore and focus
    /// full screen      -> cannot minimize (macOS); raise it if it is behind
    static func toggle(_ entry: AppEntry) {
        defer { invalidateState(entry.bundleID) }
        guard let running = runningApp(entry.bundleID) else {
            if !launch(entry.bundleID) {
                Notify.show("\(entry.name) is not installed")
            }
            return
        }

        if entry.launchOnly {
            activate(running)
            return
        }

        if running.isHidden {
            running.unhide()
            activate(running)
            return
        }

        let axApp = AXUIElementCreateApplication(running.processIdentifier)
        guard let window = targetWindow(of: axApp) else {
            activate(running)
            return
        }

        let isFrontmost = NSWorkspace.shared.frontmostApplication?
            .bundleIdentifier == entry.bundleID

        if bool(window, kAXMinimizedAttribute as String) {
            setMinimized(window, false)
            activate(running)
        } else if !isFrontmost {
            activate(running)
        } else if bool(window, "AXFullScreen") {
            // macOS cannot minimize a full-screen window.  Hiding the app as a
            // substitute was tried and rejected: Cmd-H tears down the
            // full-screen space, after which the app reports no windows while
            // AXHidden stays false and nothing can bring it back.
            Notify.show("macOS can't minimize a full-screen window", symbol: "macwindow")
        } else {
            setMinimized(window, true)
        }
    }

    // MARK: - New window

    /// Presses the app's own "New Window" menu item over the Accessibility API.
    ///
    /// There is no public call for this. NSWorkspace can launch an app or
    /// activate it, and `createsNewApplicationInstance` gives you a second
    /// copy of the process, not a second window. So every launcher that offers
    /// this drives the app's menu bar, which is what the Dock does too.
    ///
    /// The item is searched for rather than indexed: it is usually File > New
    /// Window, but Finder calls it New Finder Window, terminals offer New
    /// Window and New Tab, and the menu is localized. Matching on the words
    /// survives all three; an exact "new window" wins over a longer title so
    /// Chrome's "New Incognito Window" never gets picked first.
    static func newWindow(_ app: NSRunningApplication) -> Bool {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let bar = attribute(axApp, kAXMenuBarAttribute as String),
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return false }

        let menuBar = bar as! AXUIElement
        guard let topLevel = attribute(menuBar, kAXChildrenAttribute as String) as? [AXUIElement] else {
            return false
        }

        var fallback: AXUIElement?

        for menu in topLevel {
            // Each top-level title owns one AXMenu, whose children are items.
            guard let menus = attribute(menu, kAXChildrenAttribute as String) as? [AXUIElement],
                  let items = menus.first.flatMap({
                      attribute($0, kAXChildrenAttribute as String) as? [AXUIElement]
                  }) else { continue }

            for item in items {
                guard let title = (attribute(item, kAXTitleAttribute as String) as? String)?
                        .lowercased() else { continue }
                guard title.contains("window") else { continue }

                if title == "new window" {
                    return press(item, of: app)
                }
                if title.hasPrefix("new"), fallback == nil {
                    fallback = item
                }
            }
        }

        if let fallback {
            return press(fallback, of: app)
        }
        return false
    }

    private static func press(_ item: AXUIElement, of app: NSRunningApplication) -> Bool {
        // Some apps only build their menus once frontmost, so raise first and
        // press on the next turn.
        activate(app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AXUIElementPerformAction(item, kAXPressAction as CFString)
        }
        return true
    }

    // MARK: - Individual windows

    /// A window exposed to the menu: enough to label it and raise it.
    struct WindowRef {
        let element: AXUIElement
        let title: String
        let isMinimized: Bool
    }

    static func windowList(for app: NSRunningApplication) -> [WindowRef] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return windows(of: axApp).map { window in
            WindowRef(element: window,
                      title: (attribute(window, kAXTitleAttribute as String) as? String) ?? "Untitled",
                      isMinimized: bool(window, kAXMinimizedAttribute as String))
        }
    }

    /// Bring one specific window forward, unminimizing it first if needed.
    static func raise(_ window: WindowRef, of app: NSRunningApplication) {
        if window.isMinimized {
            setMinimized(window.element, false)
        }
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        activate(app)
    }

    static func quit(_ app: NSRunningApplication) {
        app.terminate()
    }

    // MARK: - One thing at a time

    /// The options menu asks for one specific thing, so these do exactly what
    /// they say -- unlike toggle(), which picks the next sensible step and can
    /// therefore minimize an app you meant to raise.

    static func bringToFront(_ entry: AppEntry) {
        if restore(entry.bundleID) { return }
        if !launch(entry.bundleID) { Notify.show("\(entry.name) is not installed") }
    }

    static func minimize(_ bundleID: String) {
        guard let running = runningApp(bundleID) else { return }
        let axApp = AXUIElementCreateApplication(running.processIdentifier)
        guard let window = targetWindow(of: axApp) else { return }
        if bool(window, "AXFullScreen") {
            Notify.show("macOS can't minimize a full-screen window", symbol: "macwindow")
            return
        }
        setMinimized(window, true)
    }

    static func hide(_ app: NSRunningApplication) {
        app.hide()
    }

    static func appURL(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Reveals the .app in Finder, for when you want the bundle rather than
    /// the running program.
    static func revealInFinder(_ bundleID: String) {
        guard let url = appURL(bundleID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Running apps that show up in the UI, for the auto-discovered section.
    static func runningRegularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "")
                        == .orderedAscending }
    }

    /// Bring an app forward without the minimise half of toggle().
    ///
    /// Cycling must only ever raise: if it toggled, stepping onto the app you
    /// are already in would hide it instead of switching to it.
    static func toggleActivateOnly(_ app: NSRunningApplication) {
        defer { invalidateState(app.bundleIdentifier) }
        if app.isHidden { app.unhide() }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        if let window = targetWindow(of: axApp),
           bool(window, kAXMinimizedAttribute as String) {
            setMinimized(window, false)
        }
        activate(app)
    }

    /// Used by the minimize/restore hotkey.
    static func minimizeFrontmost() -> String? {
        defer { invalidateState(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) }
        guard let running = NSWorkspace.shared.frontmostApplication,
              let bundleID = running.bundleIdentifier else { return nil }

        let axApp = AXUIElementCreateApplication(running.processIdentifier)
        guard let window = targetWindow(of: axApp) else { return nil }

        if bool(window, "AXFullScreen") {
            Notify.show("macOS can't minimize a full-screen window", symbol: "macwindow")
            return nil
        }
        setMinimized(window, true)
        return bundleID
    }

    static func restore(_ bundleID: String) -> Bool {
        defer { invalidateState(bundleID) }
        guard let running = runningApp(bundleID) else { return false }
        if running.isHidden { running.unhide() }

        let axApp = AXUIElementCreateApplication(running.processIdentifier)
        if let window = targetWindow(of: axApp),
           bool(window, kAXMinimizedAttribute as String) {
            setMinimized(window, false)
        }
        activate(running)
        return true
    }
}
