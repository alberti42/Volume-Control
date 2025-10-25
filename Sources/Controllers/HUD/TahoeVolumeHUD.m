// FILE: TahoeVolumeHUD.m

#import "TahoeVolumeHUD.h"
#import "CustomVolumeSlider.h"
#import <AppKit/NSGlassEffectView.h>
#import "HUDPanel.h"

// Product Module Name: Volume_Control
#import "Volume_Control-Swift.h"  // exposes LiquidGlassView to ObjC

@interface TahoeVolumeHUD ()

// Window + layout
@property (strong) HUDPanel *panel;
@property (strong) NSView *root;
@property (strong) LiquidGlassView *glass;

// UI
@property (strong) NSSlider *slider;
@property (strong) NSImageView *appIconView;
@property (strong) NSTimer *hideTimer;
@property (strong) NSTextField *titleLabel;


// Constraints
@property (strong) NSLayoutConstraint *contentFixedHeight;

@end

// Tunables
static const CGFloat kHUDHeight      = 64.0;
static const CGFloat kHUDWidth       = 290.0;
static const CGFloat kCornerRadius   = 24.0;
static const CGFloat kBelowGap       = 14.0;
static const NSTimeInterval kAutoHide = 2.0;

@implementation TahoeVolumeHUD

+ (TahoeVolumeHUD *)sharedManager {
    static TahoeVolumeHUD *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TahoeVolumeHUD alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (!self) return nil;

    // Panel
    NSRect frame = NSMakeRect(0, 0, kHUDWidth, kHUDHeight);
    _panel = [[HUDPanel alloc] initWithContentRect:frame
                                         styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = YES;
    _panel.hidesOnDeactivate = YES;
    _panel.level = NSPopUpMenuWindowLevel;
    _panel.movableByWindowBackground = NO;
    _panel.collectionBehavior = NSWindowCollectionBehaviorTransient
                              | NSWindowCollectionBehaviorFullScreenAuxiliary
                              | NSWindowCollectionBehaviorCanJoinAllSpaces;
    _panel.floatingPanel = YES;
    _panel.becomesKeyOnlyIfNeeded = YES;

    // Size fences
    _panel.contentMinSize = NSMakeSize(kHUDWidth, kHUDHeight);
    _panel.contentMaxSize = NSMakeSize(FLT_MAX, kHUDHeight);
    [_panel setContentSize:NSMakeSize(kHUDWidth, kHUDHeight)];

    // Root host
    _root = [[NSView alloc] initWithFrame:_panel.contentView.bounds];
    _root.translatesAutoresizingMaskIntoConstraints = NO;
    _root.wantsLayer = YES;
    _root.layer.backgroundColor = NSColor.clearColor.CGColor;
    _panel.contentView = _root;

    // Hard height on the window contentView — guarantees kHUDHeight regardless of fitting sizes
    self.contentFixedHeight = [_panel.contentView.heightAnchor constraintEqualToConstant:kHUDHeight];
    self.contentFixedHeight.priority = 1000;
    self.contentFixedHeight.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [_root.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor],
        [_root.trailingAnchor constraintEqualToAnchor:_panel.contentView.trailingAnchor],
        [_root.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor],
        [_root.bottomAnchor constraintEqualToAnchor:_panel.contentView.bottomAnchor],
    ]];

    // Glass (Swift class)
    [self installGlassInto:_root cornerRadius:kCornerRadius];

    // Content wrapper (fills the glass)
    NSView *wrapper = [NSView new];
    wrapper.translatesAutoresizingMaskIntoConstraints = NO;

    // Vertical stack container centered vertically inside wrapper
    NSView *stack = [NSView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [wrapper addSubview:stack];

    // Center the whole stack vertically; stretch horizontally
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerYAnchor constraintEqualToAnchor:wrapper.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor],
    ]];

    // Build header row (icon + label) and slider strip
    NSView *header = [self buildHeaderRow];
    NSView *strip  = [self buildSliderStrip];

    [stack addSubview:header];
    [stack addSubview:strip];

    // Vertical layout: header on top, small spacing, then strip
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:stack.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:12],
        [header.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:-12],

        [strip.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:6],
        [strip.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor],
        [strip.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor],
        [strip.bottomAnchor constraintEqualToAnchor:stack.bottomAnchor],
    ]];

    // Install in glass (wrapper stretches to the glass edges via LiquidGlassView)
    self.glass.contentView = wrapper;


    return self;
}

#pragma mark - Public API

- (void)showHUDWithVolume:(double)volume usingIcon:(NSImage*)icon anchoredToStatusButton:(NSStatusBarButton *)button {
    if (volume > 1.0) volume = MAX(0.0, MIN(1.0, volume / 100.0));
    self.slider.doubleValue = volume;

    // Update header
    self.appIconView.image = icon;
    self.titleLabel.stringValue = @"Place holder"; // TODO: replace with actual source (player name, etc.)

    // Size fence each time
    [_panel setContentSize:NSMakeSize(kHUDWidth, kHUDHeight)];

    [self positionPanelBelowStatusButton:button];
    [self.panel orderFront:nil];

    [self.hideTimer invalidate];
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:kAutoHide
                                                      target:self
                                                    selector:@selector(hide)
                                                    userInfo:nil
                                                     repeats:NO];
}


- (void)setVolume:(double)volume {
    if (volume > 1.0) volume = MAX(0.0, MIN(1.0, volume / 100.0));
    self.slider.doubleValue = volume;
}

- (void)hide {
    [self.panel orderOut:nil];
    [self.hideTimer invalidate];
    self.hideTimer = nil;

    if ([self.delegate respondsToSelector:@selector(hudDidHide:)]) {
        [self.delegate hudDidHide:self];
    }
}

#pragma mark - Layout / Anchoring

- (void)positionPanelBelowStatusButton:(NSStatusBarButton *)button {
    if (!button || !button.window) {
        NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
        if (screen) {
            NSRect vis = screen.visibleFrame;
            CGFloat x = NSMidX(vis) - self.panel.frame.size.width/2.0;
            CGFloat y = NSMidY(vis) - self.panel.frame.size.height/2.0;
            [self.panel setFrameOrigin:NSMakePoint(round(x), round(y))];
        }
        return;
    }

    NSRect buttonRectInWindow = [button convertRect:button.bounds toView:nil];
    NSRect buttonInScreen = [button.window convertRectToScreen:buttonRectInWindow];

    NSSize size = NSMakeSize(kHUDWidth, kHUDHeight);
    CGFloat x = NSMidX(buttonInScreen) - size.width / 2.0;
    CGFloat y = NSMinY(buttonInScreen) - size.height - kBelowGap;

    NSScreen *target = button.window.screen ?: NSScreen.mainScreen;
    NSRect vis = target.visibleFrame;

    if (y < NSMinY(vis)) y = NSMinY(vis) + 2.0;

    CGFloat margin = 8.0;
    x = MAX(NSMinX(vis) + margin, MIN(x, NSMaxX(vis) - margin - size.width));

    [self.panel setFrame:NSMakeRect(round(x), round(y), size.width, size.height) display:NO];
}

#pragma mark - Glass

- (void)installGlassInto:(NSView *)host cornerRadius:(CGFloat)radius {
    LiquidGlassView *glass = [LiquidGlassView glassWithStyle:1  // Clear
                                                cornerRadius:radius
                                                   tintColor:[NSColor colorWithCalibratedWhite:1 alpha:0.06]];
    self.glass = glass;

    [host addSubview:glass];
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [glass.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [glass.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [glass.topAnchor constraintEqualToAnchor:host.topAnchor],
        [glass.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
    ]];

    // Optional Tahoe tuning:
    [glass setVariantIfAvailable:5];
    [glass setScrimStateIfAvailable:0];
    [glass setSubduedStateIfAvailable:0];

    // Optional SwiftUI-like post-filters:
    [glass applyVisualAdjustmentsWithSaturation:1.5 brightness:0.2 blur:0.25];
}

#pragma mark - Content

- (NSView *)buildSliderStrip {
    NSView *strip = [NSView new];
    strip.translatesAutoresizingMaskIntoConstraints = NO;

    // Left speaker glyph
    NSImageView *iconLeft = [NSImageView new];
    iconLeft.translatesAutoresizingMaskIntoConstraints = NO;
    iconLeft.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightSemibold];
    iconLeft.image = [NSImage imageWithSystemSymbolName:@"speaker.fill" accessibilityDescription:nil];
    iconLeft.contentTintColor = NSColor.labelColor;
    [iconLeft setContentHuggingPriority:251 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [iconLeft setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationHorizontal];

    // Right speaker glyph
    NSImageView *iconRight = [NSImageView new];
    iconRight.translatesAutoresizingMaskIntoConstraints = NO;
    iconRight.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightSemibold];
    iconRight.image = [NSImage imageWithSystemSymbolName:@"speaker.wave.2.fill" accessibilityDescription:nil];
    iconRight.contentTintColor = NSColor.labelColor;
    [iconRight setContentHuggingPriority:251 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [iconRight setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationHorizontal];

    // Slider (custom white cell)
    NSSlider *slider = [NSSlider sliderWithValue:0.6 minValue:0.0 maxValue:1.0 target:self action:@selector(sliderChanged:)];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.controlSize = NSControlSizeSmall;

    CustomVolumeSlider *cell = [CustomVolumeSlider new]; // NSSliderCell subclass
    cell.minValue = 0.0;
    cell.maxValue = 1.0;
    cell.controlSize = NSControlSizeSmall;
    slider.cell = cell;

    [slider setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [slider setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.slider = slider;

    [strip addSubview:iconLeft];
    [strip addSubview:slider];
    [strip addSubview:iconRight];

    [NSLayoutConstraint activateConstraints:@[
        [strip.heightAnchor constraintEqualToConstant:36],

        [iconLeft.leadingAnchor constraintEqualToAnchor:strip.leadingAnchor constant:12],
        [iconLeft.centerYAnchor constraintEqualToAnchor:strip.centerYAnchor],

        [iconRight.trailingAnchor constraintEqualToAnchor:strip.trailingAnchor constant:-12],
        [iconRight.centerYAnchor constraintEqualToAnchor:strip.centerYAnchor],

        [slider.leadingAnchor constraintEqualToAnchor:iconLeft.trailingAnchor constant:8],
        [slider.trailingAnchor constraintEqualToAnchor:iconRight.leadingAnchor constant:-8],
        [slider.centerYAnchor constraintEqualToAnchor:strip.centerYAnchor],
    ]];

    strip.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    return strip;
}


- (NSView *)buildHeaderRow {
    NSView *row = [NSView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    // Icon (uses the same appIconView instance so other code can update it)
    self.appIconView = [NSImageView new];
    self.appIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.appIconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.appIconView.wantsLayer = YES;
    self.appIconView.layer.cornerRadius = 6.0;
    self.appIconView.layer.masksToBounds = YES;

    // Title label
    self.titleLabel = [NSTextField labelWithString:@"Place holder"];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    self.titleLabel.textColor = [NSColor labelColor];

    [row addSubview:self.appIconView];
    [row addSubview:self.titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.appIconView.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [self.appIconView.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [self.appIconView.widthAnchor constraintEqualToConstant:18],
        [self.appIconView.heightAnchor constraintEqualToConstant:18],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.appIconView.trailingAnchor constant:8],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [row.heightAnchor constraintEqualToConstant:20],
    ]];

    // Good contrast on glass
    row.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];

    return row;
}



#pragma mark - Actions

- (void)sliderChanged:(NSSlider *)sender {
    double v = sender.doubleValue; // 0..1
    if ([self.delegate respondsToSelector:@selector(hud:didChangeVolume:)]) {
        [self.delegate hud:self didChangeVolume:v];
    }
    [self.hideTimer invalidate];
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:1.2
                                                      target:self
                                                    selector:@selector(hide)
                                                    userInfo:nil
                                                     repeats:NO];
}

#pragma mark - Optional: App icon setter

- (void)setAppIcon:(NSImage *)image {
    self.appIconView.image = image;
    if (self.appIconView.layer.sublayers.count == 0) {
        CALayer *stroke = [CALayer layer];
        stroke.frame = self.appIconView.bounds;
        stroke.cornerRadius = 6.0;
        stroke.borderWidth = 1.0;
        stroke.borderColor = [[NSColor colorWithWhite:1 alpha:0.15] CGColor];
        stroke.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        [self.appIconView.layer addSublayer:stroke];
    }
}

@end
