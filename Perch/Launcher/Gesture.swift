import AppKit

/// A trackpad tap gesture opens the search (two-finger double tap by default).
///
/// macOS has no public API for custom trackpad gestures -- the public
/// NSEvent gesture events only arrive for the frontmost app's own views, and
/// the system owns the three and four finger swipes. The only route to a
/// global gesture is MultitouchSupport, a private framework. That is what
/// BetterTouchTool and friends use.
///
/// Consequences, deliberately accepted:
///   - private API: undocumented, and Apple can change or remove it
///   - cannot be shipped through the Mac App Store
///   - macOS may require Input Monitoring permission to see raw touches
///
/// To keep the risk small this reads *only* the finger count that the
/// callback is handed. It never parses the MTTouch struct, whose layout has
/// changed between macOS releases and is the usual reason this kind of code
/// breaks.
final class Gesture {
    static let shared = Gesture()

    /// Set before start(). Called on the main queue.
    var onTap: (() -> Void)?

    private var handle: UnsafeMutableRawPointer?
    private var devices: [UnsafeMutableRawPointer] = []
    private var running = false

    private typealias ContactCallback =
        @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias RegisterCallback =
        @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
    private typealias DeviceStart = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias DeviceStop = @convention(c) (UnsafeMutableRawPointer) -> Void

    // The C callback cannot capture context, so the tap state lives here.
    fileprivate static var fingersDown = 0
    fileprivate static var peak = 0
    fileprivate static var startedAt: Double = 0
    fileprivate static var requiredFingers = 2
    fileprivate static var requiredTaps = 2
    /// Tight on purpose. Multi-finger *swipes* drive Mission Control and
    /// space switching, and this only sees finger counts, not movement -- so
    /// duration is the discriminator. A tap is well under this; a swipe keeps
    /// fingers down far longer.
    fileprivate static let maxTapDuration = 0.25
    /// How long a second tap has to arrive to count as a double tap.
    fileprivate static let doubleTapWindow = 0.45
    fileprivate static var tapCount = 0
    fileprivate static var lastTapAt: Double = 0

    private init() {}

    var isAvailable: Bool {
        FileManager.default.fileExists(
            atPath: "/System/Library/PrivateFrameworks/MultitouchSupport.framework")
    }

    @discardableResult
    func start(fingers: Int = 2, taps: Int = 2) -> Bool {
        guard !running else { return true }
        Gesture.requiredFingers = fingers
        Gesture.requiredTaps = max(1, taps)
        Gesture.tapCount = 0

        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            NSLog("Perch: MultitouchSupport unavailable: \(String(cString: dlerror()))")
            return false
        }
        self.handle = handle

        guard let createSym = dlsym(handle, "MTDeviceCreateList"),
              let registerSym = dlsym(handle, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(handle, "MTDeviceStart") else {
            NSLog("Perch: MultitouchSupport symbols missing")
            return false
        }

        let createList = unsafeBitCast(createSym, to: CreateList.self)
        let register = unsafeBitCast(registerSym, to: RegisterCallback.self)
        let deviceStart = unsafeBitCast(startSym, to: DeviceStart.self)

        guard let list = createList()?.takeRetainedValue() as? [AnyObject], !list.isEmpty else {
            NSLog("Perch: no multitouch devices")
            return false
        }

        for entry in list {
            let device = Unmanaged.passUnretained(entry).toOpaque()
            register(device, gestureContactCallback)
            deviceStart(device, 0)
            devices.append(device)
        }
        running = true
        return true
    }

    func stop() {
        guard running, let handle, let stopSym = dlsym(handle, "MTDeviceStop") else { return }
        let deviceStop = unsafeBitCast(stopSym, to: DeviceStop.self)
        devices.forEach { deviceStop($0) }
        devices.removeAll()
        running = false
    }

    fileprivate func fire() {
        DispatchQueue.main.async { [weak self] in self?.onTap?() }
    }
}

/// Top-level so it can be a C function pointer.
///
/// Only `fingers` is used; the touch buffer is never dereferenced.
private func gestureContactCallback(device: Int32,
                                    data: UnsafeMutableRawPointer?,
                                    fingers: Int32,
                                    timestamp: Double,
                                    frame: Int32) -> Int32 {
    let count = Int(fingers)

    if count > Gesture.fingersDown {
        if Gesture.fingersDown == 0 { Gesture.startedAt = timestamp }
        Gesture.peak = max(Gesture.peak, count)
    }

    if count == 0 && Gesture.fingersDown > 0 {
        let quick = (timestamp - Gesture.startedAt) < Gesture.maxTapDuration
        if quick && Gesture.peak == Gesture.requiredFingers {
            // a tap landed; see whether it completes the required run
            if timestamp - Gesture.lastTapAt > Gesture.doubleTapWindow {
                Gesture.tapCount = 0
            }
            Gesture.tapCount += 1
            Gesture.lastTapAt = timestamp
            if Gesture.tapCount >= Gesture.requiredTaps {
                Gesture.tapCount = 0
                Gesture.shared.fire()
            }
        } else {
            Gesture.tapCount = 0
        }
        Gesture.peak = 0
    }

    Gesture.fingersDown = count
    return 0
}
