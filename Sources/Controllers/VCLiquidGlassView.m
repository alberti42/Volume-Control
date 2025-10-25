//
//  LiquidGlassView.m
//  Volume Control
//
//  Created by Andrea Alberti on 25.10.25.
//

#import "VCLiquidGlassView.h"

@interface VCLiquidGlassView ()
@property (strong) NSView *backingGlass;      // NSGlassEffectView or NSVisualEffectView
@property (strong) NSView *contentHost;       // Where clients put their content
@end

@implementation VCLiquidGlassView

+ (instancetype)glassWithStyle:(NSInteger)style cornerRadius:(CGFloat)cornerRadius tintColor:(NSColor *)tint {
    VCLiquidGlassView *v = [[self alloc] initWithFrame:NSZeroRect];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.style = style;
    v.cornerRadius = cornerRadius;
    v.tintColor = tint;
    return v;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = NO; // root stays “pass-through”
        [self buildBacking];
    }
    return self;
}

- (void)viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
    if (self.superview && self.translatesAutoresizingMaskIntoConstraints == NO) {
        // auto-pin to fill parent if you added it with Auto Layout
        [NSLayoutConstraint activateConstraints:@[
            [self.leadingAnchor constraintEqualToAnchor:self.superview.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:self.superview.trailingAnchor],
            [self.topAnchor constraintEqualToAnchor:self.superview.topAnchor],
            [self.bottomAnchor constraintEqualToAnchor:self.superview.bottomAnchor]
        ]];
    }
}

- (void)buildBacking {
    // Build glass (26+) or fallback
    NSView *glass = nil;
    if (@available(macOS 26.0, *)) {
        Class GlassCls = NSClassFromString(@"NSGlassEffectView");
        if (GlassCls) {
            glass = [[GlassCls alloc] initWithFrame:self.bounds];
            glass.translatesAutoresizingMaskIntoConstraints = NO;
            // Defaults
            [glass setValue:@(1) forKey:@"style"]; // Clear by default
            [glass setValue:@(14.0) forKey:@"cornerRadius"];
        }
    }
    if (!glass) {
        NSVisualEffectView *vev = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
        vev.translatesAutoresizingMaskIntoConstraints = NO;
        vev.material = NSVisualEffectMaterialUnderWindowBackground;
        vev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        vev.state = NSVisualEffectStateActive;
        vev.wantsLayer = YES;
        vev.layer.masksToBounds = YES;
        vev.layer.cornerRadius = 14.0;
        glass = vev;
    }
    self.backingGlass = glass;

    // A host view that you can treat like NSGlassEffectView.contentView
    NSView *host = [[NSView alloc] initWithFrame:self.bounds];
    host.translatesAutoresizingMaskIntoConstraints = NO;
    host.wantsLayer = NO;
    self.contentHost = host;

    [self addSubview:self.backingGlass];
    [NSLayoutConstraint activateConstraints:@[
        [self.backingGlass.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.backingGlass.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.backingGlass.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.backingGlass.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    if ([self.backingGlass respondsToSelector:NSSelectorFromString(@"setContentView:")]) {
        // NSGlassEffectView path
        [self.backingGlass setValue:self.contentHost forKey:@"contentView"];
    } else {
        // Fallback: add host as a subview inside VEV
        [self.backingGlass addSubview:self.contentHost];
        [NSLayoutConstraint activateConstraints:@[
            [self.contentHost.leadingAnchor constraintEqualToAnchor:self.backingGlass.leadingAnchor],
            [self.contentHost.trailingAnchor constraintEqualToAnchor:self.backingGlass.trailingAnchor],
            [self.contentHost.topAnchor constraintEqualToAnchor:self.backingGlass.topAnchor],
            [self.contentHost.bottomAnchor constraintEqualToAnchor:self.backingGlass.bottomAnchor],
        ]];
    }
}

#pragma mark - API

- (void)setContentView:(NSView *)contentView {
    // Replace existing content
    for (NSView *v in self.contentHost.subviews) { [v removeFromSuperview]; }
    if (!contentView) return;

    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentHost addSubview:contentView];
    [NSLayoutConstraint activateConstraints:@[
        [contentView.leadingAnchor constraintEqualToAnchor:self.contentHost.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.contentHost.trailingAnchor],
        [contentView.topAnchor constraintEqualToAnchor:self.contentHost.topAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.contentHost.bottomAnchor]
    ]];
}

- (NSView *)contentView {
    return self.contentHost.subviews.firstObject;
}

- (void)configureWithStyle:(NSInteger)style cornerRadius:(CGFloat)cornerRadius tintColor:(NSColor *)tint {
    self.style = style;
    self.cornerRadius = cornerRadius;
    self.tintColor = tint;
}

- (void)setStyle:(NSInteger)style {
    _style = style;
    if ([self.backingGlass respondsToSelector:@selector(setStyle:)]) {
        // NSGlassEffectView
        [self.backingGlass setValue:@(style) forKey:@"style"];
    } else {
        // Fallback has no “style” concept
    }
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    if ([self.backingGlass respondsToSelector:@selector(setCornerRadius:)]) {
        [self.backingGlass setValue:@(cornerRadius) forKey:@"cornerRadius"];
    } else if (self.backingGlass.wantsLayer) {
        self.backingGlass.layer.cornerRadius = cornerRadius;
        self.backingGlass.layer.masksToBounds = YES;
    }
}

- (void)setTintColor:(NSColor *)tintColor {
    _tintColor = [tintColor copy];
    if ([self.backingGlass respondsToSelector:NSSelectorFromString(@"setTintColor:")]) {
        [self.backingGlass setValue:_tintColor forKey:@"tintColor"];
    } else if (self.backingGlass.wantsLayer && _tintColor) {
        // VERY subtle fallback tint
        self.backingGlass.layer.backgroundColor = _tintColor.CGColor;
    }
}

#pragma mark - Private Tahoe knobs

- (void)setVariantIfAvailable:(NSInteger)variant {
    @try { [self.backingGlass setValue:@(variant) forKey:@"_variant"]; } @catch (...) {}
}
- (void)setScrimStateIfAvailable:(NSInteger)onOff {
    @try { [self.backingGlass setValue:@(onOff) forKey:@"_scrimState"]; } @catch (...) {}
}
- (void)setSubduedStateIfAvailable:(NSInteger)onOff {
    @try { [self.backingGlass setValue:@(onOff) forKey:@"_subduedState"]; } @catch (...) {}
}

@end
