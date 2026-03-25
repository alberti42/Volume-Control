//
//  main_cli.m
//  volume-control-osd
//
//  CLI entry point. Parses --volume <0-100>, --title <string>, and --position,
//  shows the TahoeVolumeHUD on screen, then exits once the HUD has finished
//  its fade-out animation.
//
//  Usage:
//      volume-control-osd --volume 42 --title "Bluesound"
//      volume-control-osd --volume 75 --position top-right
//      volume-control-osd --help
//

#import <Cocoa/Cocoa.h>
#import "TahoeVolumeHUD.h"

// ---------------------------------------------------------------------------
// Minimal PlayerApplication stand-in that carries only what TahoeVolumeHUD
// actually uses: icon (nil → no icon shown) and the numeric volume fields.
// ---------------------------------------------------------------------------
@interface CLIPlayerApplication : NSObject
@property (nonatomic, strong, nullable) NSImage *icon;
@property (nonatomic, assign) double currentVolume;
@property (nonatomic, assign) double oldVolume;
@property (nonatomic, assign) double doubleVolume;
- (BOOL)isRunning;
- (NSInteger)playerState;
@end

@implementation CLIPlayerApplication
- (BOOL)isRunning   { return NO; }
- (NSInteger)playerState { return 0; }
@end

// ---------------------------------------------------------------------------
// Minimal app delegate – keeps NSApp alive just long enough for the HUD
// fade-in + hold + fade-out cycle, then quits cleanly.
// ---------------------------------------------------------------------------

// Total lifetime = fade-in (0.25 s) + hold (1.5 s) + fade-out (0.45 s) + margin
static const NSTimeInterval kTotalLifetime = 0.25 + 1.5 + 0.45 + 0.15;

@interface CLIAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, assign) double       volume;    // 0.0 – 1.0
@property (nonatomic, copy)   NSString    *title;
@property (nonatomic, assign) HUDPosition  position;
@end

@implementation CLIAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Activate the app so the window server sets up a compositing surface for
    // this process. Without this, NSGlassEffectView / NSVisualEffectView cannot
    // see through the window to the content behind it and renders opaque/solid.
    [NSApp activateIgnoringOtherApps:YES];

    // Show the HUD.  Passing nil for the status button → centers on screen.
    CLIPlayerApplication *player = [[CLIPlayerApplication alloc] init];
    player.currentVolume = self.volume;
    player.doubleVolume  = self.volume;

    [[TahoeVolumeHUD sharedManager] showHUDWithVolume:self.volume
                                     usingMusicPlayer:(PlayerApplication *)player
                                             andLabel:self.title
                               anchoredToStatusButton:nil
                                             position:self.position];

    // Schedule app termination after the full HUD lifecycle has elapsed.
    [NSTimer scheduledTimerWithTimeInterval:kTotalLifetime
                                     target:self
                                   selector:@selector(quit)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)quit {
    [NSApp terminate:nil];
}

// Prevent the app from dying immediately if it has no windows.
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

@end

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static void printUsage(const char *progname) {
    fprintf(stdout,
            "Usage: %s --volume <0-100> [--title <string>] [--position <pos>]\n"
            "\n"
            "Options:\n"
            "  --volume   <n>    Volume level from 0 to 100 (required)\n"
            "  --title    <s>    Label shown in the HUD (default: \"Volume\")\n"
            "  --position <pos>  Where to show the HUD (default: top-center)\n"
            "                    top-left | top-center | top-right\n"
            "                    center-left | center | center-right\n"
            "                    bottom-left | bottom-center | bottom-right\n"
            "  --help            Show this help message\n"
            "\n"
            "Example:\n"
            "  %s --volume 42 --title Bluesound --position top-right\n",
            progname, progname);
}

static BOOL parsePosition(const char *str, HUDPosition *outPosition) {
    NSString *s = [@(str) lowercaseString];
    NSDictionary<NSString *, NSNumber *> *map = @{
        @"top-left"      : @(HUDPositionTopLeft),
        @"top-center"    : @(HUDPositionTopCenter),
        @"top-right"     : @(HUDPositionTopRight),
        @"center-left"   : @(HUDPositionCenterLeft),
        @"center"        : @(HUDPositionCenter),
        @"center-right"  : @(HUDPositionCenterRight),
        @"bottom-left"   : @(HUDPositionBottomLeft),
        @"bottom-center" : @(HUDPositionBottomCenter),
        @"bottom-right"  : @(HUDPositionBottomRight),
    };
    NSNumber *val = map[s];
    if (!val) return NO;
    *outPosition = (HUDPosition)val.integerValue;
    return YES;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

int main(int argc, char *argv[]) {
    @autoreleasepool {

        // ---- Parse arguments ----
        double       volume    = -1.0;
        NSString    *title     = @"Volume";
        HUDPosition  position  = HUDPositionTopCenter;
        BOOL         gotVolume = NO;

        for (int i = 1; i < argc; i++) {
            NSString *arg = @(argv[i]);

            if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                printUsage(argv[0]);
                return 0;
            }

            if ([arg isEqualToString:@"--volume"] || [arg isEqualToString:@"-v"]) {
                if (i + 1 >= argc) {
                    fprintf(stderr, "error: --volume requires a numeric argument.\n");
                    printUsage(argv[0]);
                    return 1;
                }
                i++;
                char *end = NULL;
                double val = strtod(argv[i], &end);
                if (end == argv[i] || *end != '\0') {
                    fprintf(stderr, "error: --volume value '%s' is not a number.\n", argv[i]);
                    return 1;
                }
                if (val < 0.0 || val > 100.0) {
                    fprintf(stderr, "error: --volume must be between 0 and 100 (got %.4g).\n", val);
                    return 1;
                }
                volume    = val / 100.0;   // normalise to 0-1
                gotVolume = YES;
                continue;
            }

            if ([arg isEqualToString:@"--title"] || [arg isEqualToString:@"-t"]) {
                if (i + 1 >= argc) {
                    fprintf(stderr, "error: --title requires a string argument.\n");
                    printUsage(argv[0]);
                    return 1;
                }
                i++;
                title = @(argv[i]);
                continue;
            }

            if ([arg isEqualToString:@"--position"] || [arg isEqualToString:@"-p"]) {
                if (i + 1 >= argc) {
                    fprintf(stderr, "error: --position requires a position argument.\n");
                    printUsage(argv[0]);
                    return 1;
                }
                i++;
                if (!parsePosition(argv[i], &position)) {
                    fprintf(stderr, "error: unknown position '%s'.\n", argv[i]);
                    printUsage(argv[0]);
                    return 1;
                }
                continue;
            }

            fprintf(stderr, "error: unknown argument '%s'.\n", argv[i]);
            printUsage(argv[0]);
            return 1;
        }

        if (!gotVolume) {
            fprintf(stderr, "error: --volume is required.\n");
            printUsage(argv[0]);
            return 1;
        }

        // ---- Bootstrap NSApplication ----
        // We need a proper NSApplication run loop for AppKit UI (windows, animations).
        // NSApplicationActivationPolicyAccessory keeps us off the Dock/menu bar.
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        CLIAppDelegate *delegate = [[CLIAppDelegate alloc] init];
        delegate.volume    = volume;
        delegate.title     = title;
        delegate.position  = position;
        app.delegate       = delegate;

        [app run];
    }
    return 0;
}