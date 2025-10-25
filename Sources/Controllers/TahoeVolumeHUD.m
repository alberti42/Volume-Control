#import "TahoeVolumeHUD.h"
#import <AppKit/NSGlassEffectView.h> // macOS 26 SDK

@interface TahoeVolumeHUD ()
// Properties
@property (strong) NSPanel *panel;
@property (strong) NSView *root;
@property (strong) NSView *glass;
@property (strong) NSSlider *slider;
@property (strong) NSTimer *hideTimer;

#define HEIGHT_POPOVER 64
#define WIDTH_POPOVER 290
#define GAP_POPOVER 10

// Private methods (forward declarations)
- (void)installGlassInto:(NSView *)host cornerRadius:(CGFloat)radius;
- (void)positionPanelBelowStatusButton:(NSStatusBarButton *)button;
- (NSView *)buildSliderRow;
- (void)sliderChanged:(NSSlider *)sender;

// … your existing properties …
@property (strong, nonatomic) NSTimer *debugTimer;
@property (assign, nonatomic) NSInteger debugVariantIndex;
@property (assign, nonatomic) NSInteger debugScrim;
@property (assign, nonatomic) NSInteger debugSubdued;

- (void)startGlassDebugCycler;
- (void)stopGlassDebugCycler;
- (void)tickGlassDebugCycler:(NSTimer *)timer;
@end

@implementation TahoeVolumeHUD

- (void)startGlassDebugCycler {
    [self stopGlassDebugCycler];

    // Initialize from current values if present (best effort)
    @try {
        id v = [self.glass valueForKey:@"_variant"];
        id s = [self.glass valueForKey:@"_scrimState"];
        id d = [self.glass valueForKey:@"_subduedState"];
        self.debugVariantIndex = [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
        self.debugScrim        = [s respondsToSelector:@selector(integerValue)] ? [s integerValue] : 0;
        self.debugSubdued      = [d respondsToSelector:@selector(integerValue)] ? [d integerValue] : 0;
    } @catch (...) {
        self.debugVariantIndex = 0;
        self.debugScrim = 0;
        self.debugSubdued = 0;
    }

    // Fire every second on the main run loop
    self.debugTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                       target:self
                                                     selector:@selector(tickGlassDebugCycler:)
                                                     userInfo:nil
                                                      repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.debugTimer forMode:NSRunLoopCommonModes];
}

- (void)stopGlassDebugCycler {
    [self.debugTimer invalidate];
    self.debugTimer = nil;
}

- (void)tickGlassDebugCycler:(NSTimer *)timer {
    // Only meaningful on NSGlassEffectView
    if (![self.glass respondsToSelector:NSSelectorFromString(@"setContentView:")]) return;

    // Cycle: 0..23 variants (based on the mapping you have), toggle scrim/subdued
    self.debugVariantIndex = (self.debugVariantIndex + 1) % 30;
    self.debugScrim   = (self.debugScrim == 0) ? 1 : 0;
    self.debugSubdued = (self.debugSubdued == 0) ? 1 : 0;

    @try {
        [self.glass setValue:@(self.debugVariantIndex) forKey:@"_variant"];
        [self.glass setValue:@(self.debugScrim)        forKey:@"_scrimState"];
        [self.glass setValue:@(self.debugSubdued)      forKey:@"_subduedState"];
    } @catch (...) {
        // If any private key disappears in a future build, just ignore
    }

    // Read back (best effort) and log
    NSInteger v = self.debugVariantIndex, s = self.debugScrim, d = self.debugSubdued;
    @try {
        id rv = [self.glass valueForKey:@"_variant"];
        id rs = [self.glass valueForKey:@"_scrimState"];
        id rd = [self.glass valueForKey:@"_subduedState"];
        if ([rv respondsToSelector:@selector(integerValue)]) v = [rv integerValue];
        if ([rs respondsToSelector:@selector(integerValue)]) s = [rs integerValue];
        if ([rd respondsToSelector:@selector(integerValue)]) d = [rd integerValue];
    } @catch (...) {}

    NSLog(@"[GlassDebug] variant=%ld scrim=%ld subdued=%ld", (long)v, (long)s, (long)d);
}


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

    // Window: borderless, non-opaque, menu-level, non-activating popover-like panel
    NSRect frame = NSMakeRect(0, 0, WIDTH_POPOVER, HEIGHT_POPOVER);
    _panel = [[NSPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                                          backing:NSBackingStoreBuffered
                                            defer:NO];

    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = YES;
    _panel.hidesOnDeactivate = YES;
    _panel.level = NSPopUpMenuWindowLevel;
    _panel.movableByWindowBackground = NO;
    _panel.collectionBehavior = NSWindowCollectionBehaviorTransient |
                                 NSWindowCollectionBehaviorIgnoresCycle |
                                 NSWindowCollectionBehaviorFullScreenAuxiliary;
    _panel.floatingPanel = YES;
    _panel.becomesKeyOnlyIfNeeded = YES;

    // Fix height to HEIGHT_POPOVER, allow free width if you ever want it
    _panel.contentMinSize = NSMakeSize(WIDTH_POPOVER, HEIGHT_POPOVER);
    _panel.contentMaxSize = NSMakeSize(FLT_MAX, HEIGHT_POPOVER);
    [_panel setContentSize:NSMakeSize(WIDTH_POPOVER, HEIGHT_POPOVER)];

    // Root host (transparent)
    _root = [[NSView alloc] initWithFrame:_panel.contentView.bounds];
    _root.translatesAutoresizingMaskIntoConstraints = NO;
    _root.wantsLayer = YES;
    _root.layer.backgroundColor = NSColor.clearColor.CGColor;
    _panel.contentView = _root;

    NSLayoutConstraint *h = [_root.heightAnchor constraintEqualToConstant:HEIGHT_POPOVER];
    h.priority = 999;

    [NSLayoutConstraint activateConstraints:@[
        [_root.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor],
        [_root.trailingAnchor constraintEqualToAnchor:_panel.contentView.trailingAnchor],
        [_root.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor],
        [_root.bottomAnchor constraintEqualToAnchor:_panel.contentView.bottomAnchor],
        h
    ]];

    // Install glass
    [self installGlassInto:_root cornerRadius:24.0];
    
    // Start debug cycler only if this is a real NSGlassEffectView (macOS 26+)
    if ([self.glass respondsToSelector:NSSelectorFromString(@"setContentView:")]) {
//        [self startGlassDebugCycler];
    }


    // Build slider row
    NSView *row = [self buildSliderRow];

    if ([_glass respondsToSelector:NSSelectorFromString(@"setContentView:")]) {
        // NSGlassEffectView path (macOS 26)
        [_glass setValue:row forKey:@"contentView"];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:_glass.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:_glass.trailingAnchor],
            [row.topAnchor constraintEqualToAnchor:_glass.topAnchor],
            [row.bottomAnchor constraintEqualToAnchor:_glass.bottomAnchor],
        ]];
    } else {
        // Fallback path
        [_glass addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:_glass.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:_glass.trailingAnchor],
            [row.topAnchor constraintEqualToAnchor:_glass.topAnchor],
            [row.bottomAnchor constraintEqualToAnchor:_glass.bottomAnchor],
        ]];
    }

    return self;
}

#pragma mark - Public API

- (void)showHUDWithVolume:(double)volume anchoredToStatusButton:(NSStatusBarButton *)button {
    // Normalize volume (accept 0–100 or 0–1)
    if (volume > 1.0) volume = MAX(0.0, MIN(1.0, volume / 100.0));
    self.slider.doubleValue = volume;

    // Size (kept at HEIGHT_POPOVER height)
    NSRect f = self.panel.frame;
    f.size = NSMakeSize(MAX(WIDTH_POPOVER, f.size.width), HEIGHT_POPOVER);
    [self.panel setFrame:f display:NO];

    // Position directly beneath the status bar button
    [self positionPanelBelowStatusButton:button];

    [self.panel orderFront:nil];

    // Restart autohide timer (2s)
    [self.hideTimer invalidate];
//    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
//                                                      target:self
//                                                    selector:@selector(hide)
//                                                    userInfo:nil
//                                                     repeats:NO];
}

- (void)setVolume:(double)volume {
    if (volume > 1.0) volume = MAX(0.0, MIN(1.0, volume / 100.0));
    self.slider.doubleValue = volume;
}

- (void)hide {
    [self.panel orderOut:nil];
    [self.hideTimer invalidate];
    self.hideTimer = nil;
    
    [self stopGlassDebugCycler];
    
    if ([self.delegate respondsToSelector:@selector(hudDidHide:)]) {
        [self.delegate hudDidHide:self];
    }
}

#pragma mark - Layout / Anchoring

- (void)positionPanelBelowStatusButton:(NSStatusBarButton *)button {
    if (!button || !button.window) {
        // Fallback: center on main screen
        NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
        if (screen) {
            NSRect vis = screen.visibleFrame;
            CGFloat x = NSMidX(vis) - self.panel.frame.size.width/2.0;
            CGFloat y = NSMidY(vis) - self.panel.frame.size.height/2.0;
            [self.panel setFrameOrigin:NSMakePoint(round(x), round(y))];
        }
        return;
    }

    // Convert the button’s rect to screen coords
    NSRect buttonRectInWindow = [button convertRect:button.bounds toView:nil];
    NSRect buttonInScreen = [button.window convertRectToScreen:buttonRectInWindow];

    // Panel size and gap
    const CGFloat gap = 6.0 + GAP_POPOVER;
    NSSize panelSize = self.panel.frame.size;

    // Center under the button horizontally
    CGFloat x = NSMidX(buttonInScreen) - panelSize.width / 2.0;
    CGFloat y = NSMinY(buttonInScreen) - panelSize.height - gap;

    // Clamp to the visible frame of the *same* screen as the button
    NSScreen *targetScreen = button.window.screen ?: NSScreen.mainScreen;
    NSRect vis = targetScreen.visibleFrame;

    if (y < NSMinY(vis)) y = NSMinY(vis) + 2.0; // prevent clipping at bottom

    CGFloat margin = 8.0;
    x = MAX(NSMinX(vis) + margin, MIN(x, NSMaxX(vis) - margin - panelSize.width));

    [self.panel setFrameOrigin:NSMakePoint(round(x), round(y))];
}

#pragma mark - Glass

- (void)installGlassInto:(NSView *)host cornerRadius:(CGFloat)radius {
    NSView *glass = nil;

    if (@available(macOS 26.0, *)) {
        Class GlassCls = NSClassFromString(@"NSGlassEffectView");
        if (GlassCls) {
            NSView *g = [[GlassCls alloc] initWithFrame:host.bounds];
            g.translatesAutoresizingMaskIntoConstraints = NO;

            // Public API: Clear style, radius, subtle tint
            [g setValue:@(NSGlassEffectViewStyleClear) forKey:@"style"]; // Clear
            [g setValue:@(radius) forKey:@"cornerRadius"];
            [g setValue:[NSColor colorWithWhite:1.0 alpha:0.25] forKey:@"tintColor"];
            
            // Optional private tweaks (use at your own risk; see https://github.com/Meridius-Labs/electron-liquid-glass/blob/main/src/glass_effect.mm)
            /* From: https://github.com/Meridius-Labs/electron-liquid-glass/blob/main/js/variants.ts
             regular: 0,
             clear: 1,
             dock: 2,
             appIcons: 3,
             widgets: 4,
             text: 5,
             avplayer: 6,
             facetime: 7,
             controlCenter: 8,
             notificationCenter: 9,
             monogram: 10,
             bubbles: 11,
             identity: 12,
             focusBorder: 13,
             focusPlatter: 14,
             keyboard: 15,
             sidebar: 16,
             abuttedSidebar: 17,
             inspector: 18,
             control: 19,
             loupe: 20,
             slider: 21,
             camera: 22,
             cartouchePopover: 23,
             */
            [g setValue:@(19) forKey:@"_variant"];        // see mapping in
            [g setValue:@(0) forKey:@"_scrimState"];     // 0/1
            [g setValue:@(0) forKey:@"_subduedState"];   // 0/1
            
            [g setValue:@(YES) forKey:@"_useReducedShadowRadius"]; // smaller or sharper rim
            [g setValue:@(1)   forKey:@"_adaptiveAppearance"];     // adapts rim contrast to dark/light mode
            [g setValue:@(1)   forKey:@"_contentLensing"];         // if 1, simulates focus depth
            
            glass = g;
            
            // Add an inner border layer to simulate light rim
            CALayer *rim = [CALayer layer];
            rim.frame = glass.bounds;
            rim.cornerRadius = radius;
            rim.borderWidth = 10.0; // very thin
            rim.borderColor = [[NSColor colorWithWhite:1.0 alpha:0.25] CGColor]; // subtle white
            rim.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
            rim.masksToBounds = YES;

            rim.shadowColor = [NSColor.whiteColor CGColor];
            rim.shadowRadius = 4.0;
            rim.shadowOpacity = 0;
            rim.shadowOffset = CGSizeZero;

            [glass.layer addSublayer:rim];

        }
    }

    if (!glass) {
        // Fallback
        NSVisualEffectView *vev = [[NSVisualEffectView alloc] initWithFrame:host.bounds];
        vev.translatesAutoresizingMaskIntoConstraints = NO;
        vev.material = NSVisualEffectMaterialUnderWindowBackground;
        vev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        vev.state = NSVisualEffectStateActive;
        vev.wantsLayer = YES;
        vev.layer.masksToBounds = YES;
        vev.layer.cornerRadius = radius;
        glass = vev;
    }

    self.glass = glass;
    [host addSubview:glass];
    [NSLayoutConstraint activateConstraints:@[
        [glass.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [glass.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [glass.topAnchor constraintEqualToAnchor:host.topAnchor],
        [glass.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
    ]];
}

#pragma mark - Content

- (NSView *)buildSliderRow {
    NSView *row = [NSView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    [row setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationVertical];

    NSImageView *iconLeft = [NSImageView new];
    iconLeft.translatesAutoresizingMaskIntoConstraints = NO;
    iconLeft.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightSemibold];
    iconLeft.image = [NSImage imageWithSystemSymbolName:@"speaker.fill" accessibilityDescription:nil];
    iconLeft.contentTintColor = NSColor.labelColor;
    [iconLeft setContentHuggingPriority:251 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [iconLeft setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSImageView *iconRight = [NSImageView new];
    iconRight.translatesAutoresizingMaskIntoConstraints = NO;
    iconRight.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightSemibold];
    iconRight.image = [NSImage imageWithSystemSymbolName:@"speaker.wave.2.fill" accessibilityDescription:nil];
    iconRight.contentTintColor = NSColor.labelColor;
    [iconRight setContentHuggingPriority:251 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [iconRight setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSSlider *slider = [NSSlider sliderWithValue:0.6 minValue:0.0 maxValue:1.0 target:self action:@selector(sliderChanged:)];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.controlSize = NSControlSizeSmall;
    [slider setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [slider setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.slider = slider;

    [row addSubview:iconLeft];
    [row addSubview:slider];
    [row addSubview:iconRight];

    [NSLayoutConstraint activateConstraints:@[
        [iconLeft.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [iconLeft.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [iconRight.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [iconRight.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [slider.leadingAnchor constraintEqualToAnchor:iconLeft.trailingAnchor constant:8],
        [slider.trailingAnchor constraintEqualToAnchor:iconRight.leadingAnchor constant:-8],
        [slider.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];

    return row;
}

#pragma mark - Actions

- (void)sliderChanged:(NSSlider *)sender {
    double v = sender.doubleValue; // already 0..1
    if ([self.delegate respondsToSelector:@selector(hud:didChangeVolume:)]) {
        [self.delegate hud:self didChangeVolume:v];
    }
    // Keep the HUD visible a bit longer while interacting
    [self.hideTimer invalidate];
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:1.2
                                                      target:self
                                                    selector:@selector(hide)
                                                    userInfo:nil
                                                     repeats:NO];
}

@end
