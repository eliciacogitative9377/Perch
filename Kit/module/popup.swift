//
//  popup.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 11/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public final class PopupCache<T> {
    public var value: T?
    public var initialized: Bool = false
    
    public init() {}
    
    public func apply(_ value: T, visible: Bool, render: (T) -> Void) {
        self.value = value
        if visible || !self.initialized {
            render(value)
            self.initialized = true
        }
    }
    
    public func replay(render: (T) -> Void) {
        if let v = self.value { render(v) }
    }
}

public protocol Popup_p: NSView {
    var keyboardShortcut: [UInt16] { get }
    var sizeCallback: ((NSSize) -> Void)? { get set }
    
    func settings() -> NSView?
    
    func appear()
    func disappear()
    func setKeyboardShortcut(_ binding: [UInt16])
}

open class PopupWrapper: NSStackView, Popup_p {
    public var title: String
    public var keyboardShortcut: [UInt16] = []
    open var sizeCallback: ((NSSize) -> Void)? = nil
    
    public init(_ typ: ModuleType, frame: NSRect) {
        self.title = typ.stringValue
        self.keyboardShortcut = Store.shared.array(key: "\(typ.stringValue)_popup_keyboardShortcut", defaultValue: []) as? [UInt16] ?? []
        
        super.init(frame: frame)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open func settings() -> NSView? { return nil }
    open func appear() {}
    open func disappear() {}
    
    open func setKeyboardShortcut(_ binding: [UInt16]) {
        self.keyboardShortcut = binding
        Store.shared.set(key: "\(self.title)_popup_keyboardShortcut", value: binding)
    }
    
    public func apply<T>(_ value: T, to cache: PopupCache<T>, render: @escaping (T) -> Void) {
        DispatchQueue.main.async {
            cache.apply(value, visible: self.window?.isVisible ?? false, render: render)
        }
    }
    
    public func replay<T>(_ cache: PopupCache<T>, render: (T) -> Void) {
        cache.replay(render: render)
    }
}

public class PopupWindow: NSWindow, NSWindowDelegate {
    private let viewController: PopupViewController
    internal var locked: Bool = false
    internal var openedBy: widget_t? = nil
    
    public init(title: String, module: ModuleType, view: Popup_p?, visibilityCallback: @escaping (_ state: Bool) -> Void) {
        self.viewController = PopupViewController(module: module)
        self.viewController.setup(title: title, view: view)
        
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: self.viewController.view.frame.width,
                height: self.viewController.view.frame.height
            ),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        
        self.viewController.visibilityCallback = { [weak self] state in
            self?.locked = false
            visibilityCallback(state)
        }
        
        self.title = title
        self.titleVisibility = .hidden
        self.contentViewController = self.viewController
        self.titlebarAppearsTransparent = true
        self.animationBehavior = .default
        self.collectionBehavior = .moveToActiveSpace
        // A titled window is opaque by default, so a clear background colour
        // alone still composites over solid black -- which is why the material
        // underneath never showed.
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.setIsVisible(false)
        self.delegate = self
    }
    
    public func windowWillMove(_ notification: Notification) {
        self.viewController.setCloseButton(true)
        self.locked = true
    }
    
    public func windowDidResignKey(_ notification: Notification) {
        if self.locked {
            return
        }
        
        self.viewController.setCloseButton(false)
        self.setIsVisible(false)
    }
}

internal class PopupViewController: NSViewController {
    fileprivate var visibilityCallback: (_ state: Bool) -> Void = {_ in }
    private var popup: PopupView
    
    public init(module: ModuleType) {
        self.popup = PopupView(frame: NSRect(
            x: 0,
            y: 0,
            width: Constants.Popup.width + (Constants.Popup.margins * 2),
            height: Constants.Popup.height+Constants.Popup.headerHeight
        ), module: module)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        self.view = self.popup
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        
        self.popup.appear()
        self.visibilityCallback(true)
        NotificationCenter.default.post(name: .popupVisibilityChanged, object: nil, userInfo: ["state": true])
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        self.popup.disappear()
        self.visibilityCallback(false)
        NotificationCenter.default.post(name: .popupVisibilityChanged, object: nil, userInfo: ["state": false])
    }
    
    fileprivate func setup(title: String, view: Popup_p?) {
        self.title = title
        self.popup.setTitle(title)
        self.popup.setView(view)
    }
    
    fileprivate func setCloseButton(_ state: Bool) {
        self.popup.setCloseButton(state)
    }
}

internal class PopupView: NSView {
    private var view: Popup_p? = nil
    
    private var foreground: NSVisualEffectView
    private var background: NSView
    /// Liquid Glass on macOS 26+. The vibrancy pair above is the fallback.
    private var glass: NSView?
    /// What the glass embeds: NSGlassEffectView only promises to place its
    /// contentView inside the effect, so header and body live in one container
    /// rather than as loose subviews.
    private var container: NSView?
    
    private let header: HeaderView
    private let body: NSScrollView
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: self.frame.width, height: self.frame.height)
    }
    private var windowHeight: CGFloat?
    private var containerHeight: CGFloat?
    
    init(frame: NSRect, module: ModuleType) {
        self.header = HeaderView(frame: NSRect(
            x: 0,
            y: frame.height - Constants.Popup.headerHeight,
            width: frame.width,
            height: Constants.Popup.headerHeight
        ), module: module)
        self.body = NSScrollView(frame: NSRect(
            x: Constants.Popup.margins,
            y: Constants.Popup.margins,
            width: frame.width - Constants.Popup.margins*2,
            height: frame.height - self.header.frame.height - Constants.Popup.margins*2
        ))
        self.windowHeight = NSScreen.main?.visibleFrame.height
        self.containerHeight = self.body.documentView?.frame.height
        
        self.foreground = NSVisualEffectView(frame: frame)
        // .hudWindow reads as glass; .titlebar is nearly opaque, and the red
        // layer colour it was painted with defeated the material entirely.
        self.foreground.material = .hudWindow
        self.foreground.blendingMode = .behindWindow
        self.foreground.state = .active
        self.foreground.wantsLayer = true
        self.foreground.layer?.cornerRadius = 14
        self.foreground.layer?.masksToBounds = true
        
        self.background = NSView(frame: frame)
        self.background.wantsLayer = true
        self.foreground.addSubview(self.background)
        
        super.init(frame: frame)
        
        self.body.drawsBackground = false
        self.body.translatesAutoresizingMaskIntoConstraints = true
        self.body.borderType = .noBorder
        self.body.hasVerticalScroller = true
        self.body.hasHorizontalScroller = false
        self.body.autohidesScrollers = true
        self.body.horizontalScrollElasticity = .none
        
        if #available(macOS 26.0, *) {
            let container = NSView(frame: frame)
            container.autoresizingMask = [.width, .height]
            container.addSubview(self.header)
            container.addSubview(self.body)

            let glass = NSGlassEffectView(frame: frame)
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = 16
            glass.style = .regular
            glass.contentView = container

            self.addSubview(glass)
            self.glass = glass
            self.container = container
        } else {
            self.addSubview(self.foreground, positioned: .below, relativeTo: .none)
            self.addSubview(self.header)
            self.addSubview(self.body)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayer() {
        // Glass brings its own ground. The fallback needs a wash so text stays
        // legible over a busy desktop -- but a translucent one: solid white was
        // what made the old popups look like flat panels in light mode.
        guard self.glass == nil else { return }
        self.background.layer?.backgroundColor = self.isDarkMode
            ? NSColor.black.withAlphaComponent(0.10).cgColor
            : NSColor.white.withAlphaComponent(0.55).cgColor
    }
    
    fileprivate func setView(_ view: Popup_p?) {
        self.view = view
        
        var isScrollVisible: Bool = false
        var size: NSSize = NSSize(
            width: (view?.frame.width ?? Constants.Popup.width) + (Constants.Popup.margins*2),
            height: (view?.frame.height ?? 0) + Constants.Popup.headerHeight + (Constants.Popup.margins*2)
        )
        
        self.windowHeight = NSScreen.main?.visibleFrame.height // for height recalculate when appear/disappear
        self.containerHeight = self.body.documentView?.frame.height // for scroll diff calculation
        if let screenHeight = NSScreen.main?.visibleFrame.height, size.height > screenHeight {
            size.height = screenHeight - Constants.Widget.height
            isScrollVisible = true
        }
        if let screenWidth = NSScreen.main?.visibleFrame.width, size.width > screenWidth {
            size.width = screenWidth
        }
        
        self.setFrameSize(size)
        self.foreground.setFrameSize(size)
        self.background.setFrameSize(size)
        self.resizeBody(size, scrollVisible: isScrollVisible)
        self.header.setFrameOrigin(NSPoint(x: 0, y: size.height - Constants.Popup.headerHeight))
        
        if let view = view {
            self.body.documentView = view
            view.sizeCallback = { [weak self] size in
                self?.recalculateHeight(size)
            }
        }
    }
    
    fileprivate func setTitle(_ newTitle: String) {
        self.header.setTitle(newTitle)
    }
    
    fileprivate func setCloseButton(_ state: Bool) {
        self.header.setCloseButton(state)
    }
    
    internal func appear() {
        self.view?.appear()
        
        self.display()
        self.body.subviews.first?.display()
        
        if let screenHeight = NSScreen.main?.visibleFrame.height, let size = self.body.documentView?.frame.size {
            if screenHeight != self.windowHeight {
                self.recalculateHeight(size)
            }
        }
        
        if let documentView = self.body.documentView {
            documentView.scroll(NSPoint(x: 0, y: documentView.bounds.size.height))
        }
    }
    internal func disappear() {
        self.header.setCloseButton(false)
        self.view?.disappear()
    }
    
    private func recalculateHeight(_ size: NSSize) {
        var isScrollVisible: Bool = false
        var windowSize: NSSize = NSSize(
            width: size.width + (Constants.Popup.margins*2),
            height: size.height + Constants.Popup.headerHeight + (Constants.Popup.margins*2)
        )
        let h0 = self.containerHeight ?? 0
        
        self.windowHeight = NSScreen.main?.visibleFrame.height // for height recalculate when appear/disappear
        self.containerHeight = self.body.documentView?.frame.height // for scroll diff calculation
        if let screenHeight = NSScreen.main?.visibleFrame.height, windowSize.height > screenHeight {
            windowSize.height = screenHeight - Constants.Widget.height
            isScrollVisible = true
        }
        if let screenWidth = NSScreen.main?.visibleFrame.width, windowSize.width > screenWidth {
            windowSize.width = screenWidth
        }
        
        self.window?.setContentSize(windowSize)
        self.foreground.setFrameSize(windowSize)
        self.background.setFrameSize(windowSize)
        self.glass?.setFrameSize(windowSize)
        self.container?.setFrameSize(windowSize)
        self.resizeBody(windowSize, scrollVisible: isScrollVisible)
        self.header.setFrameOrigin(NSPoint(
            x: self.header.frame.origin.x,
            y: self.body.frame.height + (Constants.Popup.margins*2)
        ))
        
        if let documentView = self.body.documentView {
            let diff = h0 - (self.body.documentView?.frame.height ?? 0)
            documentView.scroll(NSPoint(
                x: 0,
                y: self.body.documentVisibleRect.origin.y - (diff < 0 ? diff : 0)
            ))
        }
    }
    
    private func resizeBody(_ windowSize: NSSize, scrollVisible: Bool) {
        let offset: CGFloat = scrollVisible ? 20 : 0
        let isRTL = self.body.userInterfaceLayoutDirection == .rightToLeft
        self.body.frame = NSRect(
            x: Constants.Popup.margins - (isRTL ? offset : 0),
            y: Constants.Popup.margins,
            width: windowSize.width - (Constants.Popup.margins*2) + offset,
            height: windowSize.height - Constants.Popup.headerHeight - (Constants.Popup.margins*2)
        )
    }
}

internal class HeaderView: NSStackView {
    private var titleView: NSTextField? = nil
    private var activityButton: NSButton?
    private var closeButton: NSButton?
    
    private var title: String = ""
    private var isCloseAction: Bool = false
    private let activityMonitor: URL?
    private let calendar: URL?
    private var module: ModuleType
    
    init(frame: NSRect, module: ModuleType) {
        self.module = module
        self.activityMonitor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor")
        self.calendar = URL(fileURLWithPath: "/System/Applications/Calendar.app")
        
        super.init(frame: CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height))
        
        self.orientation = .horizontal
        self.distribution = .gravityAreas
        self.spacing = 0
        
        let activity = NSButtonWithPadding()
        activity.frame = CGRect(x: 0, y: 0, width: 24, height: self.frame.height)
        activity.horizontalPadding = activity.frame.height - 24
        activity.bezelStyle = .regularSquare
        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.imageScaling = .scaleNone
        activity.contentTintColor = .lightGray
        activity.isBordered = false
        activity.target = self
        activity.focusRingType = .none
        self.activityButton = activity
        self.setupActionButton()
        
        let title = NSTextField(frame: NSRect(x: 0, y: 0, width: frame.width/2, height: 18))
        title.isEditable = false
        title.isSelectable = false
        title.isBezeled = false
        title.wantsLayer = true
        title.textColor = .textColor
        title.backgroundColor = .clear
        title.canDrawSubviewsIntoLayer = true
        title.alignment = .center
        title.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        title.stringValue = ""
        self.titleView = title
        
        // A command glyph for "open module settings" said nothing: ⌘ is a
        // modifier key, not a destination. It is a gear now, and it sits with
        // the other navigation on the left.
        let settings = NSButtonWithPadding()
        settings.frame = CGRect(x: 0, y: 0, width: 24, height: self.frame.height)
        settings.horizontalPadding = 0
        settings.bezelStyle = .regularSquare
        settings.translatesAutoresizingMaskIntoConstraints = false
        settings.imageScaling = .scaleNone
        settings.image = iconFromSymbol(name: "gearshape", scale: .medium)
        settings.contentTintColor = .secondaryLabelColor
        settings.isBordered = false
        settings.action = #selector(self.openSettings)
        settings.target = self
        settings.toolTip = localizedString("Open module")
        settings.focusRingType = .none
        
        let close = NSButtonWithPadding()
        close.frame = CGRect(x: 0, y: 0, width: 24, height: self.frame.height)
        close.horizontalPadding = 0
        close.bezelStyle = .regularSquare
        close.translatesAutoresizingMaskIntoConstraints = false
        close.imageScaling = .scaleNone
        close.image = iconFromSymbol(name: "xmark.circle.fill", scale: .medium)
        close.contentTintColor = .secondaryLabelColor
        close.isBordered = false
        close.action = #selector(self.closePopup)
        close.target = self
        close.toolTip = localizedString("Close")
        close.focusRingType = .none
        close.isHidden = true
        self.closeButton = close
        
        let leading = NSStackView(views: [activity, settings])
        leading.orientation = .horizontal
        leading.spacing = 2
        leading.alignment = .centerY
        leading.translatesAutoresizingMaskIntoConstraints = false
        
        // Same width as the pair on the left, so the title stays centred
        // whether or not the close button is showing.
        let trailing = NSStackView(views: [close])
        trailing.orientation = .horizontal
        trailing.alignment = .centerY
        trailing.distribution = .fillEqually
        trailing.translatesAutoresizingMaskIntoConstraints = false
        
        self.addArrangedSubview(leading)
        self.addArrangedSubview(title)
        self.addArrangedSubview(trailing)
        
        let sideWidth: CGFloat = 52
        NSLayoutConstraint.activate([
            leading.widthAnchor.constraint(equalToConstant: sideWidth),
            trailing.widthAnchor.constraint(equalToConstant: sideWidth),
            title.widthAnchor.constraint(equalToConstant: self.frame.width - (sideWidth*2))
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    fileprivate func setTitle(_ newTitle: String) {
        self.title = newTitle
        self.titleView?.stringValue = localizedString(newTitle)
    }
    
    private func setupActionButton() {
        guard let button = self.activityButton else { return }
        
        self.closeButton?.isHidden = !self.isCloseAction
        
        if self.module == .clock {
            button.action = #selector(self.openCalendar)
            button.image = iconFromSymbol(name: "calendar", scale: .large)
            button.toolTip = localizedString("Open Calendar")
            return
        } else if self.module == .remote {
            button.action = #selector(self.openSystemStats)
            button.image = iconFromSymbol(name: "globe", scale: .large)
            button.toolTip = localizedString("Open System Perch")
            return
        }
        
        button.action = #selector(self.openActivityMonitor)
        // Three static bars said "a chart", not "the system activity monitor",
        // and they read as a widget icon rather than a button that leaves the
        // app. A live-looking trace matches the destination, and matches the
        // gear beside it in weight.
        button.image = iconFromSymbol(name: "chart.line.uptrend.xyaxis", scale: .medium)
        button.toolTip = localizedString("Open Activity Monitor")
    }
    
    @objc func openActivityMonitor() {
        guard let app = self.activityMonitor else { return }
        if let tab = self.module.activityMonitorTab {
            UserDefaults(suiteName: "com.apple.ActivityMonitor")?.set(tab, forKey: "SelectedTab")
        }
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    
    @objc func openCalendar() {
        guard let app = self.calendar else { return }
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    
    @objc func openSystemStats() {
        // Upstream's web app. A fork has no account system to open, so this
        // falls back to the repository -- see Branding.
        guard let url = Branding.remoteServiceHost ?? Branding.repositoryURL else { return }
        NSWorkspace.shared.open(url)
    }
    
    @objc func openSettings() {
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": self.title])
    }
    
    @objc private func closePopup() {
        self.window?.setIsVisible(false)
        self.setCloseButton(false)
        return
    }
    
    fileprivate func setCloseButton(_ state: Bool) {
        guard state != self.isCloseAction else { return }
        self.isCloseAction = state
        self.setupActionButton()
    }
}
