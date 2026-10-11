//
//  HUDVolumeSlider.swift
//
//  The Tahoe HUD's volume slider: a SwiftUI Slider set up like the slider in the
//  system volume HUD, usable from Objective-C.
//

import AppKit
import SwiftUI

@objc(HUDVolumeSlider)
public final class HUDVolumeSlider: NSView {

    /// The slider position, 0.0–1.0. Setting it does not call `onValueChanged`.
    @objc public var doubleValue: Double {
        get { model.value }
        set { model.value = min(max(newValue, 0), 1) }
    }

    /// Called with the new value on every change the user makes.
    @objc public var onValueChanged: ((Double) -> Void)?

    /// Called when the user releases the slider.
    @objc public var onEditingEnded: (() -> Void)?

    private let model = HUDVolumeSliderModel()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        guard #available(macOS 26.0, *) else { return }
        let content = HUDVolumeSliderContent(
            model: model,
            onValueChanged: { [weak self] value in self?.onValueChanged?(value) },
            onEditingChanged: { [weak self] editing in if !editing { self?.onEditingEnded?() } })
        let hosting = FirstMouseHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

@Observable
final class HUDVolumeSliderModel {
    var value: Double = 0.6
}

/// Takes the first click, so the slider can be dragged while the HUD panel is not key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// ControlCenter builds the system volume HUD's slider with
/// Slider(value:in:...minimumValueLabel:maximumValueLabel:ticks:), the labels
/// speaker.fill and speaker.wave.3.fill, 17 ticks at 0, 1/16, ..., 1, and the
/// modifiers controlSize(.small), sliderTintProminence(.primary), a white tint and
/// sliderThumbVisibility (checked on macOS 27.0.1). sliderTintProminence is not in
/// the SDK, so it is left out.
@available(macOS 26.0, *)
private struct HUDVolumeSliderContent: View {
    let model: HUDVolumeSliderModel
    let onValueChanged: (Double) -> Void
    let onEditingChanged: (Bool) -> Void

    @State private var hovering = false

    private static let ticks: [Double] = Array(stride(from: 0.0, through: 1.0, by: 1.0 / 16))

    var body: some View {
        Slider(
            value: Binding(get: { model.value },
                           set: { model.value = $0; onValueChanged($0) }),
            in: 0...1,
            label: { EmptyView() },
            minimumValueLabel: { Image(systemName: "speaker.fill") },
            maximumValueLabel: { Image(systemName: "speaker.wave.3.fill") },
            ticks: { SliderTickContentForEach(Self.ticks, id: \.self) { SliderTick($0) } },
            onEditingChanged: onEditingChanged)
        .accessibilityLabel("Volume")
        .controlSize(.small)
        .tint(.white)
        // The previous slider showed its knob only while the pointer was over it.
        .sliderThumbVisibility(hovering ? .visible : .hidden)
        .onHover { hovering = $0 }
    }
}
