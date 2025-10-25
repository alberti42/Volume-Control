#import "GlassDemoWindowController.h"

@interface GlassDemoWindowController ()
@property (strong) NSView *root;
@property (strong) NSView *glass; // NSGlassEffectView if present, else NSVisualEffectView
@end

@implementation GlassDemoWindowController

+ (void)present {
    static GlassDemoWindowController *wc;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        wc = [[self alloc] init];
        [wc showWindow:nil];
    });
}

- (instancetype)init {
    // Start at 290×64
    NSRect frame = NSMakeRect(0, 0, 290, 64);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self = [super initWithWindow:w];
    if (!self) return nil;

    // Keep the content height exactly 64
    [w setContentSize:NSMakeSize(290, 64)];
    w.contentMinSize = NSMakeSize(290, 64);
    // (Optional) lock the height completely; uncomment if desired:
    // w.contentMaxSize = NSMakeSize(FLT_MAX, 64);

    // Critical for translucency
    w.opaque = NO;
    w.backgroundColor = NSColor.clearColor;
    w.hasShadow = YES;
    w.level = NSStatusWindowLevel;
    w.movableByWindowBackground = YES;

    // Transparent root host
    _root = [[NSView alloc] initWithFrame:w.contentView.bounds];
    _root.translatesAutoresizingMaskIntoConstraints = NO;
    _root.wantsLayer = YES;
    _root.layer.backgroundColor = NSColor.clearColor.CGColor;
    w.contentView = _root;

    [NSLayoutConstraint activateConstraints:@[
        [_root.leadingAnchor constraintEqualToAnchor:w.contentView.leadingAnchor],
        [_root.trailingAnchor constraintEqualToAnchor:w.contentView.trailingAnchor],
        [_root.topAnchor constraintEqualToAnchor:w.contentView.topAnchor],
        [_root.bottomAnchor constraintEqualToAnchor:w.contentView.bottomAnchor],
    ]];

    // Hard-target 64pt height on the host (avoid collapse)
    NSLayoutConstraint *rootH = [_root.heightAnchor constraintEqualToConstant:64];
    rootH.priority = 999;
    rootH.active = YES;

    // Install liquid glass (NSGlassEffectView 26+) or fallback (NSVisualEffectView)
    [self installGlassFillingView:_root cornerRadius:24.0];

    // Demo content: a single slider row
    NSView *row = [self buildSliderRow];

    if ([self.glass respondsToSelector:NSSelectorFromString(@"setContentView:")]) {
        // Real NSGlassEffectView path (macOS 26)
        [self.glass setValue:row forKey:@"contentView"];

        // Ensure the row fills the glass (edge-to-edge)
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.glass.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:self.glass.trailingAnchor],
            [row.topAnchor constraintEqualToAnchor:self.glass.topAnchor],
            [row.bottomAnchor constraintEqualToAnchor:self.glass.bottomAnchor],
        ]];
    } else {
        // Fallback path
        [self.glass addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.glass.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:self.glass.trailingAnchor],
            [row.topAnchor constraintEqualToAnchor:self.glass.topAnchor],
            [row.bottomAnchor constraintEqualToAnchor:self.glass.bottomAnchor],
        ]];
    }

    // Center on the main screen
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    if (screen) {
        NSRect vis = screen.visibleFrame;
        CGFloat x = NSMidX(vis) - frame.size.width/2.0;
        CGFloat y = NSMidY(vis) - frame.size.height/2.0;
        [w setFrameOrigin:NSMakePoint(round(x), round(y))];
    }

    return self;
}

- (void)installGlassFillingView:(NSView *)host cornerRadius:(CGFloat)radius {
    NSView *glass = nil;

    if (@available(macOS 26.0, *)) {
        Class GlassCls = NSClassFromString(@"NSGlassEffectView");
        if (GlassCls) {
            NSView *g = [[GlassCls alloc] initWithFrame:host.bounds];
            g.translatesAutoresizingMaskIntoConstraints = NO;

            // Public API
            [g setValue:@(1) forKey:@"style"];         // Clear
            [g setValue:@(radius) forKey:@"cornerRadius"];
            [g setValue:[NSColor colorWithCalibratedWhite:0 alpha:0.06] forKey:@"tintColor"];

            // PRIVATE (optional)
            // [g setValue:@(23) forKey:@"_variant"];   // cartouchePopover
            // [g setValue:@(1)  forKey:@"_scrimState"];

            glass = g;
        }
    }

    if (!glass) {
        // Fallback on macOS < 26
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

- (NSView *)buildSliderRow {
    NSView *row = [NSView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    // Let it stretch vertically with the 64pt host
    [row setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    [row setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationVertical];

    // Left icon (speaker base)
    NSImageView *iconLeft = [NSImageView new];
    iconLeft.translatesAutoresizingMaskIntoConstraints = NO;
    iconLeft.symbolConfiguration =
        [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightSemibold];
    iconLeft.image = [NSImage imageWithSystemSymbolName:@"speaker.fill" accessibilityDescription:nil];
    iconLeft.contentTintColor = NSColor.labelColor;
    [iconLeft setContentHuggingPriority:251 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [iconLeft setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationHorizontal];

    // Right icon (speaker + waves)
    NSImageView *iconRight = [NSImageView new];
    iconRight.translatesAutoresizingMaskIntoConstraints = NO;
    iconRight.symbolConfiguration =
        [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightSemibold];
    iconRight.image = [NSImage imageWithSystemSymbolName:@"speaker.wave.2.fill" accessibilityDescription:nil];
    iconRight.contentTintColor = NSColor.labelColor;
    [iconRight setContentHuggingPriority:251 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [iconRight setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationHorizontal];

    // Slider (expands)
    NSSlider *slider = [NSSlider sliderWithValue:0.6 minValue:0.0 maxValue:1.0 target:self action:@selector(sliderChanged:)];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.controlSize = NSControlSizeSmall;
    [slider setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [slider setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    [row addSubview:iconLeft];
    [row addSubview:slider];
    [row addSubview:iconRight];

    [NSLayoutConstraint activateConstraints:@[
        // Horizontal layout
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

- (void)sliderChanged:(NSSlider *)s {
    // Hook your Apple Music volume here
}

@end
