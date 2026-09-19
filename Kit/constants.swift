//
//  constants.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 15/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public struct Popup_c_s {
    public let width: CGFloat = 264
    public let height: CGFloat = 300
    public let margins: CGFloat = 8
    public let spacing: CGFloat = 2
    public let headerHeight: CGFloat = 42
    public let separatorHeight: CGFloat = 30
    public let radius: CGFloat = 6
    public let processHeight: CGFloat = 22
}

public struct Settings_c_s {
    public let width: CGFloat = 540
    public let height: CGFloat = 480
    public let margin: CGFloat = 10
}

public struct Widget_c_s {
    public let width: CGFloat = 32
    public var height: CGFloat {
        get {
            let systemHeight = NSApplication.shared.mainMenu?.menuBarHeight
            return (systemHeight == 0 ? 22 : systemHeight) ?? 22
        }
    }
    public var margin: CGPoint {
        get { CGPoint(x: 0, y: 2) }
    }
    public let spacing: CGFloat = 2
}

public struct Constants {
    public static let Popup: Popup_c_s = Popup_c_s()
    public static let Settings: Settings_c_s = Settings_c_s()
    public static let Widget: Widget_c_s = Widget_c_s()
    
    public static let defaultProcessIcon = NSWorkspace.shared.icon(forFile: "/bin/bash")
}

public enum ModuleType: Int {
    case CPU
    case RAM
    case GPU
    case disk
    case sensors
    case network
    case battery
    case bluetooth
    case clock
    case remote
    
    case combined
    
    public var stringValue: String {
        switch self {
        case .CPU: return "CPU"
        case .RAM: return "RAM"
        case .GPU: return "GPU"
        case .disk: return "Disk"
        case .sensors: return "Sensors"
        case .network: return "Network"
        case .battery: return "Battery"
        case .bluetooth: return "Bluetooth"
        case .clock: return "Clock"
        case .remote: return "Remote"
        case .combined: return ""
        }
    }
    
    public var activityMonitorTab: Int? {
        switch self {
        case .CPU: return 0
        case .RAM: return 1
        case .disk: return 3
        case .network: return 4
        case .battery: return 2
        default: return nil
        }
    }
}

/// Where this fork points. Every outward link in the app reads from here, so
/// repointing the fork is one edit rather than a hunt through the views.
///
/// Upstream's own links are deliberately absent: a fork that keeps them sends
/// its users' bug reports to someone else's tracker and its donations to
/// someone else's account. Attribution belongs in LICENSE and NOTICE.md -- and
/// stays there, because MIT requires the copyright notice to be retained.
public enum Branding {
    /// owner/name on GitHub. The owner here is the Ko-fi handle -- correct it
    /// if your GitHub account differs, and every link below follows.
    public static let repository = "sagardn/Perch"

    public static var repositoryURL: URL? {
        URL(string: "https://github.com/\(repository)")
    }
    public static var issuesURL: URL? {
        URL(string: "https://github.com/\(repository)/issues/new")
    }
    public static var releasesURL: URL? {
        URL(string: "https://github.com/\(repository)/releases")
    }
    public static func releaseNotesURL(_ version: String) -> URL? {
        URL(string: "https://github.com/\(repository)/releases/tag/\(version)")
    }

    /// Whether this fork has a release feed to check against.
    ///
    /// While false the app never checks for updates, and the update interval
    /// defaults to Never. Two reasons, and the second is the serious one:
    ///
    /// 1. There is nothing to check. The repository below has no releases yet
    ///    and the feed URL is deliberately dead, so a check can only fail --
    ///    silently, once per launch, forever.
    /// 2. The "Silent" interval does not just check. It downloads and calls
    ///    updater.install(), which replaces the running application without
    ///    asking. Shipping that switched on, against a version number
    ///    inherited from upstream (3.0.16), means the first release published
    ///    under any tag the comparison reads as newer would overwrite the app
    ///    with no prompt. Turn this on deliberately, once the feed is yours
    ///    and the version numbering is yours.
    public static let updatesEnabled = false

    /// What the update-interval setting defaults to.
    public static var defaultUpdateInterval: String {
        updatesEnabled ? "Silent" : "Never"
    }

    /// Ko-fi page for this fork. nil would hide the Donate button rather than
    /// point it somewhere that is not yours.
    public static let donationURL: URL? = URL(string: "https://ko-fi.com/sagardn")

    /// The remote monitoring service. nil disables the Remote module outright:
    /// the protocol, the accounts and the servers are upstream's, so a fork has
    /// nothing to talk to.
    public static let remoteServiceHost: URL? = nil

    /// Public IP lookup, replacing upstream's own endpoint.
    ///
    /// ifconfig.co is echoip (https://github.com/mpolden/echoip), MIT and
    /// self-hostable -- so if you would rather not depend on someone else's
    /// server at all, run echoip and point these at it. The caller forces the
    /// address family with curl's -4/-6, which is why one path serves both.
    public static let publicIPv4 = "https://ifconfig.co/ip"
    public static let publicIPv6 = "https://ifconfig.co/ip"
}
