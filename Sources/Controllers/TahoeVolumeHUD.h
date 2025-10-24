//
//  TahoeVolumeHUD.h
//  Volume Control
//
//  Created by Andrea Alberti on 24.10.25.
//


//
//  TahoeVolumeHUD.h
//  Volume Control
//
//  Created by AI Assistant on 24.10.25.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// A manager for displaying the modern, popover-based volume HUD
// available on macOS 16.0 (Tahoe) and later.
API_AVAILABLE(macos(16.0))
@interface TahoeVolumeHUD : NSObject

// Access the shared singleton instance.
+ (instancetype)sharedManager;

// Shows the HUD with the specified volume level.
// The HUD will automatically hide after a short delay.
// @param volume The volume level to display, from 0.0 to 100.0.
// @param view The view to anchor the popover to (typically the status bar button).
- (void)showHUDWithVolume:(double)volume anchoredToView:(NSView *)view;

@end

NS_ASSUME_NONNULL_END
