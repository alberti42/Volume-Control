//
//  LiquidGlassView.swift
//
//  Created by Andrea Alberti on 25.10.25.
//
//  A native glass host view (macOS 26+) with graceful fallback,
//  usable from Objective-C and SwiftUI.
//

import AppKit
import QuartzCore
import SwiftUI

@objc(LiquidGlassView)
public final class LiquidGlassView: NSView {

    // MARK: - Public API (Objective-C visible)

    /// Where your content goes. Replaces any previous content.
    @objc public var contentView: NSView? {
        get { contentHost.subviews.first }
        set {
            contentHost.subviews.forEach { $0.removeFromSuperview() }
            guard let v = newValue else { return }
            v.translatesAutoresizingMaskIntoConstraints = false
            contentHost.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
                v.topAnchor.constraint(equalTo: contentHost.topAnchor),
                v.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor)
            ])
        }
    }

    /// Corner radius applied to the glass.
    @objc public var cornerRadius: CGFloat = 14 {
        didSet { applyCornerRadius() }
    }

    /// Tint color for the glass (native on 26+, fallback paints a faint layer color).
    @objc public var tintColor: NSColor? {
        didSet { applyTint() }
    }

    /// NSGlassEffectView.Style (0 = Regular, 1 = Clear). Ignored on fallback.
    @objc public var style: Int = 1 { // default Clear
        didSet { applyStyle() }
    }

    /// Convenience builder
    @objc public class func glass(withStyle style: Int, cornerRadius: CGFloat, tintColor: NSColor?) -> LiquidGlassView {
        let v = LiquidGlassView(frame: .zero)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.style = style
        v.cornerRadius = cornerRadius
        v.tintColor = tintColor
        return v
    }

    // MARK: Optional private Tahoe knobs (no-ops if unavailable)

    /// 0..N variants
    @objc public func setVariantIfAvailable(_ variant: Int) {
        setPrivate("_variant", value: variant)
    }

    /// 0/1
    @objc public func setScrimStateIfAvailable(_ state: Int) {
        setPrivate("_scrimState", value: state)
    }

    /// 0/1
    @objc public func setSubduedStateIfAvailable(_ state: Int) {
        setPrivate("_subduedState", value: state)
    }

    /// SwiftUI-like post-processing (applies CIFilters to the layer).
    /// Use sparingly; native glass already blurs/tints appropriately.
    @objc public func applyVisualAdjustments(saturation: CGFloat = 1.0,
                                             brightness: CGFloat = 0.0,
                                             blur: CGFloat = 0.0) {
        ensureLayerBacked()
        var filters: [CIFilter] = []

        if blur > 0 {
            if let f = CIFilter(name: "CIGaussianBlur") {
                f.setValue(blur, forKey: kCIInputRadiusKey)
                filters.append(f)
            }
        }

        if brightness != 0 || saturation != 1.0 {
            if let f = CIFilter(name: "CIColorControls") {
                f.setValue(saturation, forKey: "inputSaturation")
                f.setValue(brightness,  forKey: "inputBrightness")
                filters.append(f)
            }
        }

        backingGlass.layer?.filters = filters.isEmpty ? nil : filters
    }

    // MARK: - Internals

    private let contentHost = NSView(frame: .zero)
    private var backingGlass: NSView! // NSGlassEffectView (26+) or NSVisualEffectView (fallback)

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        buildBacking()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = false
        buildBacking()
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let s = superview, translatesAutoresizingMaskIntoConstraints == false else { return }
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: s.leadingAnchor),
            trailingAnchor.constraint(equalTo: s.trailingAnchor),
            topAnchor.constraint(equalTo: s.topAnchor),
            bottomAnchor.constraint(equalTo: s.bottomAnchor)
        ])
    }

    // Build NSGlassEffectView if available, else NSVisualEffectView
    private func buildBacking() {
        let glass: NSView

        if #available(macOS 26.0, *), let GlassType = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let g = GlassType.init(frame: bounds)
            g.translatesAutoresizingMaskIntoConstraints = false
            glass = g
        } else {
            let v = NSVisualEffectView(frame: bounds)
            v.translatesAutoresizingMaskIntoConstraints = false
            v.material = .underWindowBackground
            v.blendingMode = .behindWindow
            v.state = .active
            v.wantsLayer = true
            v.layer?.masksToBounds = true
            glass = v
        }

        backingGlass = glass

        addSubview(backingGlass)
        NSLayoutConstraint.activate([
            backingGlass.leadingAnchor.constraint(equalTo: leadingAnchor),
            backingGlass.trailingAnchor.constraint(equalTo: trailingAnchor),
            backingGlass.topAnchor.constraint(equalTo: topAnchor),
            backingGlass.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // content host
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.wantsLayer = false

        if backingGlass.responds(to: NSSelectorFromString("setContentView:")) {
            backingGlass.setValue(contentHost, forKey: "contentView") // NSGlassEffectView path
        } else {
            backingGlass.addSubview(contentHost) // fallback path
            NSLayoutConstraint.activate([
                contentHost.leadingAnchor.constraint(equalTo: backingGlass.leadingAnchor),
                contentHost.trailingAnchor.constraint(equalTo: backingGlass.trailingAnchor),
                contentHost.topAnchor.constraint(equalTo: backingGlass.topAnchor),
                contentHost.bottomAnchor.constraint(equalTo: backingGlass.bottomAnchor)
            ])
        }

        // Apply defaults
        style = 1
        cornerRadius = 14
        tintColor = nil
    }

    private func applyStyle() {
        if backingGlass.responds(to: NSSelectorFromString("setStyle:")) {
            backingGlass.setValue(style, forKey: "style")
        }
    }

    private func applyCornerRadius() {
        if backingGlass.responds(to: NSSelectorFromString("setCornerRadius:")) {
            backingGlass.setValue(cornerRadius, forKey: "cornerRadius")
        } else {
            ensureLayerBacked()
            backingGlass.layer?.cornerRadius = cornerRadius
            backingGlass.layer?.masksToBounds = true
        }
    }

    private func applyTint() {
        if backingGlass.responds(to: NSSelectorFromString("setTintColor:")) {
            backingGlass.setValue(tintColor, forKey: "tintColor")
        } else if let tint = tintColor {
            ensureLayerBacked()
            backingGlass.layer?.backgroundColor = tint.cgColor // very subtle on fallback
        } else {
            backingGlass.layer?.backgroundColor = nil
        }
    }

    private func setPrivate(_ key: String, value: Any) {
        guard backingGlass.responds(to: NSSelectorFromString("setContentView:")) else { return }
        // Best-effort, swallow future changes safely
        (try? ObjcKVC.setValue(value, forKey: key, on: backingGlass)) ?? ()
    }

    private func ensureLayerBacked() {
        if backingGlass.layer == nil {
            backingGlass.wantsLayer = true
            backingGlass.layer = CALayer()
        }
    }
}

/// Tiny helper to avoid bridging crashes if KVC changes in future macOS versions
private enum ObjcKVC {
    static func setValue(_ value: Any, forKey key: String, on object: Any) throws {
        (object as AnyObject).setValue(value, forKey: key)
    }
}

// MARK: - SwiftUI wrapper

public enum GUI { }

@available(macOS 26.0, *)
public struct CustomGlassEffectView<Content: View>: NSViewRepresentable {
    private let variant: Int?
    private let scrimState: Int?
    private let subduedState: Int?
    private let style: NSGlassEffectView.Style
    private let tint: NSColor?
    private let cornerRadius: CGFloat
    private let content: Content

    public init(variant: Int? = nil,
                scrimState: Int? = nil,
                subduedState: Int? = nil,
                style: NSGlassEffectView.Style = .clear,
                tint: NSColor? = nil,
                cornerRadius: CGFloat = 14,
                @ViewBuilder content: () -> Content)
    {
        self.variant = variant
        self.scrimState = scrimState
        self.subduedState = subduedState
        self.style = style
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public func makeNSView(context: Context) -> LiquidGlassView {
        let v = LiquidGlassView.glass(withStyle: Int(style.rawValue),
                                      cornerRadius: cornerRadius,
                                      tintColor: tint)
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        v.contentView = hosting

        if let variant { v.setVariantIfAvailable(variant) }
        if let scrimState { v.setScrimStateIfAvailable(scrimState) }
        if let subduedState { v.setSubduedStateIfAvailable(subduedState) }

        return v
    }

    public func updateNSView(_ v: LiquidGlassView, context: Context) {
        if let hosting = v.contentView as? NSHostingView<Content> {
            hosting.rootView = content
        }
        v.style = Int(style.rawValue)
        v.cornerRadius = cornerRadius
        v.tintColor = tint
        if let variant { v.setVariantIfAvailable(variant) }
        if let scrimState { v.setScrimStateIfAvailable(scrimState) }
        if let subduedState { v.setSubduedStateIfAvailable(subduedState) }
    }
}
