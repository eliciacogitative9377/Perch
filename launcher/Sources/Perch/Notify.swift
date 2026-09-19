import AppKit

/// A small centred HUD, like Hammerspoon's hs.alert.
///
/// Deliberately not UserNotifications: that needs a signed bundle and the
/// user granting notification permission, which is far too much ceremony for
/// "this window can't be minimized".
enum Notify {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, for seconds: TimeInterval = 1.6) {
        DispatchQueue.main.async {
            hideWork?.cancel()
            panel?.orderOut(nil)

            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 15, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.sizeToFit()

            let padding = NSSize(width: 28, height: 18)
            let size = NSSize(width: label.frame.width + padding.width * 2,
                              height: label.frame.height + padding.height * 2)

            let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            background.material = .hudWindow
            background.state = .active
            background.blendingMode = .behindWindow
            background.wantsLayer = true
            background.layer?.cornerRadius = 12
            background.layer?.masksToBounds = true

            label.frame.origin = NSPoint(x: padding.width, y: padding.height)
            background.addSubview(label)

            let hud = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered,
                              defer: false)
            hud.contentView = background
            hud.isOpaque = false
            hud.backgroundColor = .clear
            hud.level = .statusBar
            hud.ignoresMouseEvents = true
            hud.hidesOnDeactivate = false
            hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                hud.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                           y: frame.minY + frame.height * 0.18))
            }
            hud.orderFrontRegardless()
            panel = hud

            let work = DispatchWorkItem {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    hud.animator().alphaValue = 0
                } completionHandler: {
                    hud.orderOut(nil)
                    if panel === hud { panel = nil }
                }
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
    }
}
