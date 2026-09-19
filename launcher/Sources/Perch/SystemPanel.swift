import AppKit

/// Charts and rows for the menu's system block, laid out the way Stats lays
/// out its popup: label left, value right, a chart on a translucent rounded
/// tile, and the two network directions mirrored around a centre line.
///
/// This is an NSMenuItem.view rather than a set of menu rows because menu rows
/// can only be text plus an icon -- the old version padded format strings to
/// fake a value column and put the chart in the icon slot. A view gets real
/// columns (NSGridView) and charts at a size worth looking at.

/// A filled line chart, for one series.
class ChartView: NSView {

    var values: [Double] = [] { didSet { needsDisplay = true } }
    /// Fixed top of the scale -- 100 for a percentage. nil scales to the data.
    var ceiling: Double?
    var color: NSColor

    init(width: CGFloat, height: CGFloat, color: NSColor, ceiling: Double? = nil) {
        self.color = color
        self.ceiling = ceiling
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: height),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The tile under every chart, so an idle graph still reads as a graph
    /// rather than as empty space.
    func drawGround() {
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawGround()
        guard values.count > 1 else { return }

        let top = Swift.max(ceiling ?? values.max() ?? 1, 0.0001)
        let area = bounds.insetBy(dx: 2, dy: 2)
        let step = area.width / CGFloat(values.count - 1)

        func point(_ index: Int) -> NSPoint {
            let fraction = Swift.min(Swift.max(values[index] / top, 0), 1)
            return NSPoint(x: area.minX + CGFloat(index) * step,
                           y: area.minY + CGFloat(fraction) * area.height)
        }

        let fill = NSBezierPath()
        fill.move(to: NSPoint(x: area.minX, y: area.minY))
        for index in values.indices { fill.line(to: point(index)) }
        fill.line(to: NSPoint(x: area.maxX, y: area.minY))
        fill.close()
        color.withAlphaComponent(0.25).setFill()
        fill.fill()

        let line = NSBezierPath()
        line.lineWidth = 1.2
        line.lineJoinStyle = .round
        line.move(to: point(0))
        for index in values.indices.dropFirst() { line.line(to: point(index)) }
        color.setStroke()
        line.stroke()
    }
}

/// Download above the line, upload below it, both on one scale so the halves
/// are worth comparing. This is Stats' network chart.
final class NetworkChartView: ChartView {

    var download: [Double] = [] { didSet { needsDisplay = true } }
    var upload: [Double] = [] { didSet { needsDisplay = true } }
    var uploadColor: NSColor = .seriesAmber

    override func draw(_ dirtyRect: NSRect) {
        drawGround()

        let area = bounds.insetBy(dx: 2, dy: 2)
        let middle = area.midY

        NSColor.separatorColor.setFill()
        NSBezierPath(rect: NSRect(x: area.minX, y: middle, width: area.width, height: 1)).fill()

        // A shared ceiling, floored at 64 KB/s so an idle link does not
        // magnify a few stray bytes into a mountain range.
        let peak = Swift.max(download.max() ?? 0, upload.max() ?? 0, 64 * 1024)

        func series(_ values: [Double], _ tint: NSColor, up: Bool) {
            guard values.count > 1 else { return }
            let step = area.width / CGFloat(values.count - 1)
            let reach = area.height / 2 - 1

            func point(_ index: Int) -> NSPoint {
                let fraction = Swift.min(Swift.max(values[index] / peak, 0), 1)
                let offset = CGFloat(fraction) * reach
                return NSPoint(x: area.minX + CGFloat(index) * step,
                               y: up ? middle + offset : middle - offset)
            }

            let fill = NSBezierPath()
            fill.move(to: NSPoint(x: area.minX, y: middle))
            for index in values.indices { fill.line(to: point(index)) }
            fill.line(to: NSPoint(x: area.maxX, y: middle))
            fill.close()
            tint.withAlphaComponent(0.25).setFill()
            fill.fill()

            let line = NSBezierPath()
            line.lineWidth = 1.2
            line.lineJoinStyle = .round
            line.move(to: point(0))
            for index in values.indices.dropFirst() { line.line(to: point(index)) }
            tint.setStroke()
            line.stroke()
        }

        series(download, color, up: true)
        series(upload, uploadColor, up: false)
    }
}

/// A flat block of colour: the chip Stats puts beside a named series, and the
/// hairlines either side of a section title.
///
/// The colour is re-resolved in updateLayer rather than set once in init,
/// because a CGColor is a fixed value -- bake systemBlue or separatorColor
/// into a layer at init and it keeps the light-mode shade after the user
/// switches to dark.
private final class FillView: NSView {
    private let color: NSColor
    private let radius: CGFloat

    init(_ color: NSColor, size: NSSize? = nil, radius: CGFloat = 0) {
        self.color = color
        self.radius = radius
        super.init(frame: NSRect(origin: .zero, size: size ?? .zero))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        if let size {
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: size.width),
                heightAnchor.constraint(equalToConstant: size.height),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = radius
    }
}

/// CPU, memory, network, disk, battery and temperature as one aligned block.
final class SystemPanelView: NSView {

    private let cpuValue = SystemPanelView.value()
    private let memoryValue = SystemPanelView.value()
    private let downloadValue = SystemPanelView.value()
    private let uploadValue = SystemPanelView.value()
    private let diskValue = SystemPanelView.value()
    private let batteryValue = SystemPanelView.value()
    private let temperatureValue = SystemPanelView.value()

    private let cpuChart = ChartView(width: 96, height: 20, color: .systemBlue, ceiling: 100)
    private let memoryChart = ChartView(width: 96, height: 20, color: .systemGreen, ceiling: 100)
    private let networkChart = NetworkChartView(width: 96, height: 46, color: .systemIndigo)

    private var diskRow: NSGridRow?
    private var batteryRow: NSGridRow?
    private var temperatureRow: NSGridRow?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let grid = NSGridView(views: [
            [Self.label("CPU"), cpuValue, cpuChart],
            [Self.label("Memory"), memoryValue, memoryChart],
            [Self.series("Download", .systemIndigo, "arrow.down"), downloadValue, networkChart],
            [Self.series("Upload", .seriesAmber, "arrow.up"), uploadValue],
            [Self.label("Disk"), diskValue],
            [Self.label("Battery"), batteryValue],
            [Self.label("Temp"), temperatureValue],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 5
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .trailing
        grid.column(at: 2).xPlacement = .trailing
        grid.column(at: 0).width = 74

        // One chart standing beside both network rows, which is what makes the
        // pair read as one thing rather than two unrelated numbers.
        grid.mergeCells(inHorizontalRange: NSRange(location: 2, length: 1),
                        verticalRange: NSRange(location: 2, length: 2))
        // No chart for these three, so let the value have the whole width --
        // "412 GB of 994 GB  (41%)" does not fit in a value column.
        for row in 4...6 {
            grid.mergeCells(inHorizontalRange: NSRange(location: 1, length: 2),
                            verticalRange: NSRange(location: row, length: 1))
        }
        diskRow = grid.row(at: 4)
        batteryRow = grid.row(at: 5)
        temperatureRow = grid.row(at: 6)

        let header = Self.header("System")
        addSubview(header)
        addSubview(grid)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            grid.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        refresh(full: true)
        layoutSubtreeIfNeeded()
        // A menu sizes a hosted view from its frame, not its constraints.
        setFrameSize(fittingSize)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Pieces

    private static func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 12)
        field.textColor = .secondaryLabelColor
        return field
    }

    /// A label with its chart's colour beside it, so the two network rows say
    /// which line in the graph is theirs.
    private static func series(_ text: String, _ color: NSColor, _ direction: String? = nil) -> NSView {
        let marker: NSView
        if let direction,
           let glyph = NSImage(systemSymbolName: direction, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold)) {
            // Direction beats colour memory: an arrow says which way the bytes
            // went without the reader consulting a legend.
            let image = NSImageView(image: glyph)
            image.contentTintColor = color
            image.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                image.widthAnchor.constraint(equalToConstant: 9),
                image.heightAnchor.constraint(equalToConstant: 10),
            ])
            marker = image
        } else {
            marker = FillView(color, size: NSSize(width: 8, height: 8), radius: 2)
        }
        let stack = NSStackView(views: [marker, label(text)])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        return stack
    }

    private static func value() -> NSTextField {
        let field = NSTextField(labelWithString: "—")
        // Monospaced digits so a changing number does not jitter the column.
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.alignment = .right
        return field
    }

    /// Small caps between two hairlines -- Stats' section separator.
    private static func header(_ text: String) -> NSView {
        let title = NSTextField(labelWithString: "")
        title.attributedStringValue = NSAttributedString(string: text.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .kern: 1.0,
        ])
        title.translatesAutoresizingMaskIntoConstraints = false

        func rule() -> NSView {
            let line = FillView(.separatorColor)
            line.heightAnchor.constraint(equalToConstant: 1).isActive = true
            return line
        }

        let left = rule(), right = rule()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(left)
        container.addSubview(title)
        container.addSubview(right)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 14),
            title.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            left.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            left.trailingAnchor.constraint(equalTo: title.leadingAnchor, constant: -8),
            left.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            right.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
            right.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            right.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    // MARK: - Values

    /// `full` also re-reads disk and battery, which are a statfs and an
    /// IOKit walk -- worth doing when the menu opens, not four times a minute
    /// while it sits there.
    func refresh(full: Bool) {
        let monitor = Monitor.shared

        cpuValue.stringValue = String(format: "%.1f%%", monitor.latest.cpu)
        memoryValue.stringValue = String(format: "%.1f%%", monitor.latest.memory)
        downloadValue.stringValue = SystemStats.rate(monitor.latest.rx)
        uploadValue.stringValue = SystemStats.rate(monitor.latest.tx)

        cpuChart.values = monitor.cpuHistory
        memoryChart.values = monitor.memoryHistory
        networkChart.download = monitor.rxHistory
        networkChart.upload = monitor.txHistory

        if let temperature = monitor.latest.temperature ?? Temperature.cpu() {
            var text = String(format: "%.0f° CPU", temperature)
            if let ssd = Temperature.storage() { text += String(format: "   %.0f° SSD", ssd) }
            temperatureValue.stringValue = text
            temperatureRow?.isHidden = false
        } else {
            temperatureRow?.isHidden = true
        }

        guard full else { return }

        if let disk = SystemStats.disk() {
            diskValue.stringValue = String(format: "%@ of %@  (%.0f%%)",
                                           SystemStats.bytes(disk.used),
                                           SystemStats.bytes(disk.total),
                                           disk.percent)
            diskRow?.isHidden = false
        } else {
            diskRow?.isHidden = true
        }

        if let battery = SystemStats.battery() {
            var text = String(format: "%.0f%%", battery.percent)
            if battery.charging {
                text += "  charging"
            } else if let minutes = battery.timeToEmpty {
                text += String(format: "  %d:%02d left", minutes / 60, minutes % 60)
            }
            batteryValue.stringValue = text
            batteryRow?.isHidden = false
        } else {
            batteryRow?.isHidden = true
        }

        setFrameSize(fittingSize)
    }
}
