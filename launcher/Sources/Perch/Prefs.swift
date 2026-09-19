import Foundation

/// Small settings that do not belong in the app list file.
enum Prefs {
    private static let cycleKey = "cycleHotkeyEnabled"

    /// Ctrl+Tab cycles recent apps. On by default, but it does take Ctrl+Tab
    /// from browsers and terminals, so it is switchable.
    static var cycleHotkeyEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: cycleKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: cycleKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: cycleKey) }
    }

    private static let openAtPointerKey = "openAtPointer"
    private static let gestureKey = "gestureEnabled"
    private static let hideOnOutsideClickKey = "hideOnOutsideClick"
    private static let tempInMenuBarKey = "tempInMenuBar"
    private static let menuBarItemsKey = "menuBarItems"
    private static let monitorKey = "systemMonitor"
    private static let gestureFingersKey = "gestureFingers"
    private static let gestureTapsKey = "gestureTaps"

    /// Where the search panel appears.  Defaults to the pointer, which is how
    /// the menu behaved before the panel existed.
    static var openAtPointer: Bool {
        get {
            if UserDefaults.standard.object(forKey: openAtPointerKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: openAtPointerKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: openAtPointerKey) }
    }

    /// Trackpad gesture opens the search. On by default.
    static var gestureEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: gestureKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: gestureKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: gestureKey) }
    }

    /// Whether the search panel closes when it loses focus. On by default,
    /// which is how Spotlight behaves. Turn it off to keep the panel up while
    /// you click around elsewhere; Escape or Ctrl+Space still closes it.
    static var hideOnOutsideClick: Bool {
        get {
            if UserDefaults.standard.object(forKey: hideOnOutsideClickKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: hideOnOutsideClickKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: hideOnOutsideClickKey) }
    }

    /// Show the CPU temperature next to the menu bar title. Off by default:
    /// it widens the status item, and macOS hides menu bar items when the bar
    /// is crowded.
    static var tempInMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: tempInMenuBarKey) }
        set { UserDefaults.standard.set(newValue, forKey: tempInMenuBarKey) }
    }

    /// How many fingers the trackpad gesture wants, and how many taps.
    ///
    /// Two-finger double tap by default, as asked for. Note macOS already
    /// uses it: each tap is a secondary click and the pair is Smart Zoom, and
    /// this layer can only observe touches, so those still fire. Pick
    /// 4-finger tap in the menu for the one combination nothing stock claims.
    static var gestureFingers: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: gestureFingersKey)
            return value == 0 ? 2 : value
        }
        set { UserDefaults.standard.set(newValue, forKey: gestureFingersKey) }
    }

    static var gestureTaps: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: gestureTapsKey)
            return value == 0 ? 2 : value
        }
        set { UserDefaults.standard.set(newValue, forKey: gestureTapsKey) }
    }

    /// Which readings are drawn in the menu bar itself, as Stats' widgets
    /// are. Empty means none, and the status item falls back to its title.
    ///
    /// A set rather than a handful of booleans because the drawing order is
    /// fixed by MenuBarItem.allCases -- what varies is only which are in.
    static var menuBarItems: Set<String> {
        get {
            if let stored = UserDefaults.standard.array(forKey: menuBarItemsKey) as? [String] {
                return Set(stored)
            }
            // First run after the old single temperature toggle: carry it over
            // so someone who had it on does not lose it.
            return UserDefaults.standard.bool(forKey: tempInMenuBarKey)
                ? [MenuBarItem.cpu.rawValue, MenuBarItem.temperature.rawValue]
                : [MenuBarItem.cpu.rawValue, MenuBarItem.memory.rawValue]
        }
        set { UserDefaults.standard.set(Array(newValue), forKey: menuBarItemsKey) }
    }

    /// Sample CPU/memory/network on a timer so the menu can show graphs.
    static var systemMonitor: Bool {
        get {
            if UserDefaults.standard.object(forKey: monitorKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: monitorKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: monitorKey) }
    }
}

/// The readings that can be shown in the menu bar, in the order they are
/// drawn. Raw values are what lands in UserDefaults, so they are stable.
enum MenuBarItem: String, CaseIterable {
    case disk, cpu, memory, temperature, network

    var title: String {
        switch self {
        case .disk:        return "Disk"
        case .cpu:         return "CPU"
        case .memory:      return "Memory"
        case .temperature: return "Temperature"
        case .network:     return "Network Speed"
        }
    }

    /// The short form drawn above the value, where space is measured in pixels.
    var label: String {
        switch self {
        case .disk:        return "SSD"
        case .cpu:         return "CPU"
        case .memory:      return "RAM"
        case .temperature: return "TEMP"
        case .network:     return ""
        }
    }
}
