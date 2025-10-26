// FILE: TahoeVolumeHUD.m

#import "TahoeVolumeHUD.h"
#import "VolumeSliderCell.h"
#import <AppKit/NSGlassEffectView.h>
#import "HUDPanel.h"
#import "VolumeSlider.h"
#import "AppDelegate.h"
#import <QuartzCore/QuartzCore.h>

// Product Module Name: Volume_Control
#import "Volume_Control-Swift.h"  // exposes LiquidGlassView to ObjC

// **IMPROVEMENT 1: Add VolumeSliderDelegate protocol conformance**
@interface TahoeVolumeHUD () <VolumeSliderDelegate>

// Window + layout
@property (strong) HUDPanel *panel;
@property (strong) NSView *root;
@property (strong) LiquidGlassView *glass;

// UI
// **IMPROVEMENT 2: Change property type to be more specific**
@property (strong) VolumeSlider *slider;
@property (strong) NSImageView *appIconView;
@property (strong) NSTimer *hideTimer;
@property (strong) NSTextField *titleLabel;

// Constraints
@property (strong) NSLayoutConstraint *contentFixedHeight;

// Player
@property (strong) PlayerApplication *controlledPlayer;

@end

// Tunables
static const CGFloat kHUDHeight      = 64.0;
static const CGFloat kHUDWidth       = 290.0;
static const CGFloat kCornerRadius   = 24.0;
static const CGFloat kBelowGap       = 14.0;
static const NSTimeInterval kAutoHide = 1.5;
static const CGFloat kSideInset  = 12.0;  // left/right margin

static const NSTimeInterval kFadeInDuration  = 0.25; // seconds
static const NSTimeInterval kFadeOutDuration = 0.45; // seconds

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

    // ... (this part is correct) ...
    // Panel
    NSRect frame = NSMakeRect(0, 0, kHUDWidth, kHUDHeight);
    _panel = [[HUDPanel alloc] initWithContentRect:frame
                                         styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = NO;
    _panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];

    // Set to NO to prevent the panel from hiding when the app is not active.
    _panel.hidesOnDeactivate = NO;
    
    _panel.level = NSPopUpMenuWindowLevel;
    _panel.movableByWindowBackground = NO;

    // Ensure the panel can appear on any space.
    // This makes it a true system-wide HUD.
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
    
    // 1 of 3: Set the appearance for the entire content view.
    // This forces all subviews (labels, icons) to use their dark variants.
    wrapper.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    
    // Build header row (icon + label) and slider strip
    NSView *header = [self buildHeaderRow];
    NSView *strip  = [self buildSliderStrip];
    
    [wrapper addSubview:header];
    [wrapper addSubview:strip];
    
    // Anchor header to top, strip to bottom. This is more robust.
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:wrapper.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor],

        [strip.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor],
        [strip.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor],
        [strip.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor],
    ]];

    // Install in glass (wrapper stretches to the glass edges via LiquidGlassView)
    self.glass.contentView = wrapper;


    return self;
}

#pragma mark - Public API

- (void)showHUDWithVolume:(double)volume usingMusicPlayer:(PlayerApplication*)player andLabel:(NSString*)label anchoredToStatusButton:(NSStatusBarButton *)button {
    self.controlledPlayer = player;
    
    if (volume > 1.0) volume = MAX(0.0, MIN(1.0, volume / 100.0));
    self.slider.doubleValue = volume;
    
    // Update header
    self.appIconView.image = [player icon];
    self.titleLabel.stringValue = label;
    
    // Size fence each time
    [_panel setContentSize:NSMakeSize(kHUDWidth, kHUDHeight)];
    
    [self positionPanelBelowStatusButton:button];
    
    // Animate the fade-in
    
    // 1. If the panel is already visible, just update it.
    // Otherwise, prepare for a fade-in animation.
    if (!self.panel.isVisible) {
        // Set the panel to be fully transparent before showing it
        self.panel.alphaValue = 0.0;
        [self.panel orderFront:nil];
    }

    // 2. Animate the alpha value to 1.0 (fully opaque)
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = kFadeInDuration;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [[self.panel animator] setAlphaValue:1.0];
    }];

    // Reset the auto-hide timer
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
    // Invalidate the timer to prevent this method from being called again
    [self.hideTimer invalidate];
    self.hideTimer = nil;

    // Animate the fade-out
    
    // 1. Animate the alpha value down to 0.0 (fully transparent)
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = kFadeOutDuration;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        [[self.panel animator] setAlphaValue:0.0];
    } completionHandler:^{
        // 2. AFTER the animation is complete, properly order the window out.
        // This is crucial for performance and correctness.
        [self.panel orderOut:nil];
    }];
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
    LiquidGlassView *glass = [LiquidGlassView glassWithStyle:0  // Clear
                                                cornerRadius:radius
                                                   tintColor:[NSColor colorWithCalibratedWhite:1 alpha:1]];
    self.glass = glass;
    
    // Enable the new vibrant rim here.
    glass.hasVibrantRim = NO;

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
    
    // Setting adaptive appearance to 0 is the key to keeping it dark.
    [glass setAdaptiveAppearanceIfAvailable:0];
    [glass setUseReducedShadowRadiusIfAvailable:YES];
    [glass setContentLensingIfAvailable:0];
    
    // Optional SwiftUI-like post-filters:
    //[glass applyVisualAdjustmentsWithSaturation:1.5 brightness:0.2 blur:0.25];
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

    // 1. Create a dedicated view for the track's background.
    NSView *trackBackgroundView = [NSView new];
    trackBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;
    trackBackgroundView.wantsLayer = YES;
    trackBackgroundView.layer.backgroundColor = [NSColor colorWithWhite:1.0 alpha:0.25].CGColor;
    trackBackgroundView.layer.cornerRadius = 2.0; // The radius of our track

    // 2. Create the slider.
    VolumeSlider *slider = [VolumeSlider new];
    slider.minValue = 0.0;
    slider.maxValue = 1.0;
    slider.doubleValue = 0.6;
    slider.trackingDelegate = self;
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.controlSize = NSControlSizeSmall;

    // 3. Configure the slider's appearance.
    // Make the slider itself transparent. Only the filled portion will draw.
    if (@available(macOS 10.12.2, *)) {
        slider.sliderType = NSSliderTypeLinear;
    }
    slider.trackFillColor = [NSColor colorWithWhite:1.0 alpha:0.85];

    // NOTE: We REMOVE the slider.wantsLayer and slider.layer.backgroundColor
    // settings from the previous step.

    // Still use our custom cell for the hover knob.
    VolumeSliderCell *cell = [VolumeSliderCell new];
    cell.minValue = 0.0;
    cell.maxValue = 1.0;
    cell.controlSize = NSControlSizeSmall;
    slider.cell = cell;

    [slider setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [slider setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.slider = slider;

    // 4. Add views to the strip. The background goes in first (underneath).
    [strip addSubview:iconLeft];
    [strip addSubview:trackBackgroundView];
    [strip addSubview:slider]; // Slider is added on top of the background
    [strip addSubview:iconRight];

    // 5. Set up constraints.
    [NSLayoutConstraint activateConstraints:@[
        [strip.heightAnchor constraintEqualToConstant:36],

        [iconLeft.leadingAnchor constraintEqualToAnchor:strip.leadingAnchor constant:12],
        [iconLeft.centerYAnchor constraintEqualToAnchor:strip.centerYAnchor],

        [iconRight.trailingAnchor constraintEqualToAnchor:strip.trailingAnchor constant:-12],
        [iconRight.centerYAnchor constraintEqualToAnchor:strip.centerYAnchor],

        // --- Constraints for the background view ---
        [trackBackgroundView.leadingAnchor constraintEqualToAnchor:iconLeft.trailingAnchor constant:8],
        [trackBackgroundView.trailingAnchor constraintEqualToAnchor:iconRight.leadingAnchor constant:-8],
        [trackBackgroundView.centerYAnchor constraintEqualToAnchor:strip.centerYAnchor],
        // Give it the exact height of the bar from your original code.
        [trackBackgroundView.heightAnchor constraintEqualToConstant:4.0],

        // --- Constraints for the slider ---
        // The slider overlays the background view perfectly horizontally.
        [slider.leadingAnchor constraintEqualToAnchor:trackBackgroundView.leadingAnchor],
        [slider.trailingAnchor constraintEqualToAnchor:trackBackgroundView.trailingAnchor],
        // Vertically, it's centered in the whole strip to ensure its clickable area is large enough.
        [slider.centerYAnchor constraintEqualToAnchor:strip.centerYAnchor],
    ]];
    // strip.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
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

    // New constraints for better padding and alignment.
    CGFloat topPadding = 12.0; // Increased to provide more space at the top.
    CGFloat bottomPadding = 4.0; // Defines space between header and slider strip.

    [NSLayoutConstraint activateConstraints:@[
        // Icon constraints define the layout and padding for the header row.
        [self.appIconView.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:kSideInset],
        [self.appIconView.topAnchor constraintEqualToAnchor:row.topAnchor constant:topPadding],
        [self.appIconView.widthAnchor constraintEqualToConstant:18],
        [self.appIconView.heightAnchor constraintEqualToConstant:18],
        
        // The header row's height is determined by the icon's position and its own padding.
        [row.bottomAnchor constraintEqualToAnchor:self.appIconView.bottomAnchor constant:bottomPadding],

        // Title label is positioned relative to the icon.
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.appIconView.trailingAnchor constant:8],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.appIconView.centerYAnchor],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-kSideInset],
    ]];

    // Good contrast on glass
    // row.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];

    return row;
}

#pragma mark - VolumeSliderDelegate

// 5. IMPLEMENT the new delegate methods.
- (void)volumeSlider:(VolumeSlider *)slider didChangeValue:(double)value {
    // This is now the method that gets called during a drag.
    
    // Selector to match the protocol definition.
    if ([self.delegate respondsToSelector:@selector(hud:didChangeVolume:forPlayer:)]) {
        [self.delegate hud:self didChangeVolume:value forPlayer:self.controlledPlayer];
    }
    
    // Reset the auto-hide timer on every value change.
    [self.hideTimer invalidate];
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:1.2
                                                      target:self
                                                    selector:@selector(hide)
                                                    userInfo:nil
                                                     repeats:NO];
}

- (void)volumeSliderDidEndDragging:(VolumeSlider *)slider {
    if ([self.delegate respondsToSelector:@selector(didChangeVolumeFinal:)]) {
        [self.delegate didChangeVolumeFinal:self];
    }
    
    // You might also want to reset the hide timer here with a standard delay.
    [self.hideTimer invalidate];
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:kAutoHide
                                                      target:self
                                                    selector:@selector(hide)
                                                    userInfo:nil
                                                     repeats:NO];
}

@end
