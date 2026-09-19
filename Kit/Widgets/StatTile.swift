//
//  StatTile.swift
//  Kit
//
//  A headline figure with a thin meter beneath it, replacing the dials that
//  used to head the CPU and memory popups.
//
//  Why the dials went:
//
//  - The memory pressure gauge was a rainbow arc with a needle. A hue ramp
//    through green, yellow and red is the one thing a magnitude encoding must
//    never be, and the whole speedometer existed to render one of three words.
//    A word in a coloured pill says it in a tenth of the space.
//  - The donuts encoded a single percentage as an arc. An arc is read by angle,
//    which people are measurably bad at; a number is exact and a linear meter
//    is comparable at a glance. The temperature ring was worse -- an arc with
//    no scale behind it, so 53 degrees filled an arbitrary fraction.
//  - The memory donut carried both the App/Wired/Compressed breakdown and the
//    total in one ring, so one mark meant two things. The breakdown already has
//    a stacked bar of its own further down the popup, which is where a
//    part-to-whole belongs.
//

import Cocoa

/// A figure, its caption, and a meter showing where it sits in its range.
public class StatTileView: NSView {

    private let valueField: NSTextField
    private let captionField: NSTextField
    private let track: NSView
    private let fill: NSView

    private var fraction: CGFloat = 0
    private var color: NSColor = .controlAccentColor

    /// Meter geometry: thin, with rounded data ends anchored to the track.
    private let meterHeight: CGFloat = 5

    public init(caption: String) {
        self.valueField = NSTextField(labelWithString: "—")
        self.captionField = NSTextField(labelWithString: caption.uppercased())
        self.track = NSView()
        self.fill = NSView()

        super.init(frame: .zero)

        self.translatesAutoresizingMaskIntoConstraints = false

        // Monospaced digits: these figures change every second, and a
        // proportional font shifts the whole tile as the digits change.
        self.valueField.font = .monospacedDigitSystemFont(ofSize: 24, weight: .regular)
        self.valueField.textColor = .labelColor
        self.valueField.alignment = .center
        self.valueField.translatesAutoresizingMaskIntoConstraints = false

        self.captionField.attributedStringValue = NSAttributedString(
            string: caption.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
                .kern: 1.1
            ])
        self.captionField.alignment = .center
        self.captionField.translatesAutoresizingMaskIntoConstraints = false

        self.track.wantsLayer = true
        self.track.layer?.cornerRadius = meterHeight/2
        self.track.translatesAutoresizingMaskIntoConstraints = false

        self.fill.wantsLayer = true
        self.fill.layer?.cornerRadius = meterHeight/2
        self.fill.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(self.captionField)
        self.addSubview(self.valueField)
        self.addSubview(self.track)
        self.track.addSubview(self.fill)

        NSLayoutConstraint.activate([
            captionField.topAnchor.constraint(equalTo: topAnchor),
            captionField.leadingAnchor.constraint(equalTo: leadingAnchor),
            captionField.trailingAnchor.constraint(equalTo: trailingAnchor),

            valueField.topAnchor.constraint(equalTo: captionField.bottomAnchor, constant: 2),
            valueField.leadingAnchor.constraint(equalTo: leadingAnchor),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor),

            track.topAnchor.constraint(equalTo: valueField.bottomAnchor, constant: 6),
            track.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            track.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            track.heightAnchor.constraint(equalToConstant: meterHeight),

            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor)
        ])

        self.fillWidth = fill.widthAnchor.constraint(equalToConstant: 0)
        self.fillWidth?.isActive = true
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var fillWidth: NSLayoutConstraint?

    public override func updateLayer() {
        self.track.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        self.fill.layer?.backgroundColor = self.color.cgColor
    }

    public override func layout() {
        super.layout()
        self.fillWidth?.constant = max(0, self.track.bounds.width * self.fraction)
    }

    /// `fraction` positions the meter; pass nil for a figure with no natural
    /// range (a temperature), which hides the meter rather than inventing one.
    public func set(value: String, fraction: Double?, color: NSColor) {
        self.valueField.stringValue = value
        self.color = color

        if let fraction {
            self.fraction = CGFloat(min(max(fraction, 0), 1))
            self.track.isHidden = false
        } else {
            self.fraction = 0
            self.track.isHidden = true
        }

        self.fillWidth?.constant = max(0, self.track.bounds.width * self.fraction)
        self.needsLayout = true
        self.needsDisplay = true
        self.updateLayer()
    }
}

/// A word in a tinted capsule: the replacement for the pressure needle.
public class StatPillView: NSView {

    private let captionField: NSTextField
    private let pill: NSTextField
    private var tint: NSColor = .systemGreen

    public init(caption: String) {
        self.captionField = NSTextField(labelWithString: caption.uppercased())
        self.pill = NSTextField(labelWithString: "—")

        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false

        self.captionField.attributedStringValue = NSAttributedString(
            string: caption.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
                .kern: 1.1
            ])
        self.captionField.alignment = .center
        self.captionField.translatesAutoresizingMaskIntoConstraints = false

        self.pill.font = .systemFont(ofSize: 13, weight: .semibold)
        self.pill.alignment = .center
        self.pill.wantsLayer = true
        self.pill.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(self.captionField)
        self.addSubview(self.pill)

        NSLayoutConstraint.activate([
            captionField.topAnchor.constraint(equalTo: topAnchor),
            captionField.leadingAnchor.constraint(equalTo: leadingAnchor),
            captionField.trailingAnchor.constraint(equalTo: trailingAnchor),

            pill.centerXAnchor.constraint(equalTo: centerXAnchor),
            pill.topAnchor.constraint(equalTo: captionField.bottomAnchor, constant: 8),
            pill.heightAnchor.constraint(equalToConstant: 24),
            pill.widthAnchor.constraint(greaterThanOrEqualTo: pill.heightAnchor, multiplier: 2.4)
        ])
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func updateLayer() {
        self.pill.layer?.cornerRadius = 12
        self.pill.backgroundColor = self.tint.withAlphaComponent(0.16)
        self.pill.textColor = self.tint
    }

    public func set(text: String, color: NSColor) {
        self.pill.stringValue = text
        self.tint = color
        self.updateLayer()
    }
}
