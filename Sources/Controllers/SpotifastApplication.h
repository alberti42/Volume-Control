#import "AppDelegate.h"

// Spotifast implements the same player interface over its local socket.
// It does not expose the Apple Events used by the other music players.
@interface SpotifastApplication : PlayerApplication

@property (assign, nonatomic) BOOL enabled;
@property (copy, nonatomic, readonly) NSString *controlStatus;
@property (copy, nonatomic, readonly) NSString *playbackDeviceName;

- (void)setHUDVolume:(double)volume completion:(void (^)(BOOL success))completion;
- (void)flushHUDVolume;
- (void)cancelHUDVolume;

@end
