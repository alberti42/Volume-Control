//
//  LiquidGlassView.h
//  Volume Control
//
//  Created by Andrea Alberti on 25.10.25.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A view that hosts content inside native glass (macOS 26+) with fallback to NSVisualEffectView.
/// Add subviews to `contentView` (or set it), not to `VCLiquidGlassView` itself.
@interface VCLiquidGlassView : NSView

/// The embedded content. You can set either a single content view, or just add your subviews to it.
@property (nullable, strong) __kindof NSView *contentView;

/// Public glass properties (no private API required)
@property CGFloat cornerRadius;                         // default 14
@property (nullable, copy) NSColor *tintColor;          // default nil
@property NSInteger style;                              // NSGlassEffectViewStyle (0=Regular,1=Clear). Defaults to Clear on 26+, ignored on fallback.

/// Convenience: set all at once.
- (void)configureWithStyle:(NSInteger)style
               cornerRadius:(CGFloat)cornerRadius
                  tintColor:(nullable NSColor *)tint;

/// Private Tahoe knobs (no-ops on fallback or if Apple removes them)
- (void)setVariantIfAvailable:(NSInteger)variant;        // 0..N
- (void)setScrimStateIfAvailable:(NSInteger)onOff;       // 0/1
- (void)setSubduedStateIfAvailable:(NSInteger)onOff;     // 0/1

/// Build and return a fully configured instance.
+ (instancetype)glassWithStyle:(NSInteger)style
                  cornerRadius:(CGFloat)cornerRadius
                     tintColor:(nullable NSColor *)tint;

@end

NS_ASSUME_NONNULL_END
