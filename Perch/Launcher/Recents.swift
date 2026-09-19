import AppKit

/// Remembers when each app was last brought to the front, so the search list
/// can lead with what you actually use.
///
/// This listens to NSWorkspace's activation notification rather than only
/// recording Perch's own picks, so switching with Cmd-Tab, the Dock or a
/// click all count. It is a passive notification, not a polling watcher.
final class Recents {
    static let shared = Recents()

    private let key = "recentApps"
    private let limit = 200
    private var lastUsed: [String: Double] = [:]

    private init() {
        lastUsed = (UserDefaults.standard.dictionary(forKey: key) as? [String: Double]) ?? [:]
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self,
                           selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification,
                           object: nil)
        // seed with whatever is in front right now, otherwise it stays unranked
        // until the next switch
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            record(front)
        }
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,   // ignore ourselves
              isRealApp(app)
        else { return }
        WindowControl.invalidateState(bundleID)
        record(bundleID)
    }

    /// Filters out the system UI that borrows focus for a moment — the
    /// password prompt, the Accessibility permission dialog, notification
    /// banners. They are genuine frontmost activations, so without this they
    /// outrank the apps you were actually using.
    ///
    /// The test is where the bundle lives rather than a list of names:
    /// real apps sit in /Applications or /System/Applications, while these
    /// agents live under /System/Library.
    private func isRealApp(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular else { return false }
        guard let path = app.bundleURL?.path else { return false }
        return !path.contains("/System/Library/")
    }

    private func record(_ bundleID: String) {
        lastUsed[bundleID] = Date().timeIntervalSince1970
        if lastUsed.count > limit {
            let keep = lastUsed.sorted { $0.value > $1.value }.prefix(limit)
            lastUsed = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        UserDefaults.standard.set(lastUsed, forKey: key)
    }

    /// The most recently used apps, newest first.
    ///
    /// Skips Perch and the app you are currently in — listing the app you are
    /// already looking at wastes a slot, the same reason rank() demotes it.
    func top(_ count: Int) -> [NSRunningApplication] {
        let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return lastUsed
            .sorted { $0.value > $1.value }
            .compactMap { bundleID, _ -> NSRunningApplication? in
                guard bundleID != current,
                      bundleID != Bundle.main.bundleIdentifier,
                      let app = NSRunningApplication
                        .runningApplications(withBundleIdentifier: bundleID).first,
                      isRealApp(app) else { return nil }
                return app
            }
            .prefix(count)
            .map { $0 }
    }

    // MARK: - Cycling

    /// The list is snapshotted when a cycle begins and reused until the cycle
    /// lapses. Without that, activating an app makes it the most recent one,
    /// which reshuffles the list underneath and turns a walk backwards
    /// through history into a flip between two apps.
    private var cycleList: [NSRunningApplication] = []
    private var cycleIndex = 0
    private var lastCycleAt = Date.distantPast
    private let cycleWindow: TimeInterval = 1.5

    /// Step to the next app in the cycle, Cmd-Tab style.
    ///
    /// `among` restricts the cycle to a chosen set of bundle identifiers --
    /// the marked apps. Order still comes from recency, so within the set it
    /// behaves like Cmd-Tab: one tap lands on the app you came from.
    ///
    /// Passing nil or an empty set cycles the ten most recent apps, which is
    /// what happens until something is marked. Marking an app is the opt-in;
    /// there is no separate switch to forget about.
    @discardableResult
    func cycleToNext(among marked: Set<String>? = nil) -> NSRunningApplication? {
        let now = Date()
        if now.timeIntervalSince(lastCycleAt) > cycleWindow || cycleList.isEmpty {
            if let marked, !marked.isEmpty {
                cycleList = running(in: marked)
            } else {
                cycleList = top(10)
            }
            cycleIndex = 0
        } else {
            cycleIndex += 1
        }
        lastCycleAt = now

        guard !cycleList.isEmpty else { return nil }
        let app = cycleList[cycleIndex % cycleList.count]
        WindowControl.toggleActivateOnly(app)
        return app
    }

    /// The marked apps that are actually running, most recently used first.
    ///
    /// Marked-but-not-running apps are left out on purpose: Ctrl+Tab is for
    /// switching, and a tap that launches something is a different gesture --
    /// that is what the per-app Ctrl+digit keys and the search panel are for.
    private func running(in marked: Set<String>) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                guard let id = app.bundleIdentifier else { return false }
                return marked.contains(id) && app.activationPolicy == .regular
            }
            .sorted { rank(for: $0.bundleIdentifier ?? "") > rank(for: $1.bundleIdentifier ?? "") }
    }

    /// Higher is more recent. nil means never seen.
    func time(for bundleID: String) -> Double? { lastUsed[bundleID] }

    /// Rank for sorting, most recent first.
    ///
    /// The app you are currently in is pushed to the back of the recents, the
    /// way Cmd-Tab leads with the app you came *from* rather than the one you
    /// are already looking at.
    func rank(for bundleID: String) -> Double {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
            return -1
        }
        return lastUsed[bundleID] ?? 0
    }
}
