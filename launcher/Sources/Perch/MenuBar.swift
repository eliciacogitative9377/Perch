import AppKit

/// The metrics drawn straight into the menu bar, the way Stats draws its
/// widgets: a small label over a larger value, and network speed as two
/// stacked rates with a colour chip each.
///
/// Stats gives every widget its own NSStatusItem so each can be dragged
/// independently (Kit/module/widget.swift). Perch has one status item and one
/// menu, so all of the cells are drawn in a single view instead: less menu bar
/// space, one click target, and no per-widget position to remember.
final class MenuBarView: NSView {

    enum Cell {
        /// A label over a value: "CPU" / "28%".
        case stat(label: String, value: String)
        /// Upload over download, each with its colour chip.
        case speed(up: String, down: String)
    }

    var cells: [Cell] = [] {
        didSet { needsDisplay = true }
    }

    private let edge: CGFloat = 3        // breathing room at each end
    private let gap: CGFloat = 9         // between cells
    private let chip: CGFloat = 5
    private let chipGap: CGFloat = 3

    private let labelFont = NSFont.systemFont(ofSize: 8, weight: .regular)
    private let valueFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    // Monospaced digits: a rate that ticks between 9 and 10 MB/s would
    // otherwise resize the status item several times a second.
    private let speedFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)

    private let uploadColor = NSColor.seriesAmber
    private let downloadColor = NSColor.systemIndigo

    // MARK: - Measuring

    private func width(of cell: Cell) -> CGFloat {
        switch cell {
        case let .stat(label, value):
            return max(text(label, labelFont).size().width,
                       text(value, valueFont).size().width)
        case let .speed(up, down):
            let widest = max(text(up, speedFont).size().width,
                             text(down, speedFont).size().width)
            return chip + chipGap + widest
        }
    }

    /// What the status item's length has to be for everything to fit.
    var fittingWidth: CGFloat {
        guard !cells.isEmpty else { return 0 }
        let content = cells.map(width(of:)).reduce(0, +)
        return ceil(edge * 2 + content + gap * CGFloat(cells.count - 1))
    }

    // MARK: - Drawing

    private func text(_ string: String, _ font: NSFont,
                      color: NSColor = .labelColor,
                      alignment: NSTextAlignment = .center) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        return NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        var x = edge
        for cell in cells {
            let cellWidth = width(of: cell)
            draw(cell, in: NSRect(x: x, y: 0, width: cellWidth, height: bounds.height))
            x += cellWidth + gap
        }
    }

    private func draw(_ cell: Cell, in rect: NSRect) {
        // Two stacked lines inside a 22pt bar, the proportions Stats uses:
        // the label rides high and small, the value sits on the baseline.
        switch cell {
        case let .stat(label, value):
            text(label, labelFont, color: .labelColor.withAlphaComponent(0.75))
                .draw(in: NSRect(x: rect.minX, y: rect.height - 10, width: rect.width, height: 9))
            text(value, valueFont)
                .draw(in: NSRect(x: rect.minX, y: 0, width: rect.width, height: 13))

        case let .speed(up, down):
            func row(_ value: String, _ color: NSColor, _ direction: String, y: CGFloat) {
                // An arrow, not a chip: at menu bar size the direction is the
                // whole point, and two coloured squares make the reader
                // remember which colour was which.
                let box = NSRect(x: rect.minX, y: y + 1, width: chip + 2, height: chip + 2)
                if let glyph = NSImage(systemSymbolName: direction, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 8, weight: .bold)) {
                    glyph.isTemplate = true
                    let tinted = NSImage(size: box.size, flipped: false) { _ in
                        color.set()
                        glyph.draw(in: NSRect(origin: .zero, size: box.size),
                                   from: .zero, operation: .sourceOver, fraction: 1)
                        NSRect(origin: .zero, size: box.size).fill(using: .sourceAtop)
                        return true
                    }
                    tinted.draw(in: box)
                }
                text(value, speedFont, alignment: .right)
                    .draw(in: NSRect(x: rect.minX + chip + chipGap, y: y,
                                     width: rect.width - chip - chipGap, height: 10))
            }
            row(up, uploadColor, "arrow.up", y: rect.height - 11)
            row(down, downloadColor, "arrow.down", y: 0)
        }
    }

    /// The status item's button owns the click -- it is what opens the menu.
    /// Without this the view would swallow mouse events and the menu would
    /// stop dropping down.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The outbound series colour, matching the app's Network module: red is what
/// a failure is painted with, so it should not also mean "upload". Validated
/// for lightness and colour-blind separation against the inbound blue.
extension NSColor {
    static let seriesAmber = NSColor(red: 0xCE/255, green: 0x7C/255, blue: 0x00/255, alpha: 1)
}
