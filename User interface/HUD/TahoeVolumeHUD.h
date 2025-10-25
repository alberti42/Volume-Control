//
//  TahoeVolumeHUD.h
//
//  Created by Andrea Alberti on 25.10.25.
//


#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class TahoeVolumeHUD;

@protocol TahoeVolumeHUDDelegate <NSObject>
@optional
/// Called whenever the user changes the slider (0.0–1.0).
- (void)hud:(TahoeVolumeHUD *)hud didChangeVolume:(double)volume;
/// Called when the HUD hides (e.g., after timeout).
- (void)hudDidHide:(TahoeVolumeHUD *)hud;
@end

/// A singleton, popover-like Tahoe glass HUD anchored to a status bar button.
@interface TahoeVolumeHUD : NSObject

@property (class, readonly, strong) TahoeVolumeHUD *sharedManager;
@property (weak, nonatomic, nullable) id<TahoeVolumeHUDDelegate> delegate;

/// Show/update the HUD under a status bar button. `volume` is 0.0–1.0 (or 0–100; both accepted).
- (void)showHUDWithVolume:(double)volume usingIcon:(NSImage*)icon andLabel:(NSString*)label anchoredToStatusButton:(NSStatusBarButton *)button;

/// Programmatically hide it immediately.
- (void)hide;

/// Optional: update the slider programmatically without showing/hiding.
- (void)setVolume:(double)volume;

@end

NS_ASSUME_NONNULL_END
