//
//  popup.swift
//  GPU
//
//  Created by Serhiy Mytrovtsiy on 17/08/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private let dashboardHeight: CGFloat = 90
    private let chartHeight: CGFloat = 90 + Constants.Popup.separatorHeight
    private let detailsHeight: CGFloat = (22*7) + Constants.Popup.separatorHeight
    
    private let loadCache = PopupCache<GPU_Info>()
    
    private var usageTile: StatTileView? = nil
    private var renderTile: StatTileView? = nil
    private var tilerTile: StatTileView? = nil
    
    private var chart: LineChartView? = nil
    private var lineChartHistory: Int = 180
    private var lineChartScale: Scale = .none
    private var lineChartFixedScale: Double = 1
    
    private var modelField: NSTextField? = nil
    private var coresField: NSTextField? = nil
    private var utilizationField: NSTextField? = nil
    private var renderField: NSTextField? = nil
    private var tilerField: NSTextField? = nil
    private var aneField: NSTextField? = nil
    private var fpsField: NSTextField? = nil
    
    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        
        self.orientation = .vertical
        self.distribution = .fill
        self.spacing = 0
        
        self.addArrangedSubview(self.initDashboard())
        self.addArrangedSubview(self.initChart())
        self.addArrangedSubview(self.initDetails())
        
        self.recalculateHeight()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func updateLayer() {
        self.chart?.display()
    }
    
    public override func appear() {
        self.replay(self.loadCache, render: self.renderLoad)
    }
    
    private func recalculateHeight() {
        let h = self.arrangedSubviews.map({ $0.bounds.height + self.spacing }).reduce(0, +) - self.spacing
        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }
    
    private func initDashboard() -> NSView {
        // Tiles, matching CPU and memory. Three arcs read by angle said the
        // same thing three times in a form nobody can measure by eye; the
        // figures carry it, and the meters make them comparable.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.dashboardHeight))
        container.heightAnchor.constraint(equalToConstant: self.dashboardHeight).isActive = true

        let row = NSStackView(frame: container.bounds)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = Constants.Popup.spacing
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 4, right: 0)

        let usage = StatTileView(caption: localizedString("GPU utilization"))
        usage.toolTip = localizedString("GPU utilization")
        self.usageTile = usage

        let render = StatTileView(caption: localizedString("Render utilization"))
        render.toolTip = localizedString("Render utilization")
        self.renderTile = render

        let tiler = StatTileView(caption: localizedString("Tiler utilization"))
        tiler.toolTip = localizedString("Tiler utilization")
        self.tilerTile = tiler

        row.addArrangedSubview(usage)
        row.addArrangedSubview(render)
        row.addArrangedSubview(tiler)

        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }
    
    private func initChart() -> NSView  {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.chartHeight))
        view.heightAnchor.constraint(equalToConstant: 90 + Constants.Popup.separatorHeight).isActive = true
        let separator = separatorView(localizedString("Usage history"), origin: NSPoint(x: 0, y: self.chartHeight-Constants.Popup.separatorHeight), width: self.frame.width)
        let container: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: separator.frame.origin.y))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
        container.layer?.cornerRadius = Constants.Popup.radius
        
        let chartFrame = NSRect(x: 1, y: 0, width: view.frame.width - 2, height: container.frame.height)
        self.chart = LineChartView(frame: chartFrame, num: self.lineChartHistory, scale: self.lineChartScale, fixedScale: self.lineChartFixedScale)
        container.addSubview(self.chart!)
        
        view.addSubview(separator)
        view.addSubview(container)
        
        return view
    }
    
    private func initDetails() -> NSView  {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.detailsHeight))
        let separator = separatorView(localizedString("Details"), origin: NSPoint(x: 0, y: self.detailsHeight-Constants.Popup.separatorHeight), width: self.frame.width)
        let container: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: separator.frame.origin.y))
        container.orientation = .vertical
        container.spacing = 0
        
        self.modelField = popupRow(container, title: "\(localizedString("Model")):", value: "").1
        self.coresField = popupRow(container, title: "\(localizedString("Cores")):", value: localizedString("Unknown")).1
        self.utilizationField = popupRow(container, title: "\(localizedString("Utilization")):", value: "").1
        self.renderField = popupRow(container, title: "\(localizedString("Render utilization")):", value: "").1
        self.tilerField = popupRow(container, title: "\(localizedString("Tiler utilization")):", value: "").1
        self.aneField = popupRow(container, title: "\(localizedString("ANE utilization")):", value: "").1
        self.fpsField = popupRow(container, title: "\("FPS"):", value: "").1
        
        view.addSubview(separator)
        view.addSubview(container)
        
        return view
    }
    
    // MARK: - Callback
    
    public func loadCallback(_ value: GPU_Info) {
        self.apply(value, to: self.loadCache, render: self.renderLoad)
        if let utilization = value.utilization {
            self.chart?.addValue(utilization)
        }
    }
    
    private func renderLoad(_ value: GPU_Info) {
        self.modelField?.stringValue = value.model
        
        if let cores = value.cores {
            self.coresField?.stringValue = "\(cores)"
        }
        
        if let utilization = value.utilization {
            self.usageTile?.set(value: "\(Int(utilization.rounded(toPlaces: 2) * 100))%",
                              fraction: utilization,
                              color: utilization.usageColor())
            self.usageTile?.toolTip = "\(localizedString("GPU utilization")): \(Int(utilization.rounded(toPlaces: 2) * 100))%"
            self.utilizationField?.stringValue = "\(Int(utilization*100))%"
        }
        if let utilization = value.renderUtilization {
            self.renderTile?.set(value: "\(Int(utilization.rounded(toPlaces: 2) * 100))%",
                              fraction: utilization,
                              color: utilization.usageColor())
            self.renderTile?.toolTip = "\(localizedString("Render utilization")): \(Int(utilization.rounded(toPlaces: 2) * 100))%"
            self.renderField?.stringValue = "\(Int(utilization*100))%"
        }
        if let utilization = value.tilerUtilization {
            self.tilerTile?.set(value: "\(Int(utilization.rounded(toPlaces: 2) * 100))%",
                              fraction: utilization,
                              color: utilization.usageColor())
            self.tilerTile?.toolTip = "\(localizedString("Tiler utilization")): \(Int(utilization.rounded(toPlaces: 2) * 100))%"
            self.tilerField?.stringValue = "\(Int(utilization*100))%"
        }
        if let utilization = value.aneUtilization {
            self.aneField?.stringValue = "\(Int(utilization*100))%"
        }
        if let fps = value.fps {
            self.fpsField?.stringValue = "\(Int(fps.rounded()))"
        }
        
        self.chart?.display()
    }
    
    // MARK: - Settings
    
    public override func settings() -> NSView? {
        let view = SettingsContainerView()
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Keyboard shortcut"), component: KeyboardShartcutView(
                callback: self.setKeyboardShortcut,
                value: self.keyboardShortcut
            ))
        ]))
        
        return view
    }
}
