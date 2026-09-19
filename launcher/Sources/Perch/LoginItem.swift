import Foundation
import ServiceManagement

/// Launch at login.
///
/// macOS 13+ does this with SMAppService and no helper bundle at all -- the
/// older approach (a second .app inside Contents/Library/LoginItems, as Stats
/// and most pre-Ventura apps use) is unnecessary here since the deployment
/// target is already 13.0.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True if the change stuck.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                // .requiresApproval means macOS registered it but the user has
                // switched it off in System Settings > General > Login Items.
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return isEnabled == enabled
        } catch {
            NSLog("Perch: launch at login \(enabled ? "register" : "unregister") failed: \(error)")
            return false
        }
    }

    /// Human-readable state, for the menu.
    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:           return "enabled"
        case .requiresApproval:  return "needs approval in System Settings"
        case .notRegistered:     return "off"
        case .notFound:          return "unavailable"
        @unknown default:        return "unknown"
        }
    }
}
