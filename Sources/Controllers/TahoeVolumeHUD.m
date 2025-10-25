//
//  TahoeVolumeHUD.m
//  Volume Control
//

#import "TahoeVolumeHUD.h"
#import "CustomGlassEffectView.h"

@interface TahoeVolumeHUD ()
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) CustomGlassEffectView *glassContainer;
@property (nonatomic, strong) NSSlider *slider;
@property (nonatomic, strong) NSTimer *hideTimer;
@end

@implementation TahoeVolumeHUD

+ (instancetype)sharedManager {
    static TahoeVolumeHUD *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 290, 65)
                                                styleMask:(NSWindowStyleMaskBorderless |
                                                           NSWindowStyleMaskNonactivatingPanel)  // 👈 non-activating
                                                  backing:NSBackingStoreBuffered
                                                    defer:YES];

    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.hasShadow = YES;
    panel.hidesOnDeactivate = YES;

    // Correct level constant:
    panel.level = NSPopUpMenuWindowLevel;

    panel.collectionBehavior = NSWindowCollectionBehaviorTransient |
                               NSWindowCollectionBehaviorIgnoresCycle |
                               NSWindowCollectionBehaviorFullScreenAuxiliary;

    panel.movableByWindowBackground = NO;

    // Also helps keep it from taking focus:
    panel.floatingPanel = YES;
    panel.becomesKeyOnlyIfNeeded = YES;

    // Transparent root
    NSView *root = [[NSView alloc] initWithFrame:panel.contentView.bounds];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.wantsLayer = YES;
    root.layer.backgroundColor = NSColor.clearColor.CGColor;
    panel.contentView = root;

    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:panel.contentView.bottomAnchor],
    ]];

    // Glass backdrop
    CustomGlassEffectView *glass = [[CustomGlassEffectView alloc]
        initWithFrame:root.bounds
              variant:2
           scrimState:1
         subduedState:0
     interactionState:0
       contentLensing:1
   adaptiveAppearance:1
 useReducedShadowRadius:0
                style:NSGlassEffectViewStyleClear
         cornerRadius:14.0];
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:glass positioned:NSWindowBelow relativeTo:nil];

    [NSLayoutConstraint activateConstraints:@[
        [glass.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [glass.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [glass.topAnchor constraintEqualToAnchor:root.topAnchor],
        [glass.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];

    // Foreground content
    NSSlider *slider = [NSSlider sliderWithValue:50 minValue:0 maxValue:100 target:nil action:NULL];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.enabled = YES;

    NSView *contentContainer = [NSView new];
    contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [contentContainer addSubview:slider];

    [NSLayoutConstraint activateConstraints:@[
        [slider.centerYAnchor constraintEqualToAnchor:contentContainer.centerYAnchor],
        [slider.leadingAnchor constraintEqualToAnchor:contentContainer.leadingAnchor constant:20.0],
        [slider.trailingAnchor constraintEqualToAnchor:contentContainer.trailingAnchor constant:-20.0],
    ]];

    // Let the glass own the content hierarchy
    glass.contentView = contentContainer;

    _panel = panel;
    _glassContainer = glass;
    _slider = slider;

    return self;
}

- (void)showHUDWithVolume:(double)volume anchoredToView:(NSView *)view {
    [self.hideTimer invalidate];
    self.hideTimer = nil;

    self.slider.doubleValue = volume;

    // Ensure size
    NSRect frame = self.panel.frame;
    frame.size = NSMakeSize(290, 65);
    [self.panel setFrame:frame display:NO];

    // Position like a popover under the anchor
    if (view.window) {
        NSRect anchorRectInWindow = [view convertRect:view.bounds toView:nil];
        NSRect screenRect = [view.window convertRectToScreen:anchorRectInWindow];

        CGFloat x = NSMidX(screenRect) - frame.size.width / 2.0;
        CGFloat y = NSMinY(screenRect) - frame.size.height - 8.0;
        [self.panel setFrameOrigin:NSMakePoint(round(x), round(y))];
    } else {
        NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
        if (screen) {
            NSRect vis = screen.visibleFrame;
            CGFloat x = NSMidX(vis) - frame.size.width/2.0;
            CGFloat y = NSMidY(vis) - frame.size.height/2.0;
            [self.panel setFrameOrigin:NSMakePoint(round(x), round(y))];
        }
    }

    [self.panel orderFront:nil];

    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                      target:self
                                                    selector:@selector(hideHUD)
                                                    userInfo:nil
                                                     repeats:NO];
}

- (void)hideHUD {
    [self.panel orderOut:nil];
    self.hideTimer = nil;
}

@end
