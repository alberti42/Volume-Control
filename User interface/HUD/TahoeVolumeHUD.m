// FILE: TahoeVolumeHUD.m

#import "TahoeVolumeHUD.h"
#import <AppKit/NSGlassEffectView.h>
#import "HUDPanel.h"
#import "AppDelegate.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

// Product Module Name: Volume_Control
#import "Volume_Control-Swift.h"  // exposes LiquidGlassView to ObjC

@interface TahoeVolumeHUD ()

// Window + layout
@property (strong) HUDPanel *panel;
@property (strong) NSView *root;
@property (strong) LiquidGlassView *glass;

// UI
@property (strong) HUDVolumeSlider *slider;
@property (strong) NSImageView *appIconView;
@property (strong) NSTimer *hideTimer;
@property (strong) NSTextField *titleLabel;

// Constraints
@property (strong) NSLayoutConstraint *contentFixedHeight;

// Player
@property (strong) PlayerApplication *controlledPlayer;

// Test build: index into kVariants, and the other variants shown with the shared HUD
@property (assign) NSInteger variantIndex;
@property (strong) NSArray<TahoeVolumeHUD *> *galleryHUDs;

@end

// Test build for issue #60: each volume key press shows one HUD per entry of kVariants,
// in a grid under the menu bar, so one screenshot compares all of them.
#define HUD_VARIANT_GALLERY 1

typedef NS_ENUM(NSInteger, HUDContent) {
    HUDContentDark,    // NSAppearanceNameVibrantDark, white slider (the shipping HUD)
    HUDContentSystem,  // follows the system appearance, default slider tint
    HUDContentLight,   // NSAppearanceNameAqua, default slider tint
};

typedef struct {
    NSGlassEffectViewStyle style;
    BOOL privateSettings;  // NO leaves every private NSGlassEffectView setting at its default
    NSInteger variant;
    NSInteger adaptiveAppearance;  // 0 automatic, 1 off, 2 on
    NSInteger scrimState;
    CGFloat tintWhite;  // grey level of the tint, 0 black
    CGFloat tintAlpha;  // 0 for no tint
    HUDContent content;
    const char *name;
} HUDVariant;

static const HUDVariant kVariants[] = {
    { NSGlassEffectViewStyleRegular, YES, 9, 0, 0, 0.0, 0.40, HUDContentDark, "black 40% (round 1, 9)" },
    { NSGlassEffectViewStyleRegular, YES, 9, 0, 0, 0.0, 0.25, HUDContentDark, "black 25%" },
    { NSGlassEffectViewStyleRegular, YES, 9, 0, 0, 0.0, 0.30, HUDContentDark, "black 30%" },
    { NSGlassEffectViewStyleRegular, YES, 9, 0, 0, 0.0, 0.35, HUDContentDark, "black 35%" },
    { NSGlassEffectViewStyleRegular, YES, 9, 0, 0, 0.0, 0.45, HUDContentDark, "black 45%" },
    { NSGlassEffectViewStyleRegular, YES, 9, 0, 0, 0.0, 0.50, HUDContentDark, "black 50%" },
    { NSGlassEffectViewStyleRegular, YES, 9, 0, 0, 0.5, 0.30, HUDContentDark, "grey 50% at 30%" },
    { NSGlassEffectViewStyleRegular, YES, 9, 0, 0, 0.5, 0.40, HUDContentDark, "grey 50% at 40%" },
    { NSGlassEffectViewStyleRegular, YES, 9, 0, 0, 0.5, 0.50, HUDContentDark, "grey 50% at 50%" },
    { NSGlassEffectViewStyleRegular, YES, 9, 0, 0, 0.35, 0.40, HUDContentDark, "grey 35% at 40%" },
    { NSGlassEffectViewStyleRegular, YES, 9, 0, 0, 0.35, 0.50, HUDContentDark, "grey 35% at 50%" },
    { NSGlassEffectViewStyleRegular, YES, 9, 0, 0, 0.0, 0.0, HUDContentDark, "no tint (2.7.0)" },
};
static const NSInteger kVariantCount = sizeof(kVariants) / sizeof(kVariants[0]);
static const NSInteger kGalleryColumns = 3;
static const NSTimeInterval kGalleryAutoHide = 8.0;

// Tunables
static const CGFloat kHUDHeight      = 64.0;
static const CGFloat kHUDWidth       = 292.0;  // measured from the system volume HUD on macOS 27.0.1
// Transparent margin between the glass and the panel's edges. The glass draws its
// outermost pixels half outside its shape; a panel exactly the size of the glass clips
// them, which removes the dark edge line on the sides and tightens the corners by 1 px.
// The system HUD's window (352 pt wide) leaves room on every side as well.
static const CGFloat kPanelPadding   = 20.0;
static const CGFloat kCornerRadius   = 24.0;
static const CGFloat kBelowGap       = 14.0;
static const NSTimeInterval kAutoHide = 1.5;
static const CGFloat kSideInset  = 12.0;  // left/right margin
// pt below the menu bar when no usable anchor. ControlCenter passes menu bar height + 10
// as the system volume HUD's top margin; with a 30 pt menu bar both HUDs measure 40 pt
// below the screen top (macOS 27.0.1).
static const CGFloat kTopMarginWhenUnanchored = 10.0;

static const NSTimeInterval kFadeInDuration  = 0.25; // seconds
static const NSTimeInterval kFadeOutDuration = 0.45; // seconds

// Returns the height of `screen`'s menu bar when it is shown, also while it is hidden.
// ControlCenter places the system volume HUD with -[NSScreen _revealedMenuBarHeight]
// (30 pt where NSStatusBar.thickness is 22 pt, on macOS 27.0.1). Without that private
// method, use the space the menu bar reserves in visibleFrame, or the status bar
// thickness while the menu bar is hidden.
static CGFloat menuBarHeightOfScreen(NSScreen *screen) {
    SEL sel = NSSelectorFromString(@"_revealedMenuBarHeight");
    if ([screen respondsToSelector:sel]) {
        CGFloat height = ((CGFloat (*)(id, SEL))objc_msgSend)(screen, sel);
        if (height > 0) return height;
    }
    CGFloat reserved = NSMaxY(screen.frame) - NSMaxY(screen.visibleFrame);
    return reserved >= 1.0 ? reserved : [NSStatusBar systemStatusBar].thickness;
}

// Returns YES while the window server draws a menu bar on `screen`. Its menu bar
// window (owner "Window Server", layer kCGMainMenuWindowLevel) is in the on-screen
// window list only while the bar is drawn; with "Automatically hide and show the
// menu bar" on, it disappears when the bar hides. Owner name and layer are readable
// without Screen Recording permission; the window name is not.
static BOOL menuBarIsDrawnOnScreen(NSScreen *screen) {
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (!list) return NO;
    // Window-list bounds have their origin at the top-left of the primary screen.
    CGFloat primaryHeight = NSMaxY(NSScreen.screens.firstObject.frame);
    BOOL found = NO;
    for (NSDictionary *info in (__bridge NSArray *)list) {
        if ([info[(id)kCGWindowLayer] integerValue] != kCGMainMenuWindowLevel) continue;
        if (![info[(id)kCGWindowOwnerName] isEqualToString:@"Window Server"]) continue;
        CGRect bounds;
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds)) continue;
        NSRect inScreen = NSMakeRect(bounds.origin.x, primaryHeight - CGRectGetMaxY(bounds), bounds.size.width, bounds.size.height);
        if (NSIntersectsRect(inScreen, screen.frame)) { found = YES; break; }
    }
    CFRelease(list);
    return found;
}

@implementation TahoeVolumeHUD

+ (TahoeVolumeHUD *)sharedManager {
    static TahoeVolumeHUD *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TahoeVolumeHUD alloc] initWithVariant:0];
#if HUD_VARIANT_GALLERY
        NSMutableArray *others = [NSMutableArray array];
        for (NSInteger i = 1; i < kVariantCount; i++) {
            [others addObject:[[TahoeVolumeHUD alloc] initWithVariant:i]];
        }
        instance.galleryHUDs = others;
#endif
    });
    return instance;
}

- (instancetype)initWithVariant:(NSInteger)variantIndex {
    self = [super init];
    if (!self) return nil;
    _variantIndex = variantIndex;
    HUDVariant v = kVariants[variantIndex];
    NSAppearance *contentAppearance = (v.content == HUDContentDark)  ? [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]
                                    : (v.content == HUDContentLight) ? [NSAppearance appearanceNamed:NSAppearanceNameAqua]
                                    : nil;

    // ... (this part is correct) ...
    // Panel
    NSSize panelSize = NSMakeSize(kHUDWidth + 2 * kPanelPadding, kHUDHeight + 2 * kPanelPadding);
    NSRect frame = NSMakeRect(0, 0, panelSize.width, panelSize.height);
    _panel = [[HUDPanel alloc] initWithContentRect:frame
                                         styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = NO;
    _panel.appearance = contentAppearance;

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
    _panel.contentMinSize = panelSize;
    _panel.contentMaxSize = NSMakeSize(FLT_MAX, panelSize.height);
    [_panel setContentSize:panelSize];

    // Root host
    _root = [[NSView alloc] initWithFrame:_panel.contentView.bounds];
    _root.translatesAutoresizingMaskIntoConstraints = NO;
    _root.wantsLayer = YES;
    _root.layer.backgroundColor = NSColor.clearColor.CGColor;
    _panel.contentView = _root;

    // Hard height on the window contentView — guarantees the panel height regardless of fitting sizes
    self.contentFixedHeight = [_panel.contentView.heightAnchor constraintEqualToConstant:panelSize.height];
    self.contentFixedHeight.priority = 1000;
    self.contentFixedHeight.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [_root.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor],
        [_root.trailingAnchor constraintEqualToAnchor:_panel.contentView.trailingAnchor],
        [_root.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor],
        [_root.bottomAnchor constraintEqualToAnchor:_panel.contentView.bottomAnchor],
    ]];

    // The glass fills glassHost, which is inset by kPanelPadding. (LiquidGlassView pins
    // itself to its superview's edges, so the inset goes on the host.)
    NSView *glassHost = [NSView new];
    glassHost.translatesAutoresizingMaskIntoConstraints = NO;
    [_root addSubview:glassHost];
    [NSLayoutConstraint activateConstraints:@[
        [glassHost.leadingAnchor constraintEqualToAnchor:_root.leadingAnchor constant:kPanelPadding],
        [glassHost.trailingAnchor constraintEqualToAnchor:_root.trailingAnchor constant:-kPanelPadding],
        [glassHost.topAnchor constraintEqualToAnchor:_root.topAnchor constant:kPanelPadding],
        [glassHost.bottomAnchor constraintEqualToAnchor:_root.bottomAnchor constant:-kPanelPadding],
    ]];

    // Glass (Swift class)
    [self installGlassInto:glassHost cornerRadius:kCornerRadius];
    
    // Content wrapper (fills the glass)
    NSView *wrapper = [NSView new];
    wrapper.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 1 of 3: Set the appearance for the entire content view.
    // This forces all subviews (labels, icons) to use their dark variants.
    wrapper.appearance = contentAppearance;
    
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

    self.slider.whiteTint = (v.content == HUDContentDark);


    return self;
}

#pragma mark - Public API

- (void)showHUDWithVolume:(double)volume usingMusicPlayer:(PlayerApplication*)player andLabel:(NSString*)label anchoredToStatusButton:(NSStatusBarButton *)button {
    self.controlledPlayer = player;

    volume = MAX(0.0, MIN(1.0, volume / 100.0));
    self.slider.doubleValue = volume;
    
    // Update header
    self.appIconView.image = [player icon];
    self.titleLabel.stringValue = label;
#if HUD_VARIANT_GALLERY
    self.titleLabel.stringValue = [NSString stringWithFormat:@"%ld · %s", (long)self.variantIndex, kVariants[self.variantIndex].name];
#endif

    // Size fence each time
    [_panel setContentSize:NSMakeSize(kHUDWidth + 2 * kPanelPadding, kHUDHeight + 2 * kPanelPadding)];

#if HUD_VARIANT_GALLERY
    [self positionPanelInGallery];
    for (TahoeVolumeHUD *hud in self.galleryHUDs) {
        [hud showHUDWithVolume:volume * 100.0 usingMusicPlayer:player andLabel:label anchoredToStatusButton:button];
    }
#else
    [self positionPanelBelowStatusButton:button];
#endif
    
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
#if HUD_VARIANT_GALLERY
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:kGalleryAutoHide
#else
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:kAutoHide
#endif
                                                      target:self
                                                    selector:@selector(hide)
                                                    userInfo:nil
                                                     repeats:NO];
}


- (void)setVolume:(double)volume {
    for (TahoeVolumeHUD *hud in self.galleryHUDs) [hud setVolume:volume];
    volume = MAX(0.0, MIN(1.0, volume / 100.0));
    self.slider.doubleValue = volume;
}

- (void)hide {
    // Invalidate the timer to prevent this method from being called again
    [self.hideTimer invalidate];
    self.hideTimer = nil;
    for (TahoeVolumeHUD *hud in self.galleryHUDs) [hud hide];

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

// Test build: places variant variantIndex in a grid of kGalleryColumns columns,
// centred on the main screen, its top row where the unanchored HUD goes.
- (void)positionPanelInGallery {
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    if (!screen) return;
    NSRect full = screen.frame;
    CGFloat spacing = 10.0;
    NSInteger column = self.variantIndex % kGalleryColumns;
    NSInteger row = self.variantIndex / kGalleryColumns;
    CGFloat gridWidth = kGalleryColumns * kHUDWidth + (kGalleryColumns - 1) * spacing;
    CGFloat x = NSMidX(full) - gridWidth / 2.0 + column * (kHUDWidth + spacing);
    CGFloat topEdge = NSMaxY(full) - menuBarHeightOfScreen(screen) - kTopMarginWhenUnanchored;
    CGFloat y = topEdge - kHUDHeight - row * (kHUDHeight + spacing);
    [self.panel setFrame:NSInsetRect(NSMakeRect(round(x), round(y), kHUDWidth, kHUDHeight), -kPanelPadding, -kPanelPadding) display:NO];
}

- (void)positionPanelBelowStatusButton:(NSStatusBarButton *)button {
    NSSize size = NSMakeSize(kHUDWidth, kHUDHeight);

    // Decide whether the button is a usable anchor. The HUD caller passes nil when
    // the status item is intentionally hidden (e.g. "Hide from Status Bar"). We also
    // treat the button as unusable if:
    //   - its window was ordered out;
    //   - its on-screen rect does not intersect the screen's frame. This covers
    //     Ice/Bartender, which move the status window off-screen horizontally, and
    //     the auto-hidden menu bar on macOS 26, where the status item's window sits
    //     above the screen top while the bar is hidden;
    //   - the menu bar is set to hide automatically and is not drawn right now. On
    //     macOS 27 the status item's window stays at its revealed position while the
    //     bar is hidden, so only the window server's menu bar window tells the two
    //     states apart.
    // When the user hovers to reveal the auto-hidden menu bar, none of these fire
    // and the HUD anchors under the icon, matching the system HUD.
    BOOL useAnchor = (button != nil) && (button.window != nil) && button.window.isVisible;
    NSRect buttonInScreen = NSZeroRect;
    NSScreen *target = nil;

    if (useAnchor) {
        NSRect buttonRectInWindow = [button convertRect:button.bounds toView:nil];
        buttonInScreen = [button.window convertRectToScreen:buttonRectInWindow];
        target = button.window.screen ?: NSScreen.mainScreen;
        BOOL menuBarAutoHides = (NSMaxY(target.frame) - NSMaxY(target.visibleFrame)) < 1.0;
        if (!NSIntersectsRect(target.frame, buttonInScreen)) {
            useAnchor = NO;
        } else if (menuBarAutoHides && !menuBarIsDrawnOnScreen(target)) {
            useAnchor = NO;
        }
    }

    if (!useAnchor) {
        NSScreen *screen = target ?: NSScreen.mainScreen ?: NSScreen.screens.firstObject;
        if (!screen) return;
        NSRect full = screen.frame;
        // The HUD's top sits kTopMarginWhenUnanchored below the menu bar, at the same
        // screen position whether the menu bar is shown or hidden, as the system HUD does.
        CGFloat topEdge = NSMaxY(full) - menuBarHeightOfScreen(screen);
        CGFloat x = NSMidX(full) - size.width / 2.0;
        CGFloat y = topEdge - size.height - kTopMarginWhenUnanchored;
        [self.panel setFrame:NSInsetRect(NSMakeRect(round(x), round(y), size.width, size.height), -kPanelPadding, -kPanelPadding) display:NO];
        return;
    }

    CGFloat x = NSMidX(buttonInScreen) - size.width / 2.0;
    CGFloat y = NSMinY(buttonInScreen) - size.height - kBelowGap;

    NSRect vis = target.visibleFrame;
    if (y < NSMinY(vis)) y = NSMinY(vis) + 2.0;

    CGFloat margin = 8.0;
    x = MAX(NSMinX(vis) + margin, MIN(x, NSMaxX(vis) - margin - size.width));

    [self.panel setFrame:NSInsetRect(NSMakeRect(round(x), round(y), size.width, size.height), -kPanelPadding, -kPanelPadding) display:NO];
}

#pragma mark - Glass

- (void)installGlassInto:(NSView *)host cornerRadius:(CGFloat)radius {
    if (@available(macOS 26.0, *)) {
        HUDVariant v = kVariants[self.variantIndex];
        NSColor *tint = v.tintAlpha > 0 ? [NSColor colorWithCalibratedWhite:v.tintWhite alpha:v.tintAlpha] : nil;
        LiquidGlassView *glass = [LiquidGlassView glassWithStyle:v.style
                                                    cornerRadius:radius
                                                       tintColor:tint];
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
        
        // Variant 9 with the Regular style gives the same glassBackground filter
        // parameters as SwiftUI's _Glass.controlCenter, which ControlCenter uses
        // for the system volume banner (checked on macOS 27.0.1).
        if (v.privateSettings) {
            [glass setVariantIfAvailable:v.variant];
            [glass setScrimStateIfAvailable:v.scrimState];
            [glass setSubduedStateIfAvailable:0];

            // 0 automatic, 1 off, 2 on (from _adaptationDebugDescription, macOS 27.0.1).
            [glass setAdaptiveAppearanceIfAvailable:v.adaptiveAppearance];
            [glass setUseReducedShadowRadiusIfAvailable:YES];
            [glass setContentLensingIfAvailable:0];
        }
    } else {
        // Fallback on earlier versions
    }
    
    // Optional SwiftUI-like post-filters:
    //[glass applyVisualAdjustmentsWithSaturation:1.5 brightness:0.2 blur:0.25];
}

#pragma mark - Content


// In TahoeVolumeHUD.m

- (NSView *)buildSliderStrip {
    NSView *strip = [NSView new];
    strip.translatesAutoresizingMaskIntoConstraints = NO;

    // SwiftUI slider with the speaker icons and tick marks of the system volume HUD.
    HUDVolumeSlider *slider = [[HUDVolumeSlider alloc] initWithFrame:NSZeroRect];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.doubleValue = 0.6;
    __weak typeof(self) weakSelf = self;
    slider.onValueChanged = ^(double value) { [weakSelf sliderDidChangeValue:value]; };
    slider.onEditingEnded = ^{ [weakSelf sliderDidEndDragging]; };
    self.slider = slider;

    [strip addSubview:slider];

    // Insets and the 4 pt upward offset put the icons and the track where the system
    // volume HUD draws them (measured on macOS 27.0.1).
    [NSLayoutConstraint activateConstraints:@[
        [strip.heightAnchor constraintEqualToConstant:36],

        [slider.leadingAnchor constraintEqualToAnchor:strip.leadingAnchor constant:14],
        [slider.trailingAnchor constraintEqualToAnchor:strip.trailingAnchor constant:-14],
        [slider.centerYAnchor constraintEqualToAnchor:strip.centerYAnchor constant:-4],
        [slider.heightAnchor constraintEqualToAnchor:strip.heightAnchor],
    ]];

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
    // The system volume HUD's title uses Font.system(.callout, weight: .medium)
    // (checked on macOS 27.0.1); .callout is 12 pt on macOS.
    CGFloat calloutSize = [NSFont preferredFontForTextStyle:NSFontTextStyleCallout options:@{}].pointSize;
    self.titleLabel.font = [NSFont systemFontOfSize:calloutSize weight:NSFontWeightMedium];
    self.titleLabel.textColor = [NSColor labelColor];

    [row addSubview:self.appIconView];
    [row addSubview:self.titleLabel];

    // New constraints for better padding and alignment.
    // Puts the title's centre 18.5 pt below the top of the glass, where the system
    // volume HUD draws its title (measured on macOS 27.0.1).
    CGFloat topPadding = 9.5;
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

#pragma mark - Slider callbacks

// Called on every change the user makes while dragging.
- (void)sliderDidChangeValue:(double)value {
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

- (void)sliderDidEndDragging {
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
