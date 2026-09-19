//
//  Settings.swift
//  Perch
//
//  Created by Serhiy Mytrovtsiy on 12/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import SwiftUI
import Kit

class SettingsWindow: NSWindow, NSWindowDelegate {
    private static let size: CGSize = CGSize(width: 720, height: 480)
    private static let frameAutosaveName = "com.sagar.perch.Settings.WindowFrame"
    
    internal var onClose: (() -> Void)?
    
    private let model = SettingsModel()
    
    private var dashboard: NSView = Dashboard()
    private var settings: ApplicationSettings = ApplicationSettings()
    
    private var activeModuleName: String? = nil
    
    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsWindow.size.width,
                height: SettingsWindow.size.height
            ),
            styleMask: [.closable, .titled, .miniaturizable, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // NavigationSplitView brings its own sidebar material, selection and
        // toolbar, so the window no longer needs an NSSplitViewController or an
        // NSToolbar delegate of its own.
        self.contentViewController = NSHostingController(
            rootView: SettingsShellView(model: self.model))
        self.titlebarAppearsTransparent = true
        // Non-opaque so the glass behind the content actually composites; a
        // titled window is opaque by default and paints over it.
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isRestorable = true
        self.isReleasedWhenClosed = false
        self.delegate = self
        self.setFrameAutosaveName(SettingsWindow.frameAutosaveName)
        if !self.setFrameUsingName(SettingsWindow.frameAutosaveName) {
            self.positionCenter()
        }
        self.setIsVisible(false)
        self.minSize = NSSize(width: SettingsWindow.size.width, height: SettingsWindow.size.height-Constants.Popup.headerHeight)
        
        let windowController = NSWindowController()
        windowController.window = self
        windowController.loadWindow()
        
        // .toggleModule is the model's business now -- it owns the switch
        // states the shell draws.
        NotificationCenter.default.addObserver(self, selector: #selector(menuCallback), name: .openModuleSettings, object: nil)
        
        self.openModule("Dashboard")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .openModuleSettings, object: nil)
    }
    
    func windowWillClose(_ notification: Notification) {
        let onClose = self.onClose
        DispatchQueue.main.async {
            onClose?()
        }
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == NSEvent.EventType.keyDown && event.modifierFlags.contains(.command) {
            if event.keyCode == 12 || event.keyCode == 13 {
                self.close()
                return true
            } else if event.keyCode == 46 {
                self.miniaturize(event)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func mouseUp(with: NSEvent) {
        NotificationCenter.default.post(name: .clickInSettings, object: nil, userInfo: nil)
    }
    
    internal func open(module: String? = nil) {
        if !self.isVisible {
            self.setIsVisible(true)
            self.makeKeyAndOrderFront(nil)
        }
        if !self.isKeyWindow {
            self.orderFrontRegardless()
        }
        
        if var name = module {
            if name == "Combined modules" { name = "Dashboard" }
            self.openModule(name)
        }
    }
    
    @objc private func menuCallback(_ notification: Notification) {
        guard let title = notification.userInfo?["module"] as? String else { return }
        self.openModule(title)
    }
    
    /// Resolves a name to the view that shows it and hands it to the shell.
    private func openModule(_ title: String) {
        var view: NSView = NSView()
        
        if let detectedModule = modules.first(where: { $0.config.name == title }) {
            if let v = detectedModule.window { view = v }
            self.activeModuleName = detectedModule.config.name
            self.model.moduleStates[detectedModule.config.name] = detectedModule.enabled
            NotificationCenter.default.post(name: .openWindow, object: nil, userInfo: ["module": detectedModule.config.name, "state": true])
        } else if title == "Dashboard" {
            view = self.dashboard
            self.activeModuleName = nil
            NotificationCenter.default.post(name: .openWindow, object: nil, userInfo: ["state": false])
        } else if title == "Settings" {
            self.settings.viewWillAppear()
            view = self.settings
            self.activeModuleName = nil
            NotificationCenter.default.post(name: .openWindow, object: nil, userInfo: ["state": false])
        } else {
            return
        }
        
        self.title = localizedString(title)
        self.model.selection = title
        self.model.detail = view
    }
    
    private func positionCenter() {
        guard let screen = NSScreen.main else {
            self.center()
            return
        }
        self.setFrameOrigin(NSPoint(
            x: (screen.frame.width - SettingsWindow.size.width)/2,
            y: ((screen.frame.height - SettingsWindow.size.height)/1.75)
        ))
    }
}
