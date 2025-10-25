//
//  TahoeVolumeHUD.h
//  Volume Control
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Displays a modern Tahoe-style translucent HUD for volume feedback.
/// Uses a custom borderless NSPanel with NSGlassEffectView backdrop.
API_AVAILABLE(macos(16.0))
@interface TahoeVolumeHUD : NSObject

/// Returns the shared singleton instance.
+ (instancetype)sharedManager;

/// Shows the HUD anchored visually beneath the given view.
/// @param volume The current volume level (0.0–100.0).
/// @param view   The view to anchor beneath, typically your status-bar item button.
- (void)showHUDWithVolume:(double)volume anchoredToView:(NSView *)view;

/// Hides the HUD immediately (called automatically after timeout).
- (void)hideHUD;

@end

NS_ASSUME_NONNULL_END
