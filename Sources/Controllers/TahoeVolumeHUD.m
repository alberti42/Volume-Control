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

// In TahoeVolumeHUD.m, inside @implementation HUDViewController

- (void)loadView {
    // 1. Get the private NSGlassEffectView class at runtime.
    Class GlassEffectViewClass = NSClassFromString(@"NSGlassEffectView");
    if (!GlassEffectViewClass) {
        // Fallback to a standard view if the private class is not found.
        self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 290, 65)];
        return;
    }

    // 2. Create an instance of NSGlassEffectView with the new dimensions.
    NSView *glassView = [[GlassEffectViewClass alloc] initWithFrame:NSMakeRect(0, 0, 290, 65)];
    
    // Configure the glass effect properties.
    // Variant 19 often works well for larger, horizontal HUDs. Feel free to experiment.
    [glassView setValue:@(19) forKey:@"_variant"];
    [glassView setValue:@(24.0) forKey:@"cornerRadius"]; // A larger radius for a wider view
    [glassView setValue:@(0) forKey:@"_scrimState"];
    [glassView setValue:@(0) forKey:@"_subduedState"];

    self.view = glassView;
    
    // 3. Create and configure the volume slider for HORIZONTAL display.
    _volumeSlider = [[NSSlider alloc] init];
    _volumeSlider.sliderType = NSSliderTypeLinear;
    // _volumeSlider.vertical = YES; // REMOVED - Horizontal is the default.
    _volumeSlider.minValue = 0.0;
    _volumeSlider.maxValue = 100.0;
    _volumeSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _volumeSlider.enabled = NO; // Display-only, not interactive

    // 4. Add the slider to the glass view's content using Auto Layout for proper padding.
    // The `contentView` property is the correct way to add content to NSGlassEffectView.
    // We add our slider directly to it and apply constraints.
    if ([glassView respondsToSelector:NSSelectorFromString(@"setContentView:")]) {
        // Create a simple container to hold the slider. This is the view we will constrain.
        NSView *contentContainer = [[NSView alloc] initWithFrame:self.view.bounds];
        contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
        
        // Add slider to the container
        [contentContainer addSubview:_volumeSlider];

        // Set the container as the glass effect's content view
        [(NSGlassEffectView *)glassView setContentView:contentContainer];

        // Apply constraints to position the slider within the container with padding
        [NSLayoutConstraint activateConstraints:@[
            // Center the slider vertically in the popover
            [_volumeSlider.centerYAnchor constraintEqualToAnchor:contentContainer.centerYAnchor],
            
            // Add 20 points of padding on the left and right sides
            [_volumeSlider.leadingAnchor constraintEqualToAnchor:contentContainer.leadingAnchor constant:20.0],
            [_volumeSlider.trailingAnchor constraintEqualToAnchor:contentContainer.trailingAnchor constant:-20.0]
        ]];
        
    } else {
        // Fallback for older systems or if setContentView fails: add as a direct subview.
        [self.view addSubview:_volumeSlider];
        [NSLayoutConstraint activateConstraints:@[
            [_volumeSlider.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
            [_volumeSlider.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20.0],
            [_volumeSlider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20.0]
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
