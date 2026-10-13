#import "AppDelegate.h"

// Spotifast implements the same player interface over its documented CLI.
// It does not expose the Apple Events used by the other music players.
@interface SpotifastApplication : PlayerApplication

@property (assign, nonatomic) BOOL enabled;
@property (copy, nonatomic, readonly) NSString *controlStatus;
@property (copy, nonatomic, readonly) NSString *playbackDeviceName;

@end
