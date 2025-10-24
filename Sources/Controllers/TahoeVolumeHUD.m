//
//  TahoeVolumeHUD.m
//  Volume Control
//
//  Created by AI Assistant on 24.10.25.
//

#import "TahoeVolumeHUD.h"

#pragma mark - HUD Content View Controller

// A private view controller to manage the content of our popover.
API_AVAILABLE(macos(16.0))
@interface HUDViewController : NSViewController
@property (nonatomic, strong, readonly) NSSlider *volumeSlider;
@end

@implementation HUDViewController

- (void)loadView {
    // 1. Get the private NSGlassEffectView class at runtime.
    Class GlassEffectViewClass = NSClassFromString(@"NSGlassEffectView");
    if (!GlassEffectViewClass) {
        // Fallback to a standard view if the private class is not found.
        self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 40, 140)];
        return;
    }

    // 2. Create an instance of NSGlassEffectView.
    // We use KVC (setValue:forKey:) to configure its private properties.
    NSView *glassView = [[GlassEffectViewClass alloc] initWithFrame:NSMakeRect(0, 0, 40, 140)];
    [glassView setValue:@(10) forKey:@"_variant"]; // Experiment with variants (0-19) for different looks. 10 is a good starting point.
    [glassView setValue:@(18.0) forKey:@"cornerRadius"];
    [glassView setValue:@(0) forKey:@"_scrimState"]; // Scrim overlay off
    [glassView setValue:@(0) forKey:@"_subduedState"]; // Normal (not subdued) state

    self.view = glassView;
    
    // 3. Create and configure the volume slider.
    _volumeSlider = [[NSSlider alloc] init];
    _volumeSlider.sliderType = NSSliderTypeLinear;
    _volumeSlider.vertical = YES;
    _volumeSlider.minValue = 0.0;
    _volumeSlider.maxValue = 100.0;
    _volumeSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _volumeSlider.enabled = NO; // Display-only, not interactive

    // 4. Add the slider to the glass view's content.
    // The provided snippets suggest setting `contentView`. If that fails, `addSubview:` is the fallback.
    if ([glassView respondsToSelector:NSSelectorFromString(@"setContentView:")]) {
        [(NSGlassEffectView *)glassView setContentView:_volumeSlider];
    } else {
        [self.view addSubview:_volumeSlider];
        // Center the slider if we added it as a plain subview
        [NSLayoutConstraint activateConstraints:@[
            [_volumeSlider.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [_volumeSlider.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
            [_volumeSlider.heightAnchor constraintEqualToConstant:100]
        ]];
    }
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
