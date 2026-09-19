import Foundation

/// One row in the menu.
struct AppEntry: Codable {
    let name: String
    let bundleID: String
    /// Apps that only ever launch (Launchpad), never minimize.
    var launchOnly: Bool = false
    /// Optional direct hotkey: a single character, pressed with Control.
    /// "2" means Ctrl+2 jumps straight to this app, no menu.
    var shortcut: String? = nil
    /// Held at the top of the list regardless of recency or search score.
    /// Launchpad is pinned by default: it is a launcher you reach for, not
    /// an app you "use", so recency ranking would always bury it.
    var pinned: Bool = false

    enum CodingKeys: String, CodingKey {
        case name, bundleID, launchOnly, shortcut, pinned
    }
}

/// The app list lives in a JSON file, not in the binary, so adding an app is
/// an edit and a reload rather than a rebuild.
enum Config {
    static let directory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Perch", isDirectory: true)

    static let fileURL = directory.appendingPathComponent("apps.json")

    static let defaults: [AppEntry] = [
        AppEntry(name: "Finder",             bundleID: "com.apple.finder",             shortcut: "1"),
        AppEntry(name: "Launchpad (Apps)",   bundleID: "com.apple.apps.launcher", launchOnly: true, pinned: true),
        AppEntry(name: "Google Chrome",      bundleID: "com.google.Chrome",            shortcut: "2"),
        AppEntry(name: "Discord",            bundleID: "com.hnc.Discord",              shortcut: "3"),
        AppEntry(name: "Orca",               bundleID: "com.stablyai.orca",            shortcut: "4"),
        AppEntry(name: "Antigravity IDE",    bundleID: "com.google.antigravity-ide",   shortcut: "5"),
        AppEntry(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode",         shortcut: "6"),
        AppEntry(name: "Firefox",            bundleID: "org.mozilla.firefox"),
        AppEntry(name: "Safari",             bundleID: "com.apple.Safari"),
        AppEntry(name: "Thunderbird",        bundleID: "org.mozilla.thunderbird"),
        AppEntry(name: "Chromium",           bundleID: "org.chromium.Chromium"),
        AppEntry(name: "Notes",              bundleID: "com.apple.Notes"),
        AppEntry(name: "Music",              bundleID: "com.apple.Music"),
        AppEntry(name: "Reminders",          bundleID: "com.apple.reminders"),
        AppEntry(name: "OpenVPN Connect",    bundleID: "org.openvpn.client.app"),
        AppEntry(name: "Telegram",           bundleID: "ru.keepcoder.Telegram",        shortcut: "7"),
        AppEntry(name: "Dropbox",            bundleID: "com.getdropbox.dropbox"),
        AppEntry(name: "Terminal",           bundleID: "com.apple.Terminal",           shortcut: "8"),
        AppEntry(name: "System Settings",    bundleID: "com.apple.systempreferences",  shortcut: "9"),
    ]

    /// Reads the list, writing the default file the first time.
    static func load() -> [AppEntry] {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            save(defaults)
            return defaults
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([AppEntry].self, from: data)
        } catch {
            NSLog("Perch: could not read \(fileURL.path): \(error). Using defaults.")
            return defaults
        }
    }

    static func save(_ entries: [AppEntry]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Perch: could not write \(fileURL.path): \(error)")
        }
    }
}
