import Foundation

/// Launcher settings that do not belong in the app list file.
///
/// Deliberately UserDefaults rather than Kit's Store: these belong to the
/// launcher half of the app and outlive any module being enabled.
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
}

/// The readings that can be shown in the menu bar, in the order they are
/// drawn. Raw values are what lands in UserDefaults, so they are stable.
