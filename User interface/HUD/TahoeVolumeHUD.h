//
//  TahoeVolumeHUD.h
//
//  Created by Andrea Alberti on 25.10.25.
//


#import <Cocoa/Cocoa.h>

// Do not import AppDelegate.h here to avoid circular imports.
// Forward-declare the types we only need by pointer.
@class TahoeVolumeHUD;
@class PlayerApplication;

/// Where to place the HUD on screen when not anchored to a status-bar button.
/// The nine values form a 3×3 grid; the default is TopCenter (below the menu bar).
typedef NS_ENUM(NSInteger, HUDPosition) {
    HUDPositionTopLeft      = 0,
    HUDPositionTopCenter    = 1,
    HUDPositionTopRight     = 2,
    HUDPositionCenterLeft   = 3,
    HUDPositionCenter       = 4,
    HUDPositionCenterRight  = 5,
    HUDPositionBottomLeft   = 6,
    HUDPositionBottomCenter = 7,
    HUDPositionBottomRight  = 8,
};

NS_ASSUME_NONNULL_BEGIN

@protocol TahoeVolumeHUDDelegate <NSObject>
@optional
/// Called whenever the user changes the slider (0.0–1.0).
- (void)hud:(TahoeVolumeHUD *)hud didChangeVolume:(double)volume forPlayer:(PlayerApplication*)controlledPlayer;
/// Called whenever the user changes the slider (0.0–1.0) for the last time releasing focus
- (void)didChangeVolumeFinal:(TahoeVolumeHUD *)hud;

@end

/// A singleton, popover-like Tahoe glass HUD anchored to a status bar button.
@interface TahoeVolumeHUD : NSObject

@property (class, readonly, strong) TahoeVolumeHUD *sharedManager;
@property (weak, nonatomic, nullable) id<TahoeVolumeHUDDelegate> delegate;

/// Show/update the HUD under a status bar button. `volume` is 0.0–1.0 (or 0–100; both accepted).
/// When `button` is nil the HUD is placed on screen according to `position`.
- (void)showHUDWithVolume:(double)volume usingMusicPlayer:(nullable PlayerApplication*)controlledPlayer andLabel:(NSString*)label anchoredToStatusButton:(nullable NSStatusBarButton *)button position:(HUDPosition)position;

/// Programmatically hide it immediately.
- (void)hide;

/// Optional: update the slider programmatically without showing/hiding.
- (void)setVolume:(double)volume;

@end

NS_ASSUME_NONNULL_END
