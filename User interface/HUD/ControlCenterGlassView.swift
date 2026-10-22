//
//  ControlCenterGlassView.swift
//
//  The glass of the system volume HUD on macOS 26, built as ControlCenter builds it,
//  usable from Objective-C.
//

import AppKit
import SwiftUI

/// ControlCenter on macOS 26.3.1 draws the volume HUD's glass as
/// Material._glass(Material._GlassVariant.controlCenter), wrapped with _Glass.explicit(_:).
/// These are private SwiftUI symbols, so they are looked up at runtime. The resulting
/// _Glass is copied into a Glass for the public glassEffect(_:in:).
@objc(ControlCenterGlassView)
public final class ControlCenterGlassView: NSView {

    /// YES when every symbol the glass needs is present on this system.
    @objc public static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return controlCenterGlass != nil }
        return false
    }

    /// Drawn on the glass. As in NSGlassEffectView, controls look right only inside the
    /// glass: next to it, a slider draws its empty track black instead of translucent.
    @objc public var contentView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            guard let contentView else { return }
            contentView.translatesAutoresizingMaskIntoConstraints = false
            contentHost.addSubview(contentView)
            NSLayoutConstraint.activate([
                contentView.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
                contentView.topAnchor.constraint(equalTo: contentHost.topAnchor),
                contentView.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            ])
        }
    }

    private let contentHost = NSView()

    /// Fills the view with the glass. Returns nil when `isAvailable` is NO.
    @objc public init?(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        guard #available(macOS 26.0, *), let glass = Self.controlCenterGlass else { return nil }
        let root = ControlCenterGlassBackground(content: contentHost, glass: glass, cornerRadius: cornerRadius)
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @available(macOS 26.0, *)
    private static let controlCenterGlass: Glass? = makeControlCenterGlass()
}

@available(macOS 26.0, *)
private struct ControlCenterGlassBackground: View {
    let content: NSView
    let glass: Glass
    let cornerRadius: CGFloat

    var body: some View {
        HostedView(view: content)
            .glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct HostedView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Returns _Glass.explicit(Material._glass(.controlCenter)) as a Glass, or nil when a symbol
/// is missing or the two types differ in size. SwiftUI is built with library evolution, so
/// its public functions take and return its structs indirectly; the generic function types
/// below have the same ABI.
///
/// A Glass holds exactly a _Glass: on macOS 26.3.1 _Glass.clear and Glass.clear write the same
/// 41 bytes, and on macOS 27.0.1 Glass.init(explicit:), which 26.3.1 lacks, copies the 40
/// bytes of its _Glass argument and does nothing else.
@available(macOS 26.0, *)
private func makeControlCenterGlass() -> Glass? {
    guard let swiftUI = dlopen("/System/Library/Frameworks/SwiftUI.framework/SwiftUI", RTLD_NOW),
          let variantGetter = dlsym(swiftUI, "$s7SwiftUI8MaterialV13_GlassVariantV13controlCenterAEvgZ"),
          let materialGlass = dlsym(swiftUI, "$s7SwiftUI8MaterialV6_glassyA2C13_GlassVariantVFZ"),
          let glassExplicit = dlsym(swiftUI, "$s7SwiftUI6_GlassV8explicityAcA8MaterialVFZ"),
          let variantType = _typeByName("7SwiftUI8MaterialV13_GlassVariantV"),
          let privateGlassType = _typeByName("7SwiftUI6_GlassV")
    else { return nil }

    func build<Variant, PrivateGlass>(_: Variant.Type, _: PrivateGlass.Type) -> Glass? {
        guard MemoryLayout<PrivateGlass>.size == MemoryLayout<Glass>.size else { return nil }
        typealias VariantGetter = @convention(thin) () -> Variant
        typealias MaterialGlass = @convention(thin) (Variant) -> Material
        typealias GlassExplicit = @convention(thin) (Material) -> PrivateGlass
        let variant = unsafeBitCast(variantGetter, to: VariantGetter.self)()
        let material = unsafeBitCast(materialGlass, to: MaterialGlass.self)(variant)
        let privateGlass = unsafeBitCast(glassExplicit, to: GlassExplicit.self)(material)
        return unsafeBitCast(privateGlass, to: Glass.self)
    }

    func open<Variant>(_ variant: Variant.Type) -> Glass? {
        func openGlass<PrivateGlass>(_ privateGlass: PrivateGlass.Type) -> Glass? {
            build(variant, privateGlass)
        }
        return _openExistential(privateGlassType, do: openGlass)
    }
    return _openExistential(variantType, do: open)
}
