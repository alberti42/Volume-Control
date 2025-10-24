//
//  TahoeVolumeHUD.m
//  Volume Control
//
//  Created by AI Assistant on 24.10.25.
//

#import "TahoeVolumeHUD.h"
#import "CustomGlassEffectView.h"

#pragma mark - HUD Content View Controller

// A private view controller to manage the content of our popover.
API_AVAILABLE(macos(16.0))
@interface HUDViewController : NSViewController
@property (nonatomic, strong, readonly) NSSlider *volumeSlider;
@end

@implementation HUDViewController

// In TahoeVolumeHUD.m, inside @implementation HUDViewController


- (void)loadView {
    // 1. Create an instance of our component with the complete set of parameters.
    CustomGlassEffectView *customGlassView = [[CustomGlassEffectView alloc]
        initWithFrame:NSMakeRect(0, 0, 290, 65)
              variant:19                      // Visual style
           scrimState:0                       // No overlay
         subduedState:0                       // Normal state
     interactionState:0                       // Not interactive
       contentLensing:1                       // <<< THE MAGIC: Turn ON the liquid/lensing effect
   adaptiveAppearance:1                       // Good practice for light/dark mode
 useReducedShadowRadius:0                     // Use the full, default shadow
                style:NSGlassEffectViewStyleClear // <<< CRITICAL: For translucency
         cornerRadius:24.0];
    
    // 2. Set it as the main view for this controller.
    self.view = customGlassView;

    // 3. Create and configure the slider... (rest of the code is the same)
    _volumeSlider = [[NSSlider alloc] init];
    _volumeSlider.sliderType = NSSliderTypeLinear;
    _volumeSlider.minValue = 0.0;
    _volumeSlider.maxValue = 100.0;
    _volumeSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _volumeSlider.enabled = NO;

    NSView *contentContainer = [[NSView alloc] init];
    [contentContainer addSubview:_volumeSlider];
    
    customGlassView.contentView = contentContainer;

    [NSLayoutConstraint activateConstraints:@[
        [_volumeSlider.centerYAnchor constraintEqualToAnchor:contentContainer.centerYAnchor],
        [_volumeSlider.leadingAnchor constraintEqualToAnchor:contentContainer.leadingAnchor constant:20.0],
        [_volumeSlider.trailingAnchor constraintEqualToAnchor:contentContainer.trailingAnchor constant:-20.0]
    ]];
}

@end


#pragma mark - TahoeVolumeHUD Implementation

API_AVAILABLE(macos(16.0))
@implementation TahoeVolumeHUD
{
    NSPopover *_popover;
    HUDViewController *_hudVC;
    NSTimer *_hideTimer;
}

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
    if (self) {
        _popover = [[NSPopover alloc] init];
        _popover.behavior = NSPopoverBehaviorTransient;
        _popover.animates = YES;
        
        // REMOVE THIS LINE. This was forcing the popover's window to be opaque.
        // _popover.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        
        _hudVC = [[HUDViewController alloc] init];
        _popover.contentViewController = _hudVC;
    }
    return self;
}


- (void)showHUDWithVolume:(double)volume anchoredToView:(NSView *)view {
    // Invalidate any existing hide timer.
    [_hideTimer invalidate];
    _hideTimer = nil;
    
    // Update the slider's value.
    _hudVC.volumeSlider.doubleValue = volume;

    // Show the popover if it's not already visible.
    if (!_popover.isShown) {
        [_popover showRelativeToRect:view.bounds ofView:view preferredEdge:NSRectEdgeMinY];
    }
    
    // Set a timer to automatically hide the popover after 2 seconds.
    _hideTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                  target:self
                                                selector:@selector(hideHUD)
                                                userInfo:nil
                                                 repeats:NO];
}

- (void)hideHUD {
    [_popover performClose:nil];
    _hideTimer = nil;
}

@end
