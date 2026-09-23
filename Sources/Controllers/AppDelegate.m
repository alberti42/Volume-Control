//
//
//  AppDelegate.m
//  iTunes Volume Control
//
//  Created by Andrea Alberti on 25.12.12.
//  Copyright (c) 2012 Andrea Alberti. All rights reserved.
//

#import "AppDelegate.h"
#import "SystemVolume.h"
#import "AccessibilityDialog.h"
#import "TahoeVolumeHUD.h"

#import <IOKit/hidsystem/ev_keymap.h>
#import <ServiceManagement/ServiceManagement.h>
#import <stdatomic.h>
#import <CoreServices/CoreServices.h>
#import <sys/sysctl.h>

#import "OSD.h"

//This will handle signals for us, specifically SIGTERM.
void handleSIGTERM(int sig) {
	[NSApp terminate:nil];
}

#define USE_APPLE_CMD_MODIFIER_MENU_ID 3
#define LOCK_SYSTEM_AND_PLAYER_VOLUME_ID 9
#define START_AT_LOGIN_ID 4
#define AUTOMATIC_UPDATES_ID 8
#define PLAY_SOUND_FEEDBACK_ID 7
#define TAPPING_ID 1
#define HIDE_FROM_STATUS_BAR_ID 5
#define HIDE_VOLUME_WINDOW_ID 6

#pragma mark - Tapping key stroke events

// Marks an event as one the tap should let pass through untouched rather than
// intercept and process. We stamp it onto the system-defined volume keys we
// re-post ourselves (see -repostSystemDefinedKey:keyDown:) when the active
// output device exposes no controllable volume and we want macOS to handle the
// key natively. The tag currently rides in the event's data2 field; real
// hardware volume-key events carry data2 == -1, so this distinct value cannot
// collide with them.
static const NSInteger kPassThroughEventTag = 0x0056434B; // 'VCK'

// Keycode of a volume/mute key we have currently handed off to macOS (or -1 if
// none). While a key is handed off, the tap lets that key's auto-repeat events
// and its release flow straight through so macOS ramps natively; without this we
// would consume every repeat and only single presses would work. Written by the
// main thread on key-down and cleared by either thread on key-up, so it is
// accessed atomically across the tap and main threads.
static _Atomic(int) gPassThroughKeyCode = -1;

CGEventRef event_tap_callback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    // Keep track of how many consecutive timeouts we’ve seen.
    // macOS fires kCGEventTapDisabledByTimeout when it thinks the tap is “hung”
    // (e.g. if the app is suspended by TCC while showing an Apple Events dialog).
    // We auto-resume a few times, then give up and alert the user if it persists.
    static int timeout_count = 0;
    
    if (type == kCGEventTapDisabledByTimeout) {
        if (timeout_count < 5) {
            // This handles “false positives” that occur when macOS temporarily
            // suspends the app for Apple Events permission prompts.
            timeout_count++;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                // Try to resume tapping automatically.
                AppDelegate *app = (__bridge AppDelegate *)refcon;
                if ([app Tapping]) { // guard if user disabled it manually
                    [app setTapping:YES]; // attempt to re-enable tap
                }
            });
        } else {
            // After 5 consecutive timeouts, assume it’s a real problem
            // (e.g. the tap logic is genuinely unresponsive).
            // Disable tapping and inform the user instead of looping forever.
            timeout_count = 0; // reset counter for next time
            dispatch_async(dispatch_get_main_queue(), ^{
                AppDelegate *app = (__bridge AppDelegate *)refcon;
                [app setTapping:NO];
                
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Tapping Disabled";
                alert.informativeText = @"Volume Control lost its ability to monitor volume keys because it became unresponsive. "
                                        @"Tapping has been turned off. You can re-enable it from the menu.";
                
                [alert addButtonWithTitle:@"OK"];
                [alert addButtonWithTitle:@"Report Issue on GitHub"];
                
                NSModalResponse response = [alert runModal];
                if (response == NSAlertSecondButtonReturn) {
                    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:
                                                            @"https://github.com/alberti42/Volume-Control/issues"]];
                }
            });
        }
        return event; // always return quickly so system input isn’t blocked
    }

    // Pass through events we don't care about
    if (type != NX_SYSDEFINED) return event;

    NSEvent *sysEvent = [NSEvent eventWithCGEvent:event];
    if ([sysEvent subtype] != NX_SUBTYPE_AUX_CONTROL_BUTTONS) return event;

    // Let our own re-posted volume keys flow straight through to macOS, so it can
    // perform its native handling. Without this guard we would re-catch and
    // re-process them, defeating the passthrough (and looping).
    if ([sysEvent data2] == kPassThroughEventTag) return event;

    // Extract key info
    int keyFlags   = ([sysEvent data1] & 0x0000FFFF);
    int keyCode    = (([sysEvent data1] & 0xFFFF0000) >> 16);
    int keyState   = (((keyFlags & 0xFF00) >> 8)) == 0xA;
    bool keyIsRepeat = (keyFlags & 0x1);
    CGEventFlags keyModifier = [sysEvent modifierFlags] | 0xFFFF;

    // If this key is currently handed off to macOS (because the output device
    // has no controllable volume), let its auto-repeat events and its release
    // flow straight through until the key is released, so macOS ramps natively.
    if (atomic_load(&gPassThroughKeyCode) == keyCode) {
        if (keyState == 0) { // key up ends the hand-off
            atomic_store(&gPassThroughKeyCode, -1);
        }
        return event;
    }

    // Decide here if it's a volume/mute event
    BOOL isMediaKey = (keyCode == NX_KEYTYPE_MUTE ||
                       keyCode == NX_KEYTYPE_SOUND_UP ||
                       keyCode == NX_KEYTYPE_SOUND_DOWN);

    if(isMediaKey /*&& keyModifier==1114111*/) {
        // Hand off all actual logic to main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            AppDelegate *app = (__bridge AppDelegate *)refcon;
            [app handleAsynchronouslyTappedEventWithKeyCode:keyCode
                                                   keyState:keyState
                                                keyIsRepeat:keyIsRepeat
                                                keyModifier:keyModifier];
        });
        
        return NULL;
    } else {
        // Always return immediately to keep the system input flowing
        return event;
    }
}


#pragma mark - Class extension for status menu

@interface AppDelegate () <NSMenuDelegate>
{
	//StatusItemView* _statusBarItemView;
	NSTimer* _statusBarHideTimer;
	NSPopover* _hideFromStatusBarHintPopover;
	NSTextField* _hideFromStatusBarHintLabel;
	NSTimer *_hideFromStatusBarHintPopoverUpdateTimer;

	NSView* _hintView;
	NSViewController* _hintVC;
    
    NSTimer* accessibilityCheckTimer;
    NSTimer* volumeRampTimer;
    NSTimer* timerImgSpeaker;
    NSTimer* checkPlayerTimer;
    NSTimer* updateSystemVolumeTimer;
    NSTimeInterval waitOverlayPanel;
    bool fadeInAnimationReady;
    
    // Event tap state
    int _previousKeyCode;
    BOOL _muteDown;
}

// Forward declare private methods
- (id)runningPlayer;
- (void)completeInitialization;
- (void)setVolumeUp:(bool)increase;
- (void)repostSystemDefinedKey:(int)keyCode keyDown:(BOOL)keyDown;
- (void) setItunesVolume:(NSInteger)volume;
- (void) setSpotifyVolume:(NSInteger)volume;
- (void) setDopplerVolume:(NSInteger)volume;
- (void) setSwinsianVolume:(NSInteger)volume;
- (void) setSystemVolume:(NSInteger)volume;
- (void)stopVolumeRampTimer;
- (void)updatePercentages;
- (bool)createEventTap;
- (void)handleEventTapDisabledByUser;

@end

#pragma mark - Extention music applications

@interface PlayerApplication () {
    dispatch_queue_t _writeQueue;  // serial queue for ScriptingBridge writes
    BOOL             _writeInFlight; // YES while a write is executing on _writeQueue
    double           _pendingWrite;  // latest desired volume while write is in flight; -1 = none
    BOOL             _rampActive;    // YES while a key-hold ramp is in progress
}
- (void)scheduleVolumeWrite:(double)volume;
- (void)scheduleVolumeVerification;
@property (nonatomic, assign) BOOL rampActive;
@end

@implementation PlayerApplication

@synthesize currentVolume = _currentVolume;
@synthesize icon = _icon;
@synthesize rampActive = _rampActive;

- (void) setCurrentVolume:(double)currentVolume
{
  /* We use setValue:forKey: (KVC) rather than calling setSoundVolume:
      directly because the generated headers declare soundVolume as
      NSInteger for Music/ Spotify/Doppler but as NSNumber * for
      Swinsian (whose sdef uses type="number").  The compiler would
      see conflicting method signatures and pick arbitrarily.  KVC
      bypasses that ambiguity by boxing the value as NSNumber
      regardless. */

    [self setDoubleVolume:currentVolume];

    // Negative sentinel values (e.g. -100 used during init) must not be
    // forwarded to the player — they are internal "unset" markers only.
    if (currentVolume >= 0) {
        [self scheduleVolumeWrite:currentVolume];
    }
}

// Sends `volume` to the ScriptingBridge player on a background serial queue.
// If a write is already in flight the new value is remembered and dispatched
// as soon as the in-flight write completes, so intermediate values are skipped
// rather than queued — keeping the player in sync with the latest position.
- (void) scheduleVolumeWrite:(double)volume
{
    if (_writeInFlight) {
        // A write is already on its way; just record the latest target.
        _pendingWrite = volume;
        return;
    }

    _writeInFlight = YES;
    _pendingWrite  = -1.0;

    dispatch_async(_writeQueue, ^{
        [self->musicPlayer setValue:@((NSInteger)round(volume)) forKey:@"soundVolume"];

        dispatch_async(dispatch_get_main_queue(), ^{
            self->_writeInFlight = NO;
            if (self->_pendingWrite >= 0) {
                double v = self->_pendingWrite;
                self->_pendingWrite = -1.0;
                [self scheduleVolumeWrite:v];
            } else {
#ifdef DEBUG
                // All writes have been flushed to the player.
                // Skip the verification read while a ramp is active: Apple Music on
                // Tahoe acknowledges Apple Events before applying them, so an
                // immediate SB read after write completion returns a stale value and
                // produces spurious ⚠️ warnings.  The ramp-end path calls
                // scheduleVolumeVerification with a delay instead.
                if (!self->_rampActive) {
                    double sbVol     = [[self->musicPlayer valueForKey:@"soundVolume"] doubleValue];
                    double cachedVol = [self doubleVolume];
                    NSLog(@"[VC] flush internal=%.2f  player SB=%.2f  delta=%.2f%@",
                          cachedVol, sbVol, sbVol - cachedVol,
                          (fabs(sbVol - cachedVol) > 1.0) ? @"  ⚠️ MISMATCH" : @"");
                }
#endif
            }
        });
    });
}

// Called by AppDelegate when the key-hold ramp ends.  Waits 500 ms to give
// Apple Music time to apply the last write, then reads the actual volume and
// compares it with the internal cache.  The delay is intentional: on Tahoe,
// Apple Music acknowledges Apple Events before applying them, so an immediate
// read after write completion returns a stale value.
- (void)scheduleVolumeVerification
{
#ifdef DEBUG
    double expected = [self doubleVolume];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // Skip if another ramp or write cycle started in the meantime.
        if (self->_writeInFlight || self->_pendingWrite >= 0) return;
        double sbVol = [[self->musicPlayer valueForKey:@"soundVolume"] doubleValue];
        NSLog(@"[VC] verify  internal=%.2f  player SB=%.2f  delta=%.2f%@",
              expected, sbVol, sbVol - expected,
              (fabs(sbVol - expected) > 1.0) ? @"  ⚠️ MISMATCH" : @"");
    });
#endif
}

- (double) currentVolume
{
  /* We use valueForKey: rather than calling soundVolume directly
  because ScriptingBridge returns a scalar for integer-typed
  properties but an NSNumber * for Swinsian's number-typed
  soundVolume.  Reading a pointer as a scalar produces garbage
  (e.g. the memory address).  valueForKey: always returns id, so
  doubleValue gives the correct numeric value uniformly. */

  double vol = [[musicPlayer valueForKey:@"soundVolume"] doubleValue];

  if (fabs(vol-[self doubleVolume])<1) {
    vol = [self doubleVolume];
  }

	return vol;
}

- (void) nextTrack
{
	return [musicPlayer nextTrack];
}

- (void) previousTrack
{
	return [musicPlayer previousTrack];
}

- (void) playPause
{
	return [musicPlayer playPause];
}

- (BOOL) isRunning
{
	return [musicPlayer isRunning];
}

- (NSInteger) playerState
{
    /* enum behaves like an integer and the default C enum size (4
       bytes) doesn't match NSInteger's size on 64-bit (8 bytes). The
       valueForKey: sidesteps this entirely by never calling
       playerState as a typed method at the call site.  valueForKey
       retrieves an id and then we can query the integer value
       safely. */
    return [[musicPlayer valueForKey:@"playerState"] integerValue];
}

-(id)initWithBundleIdentifier:(NSString*) bundleIdentifier andIcon:(NSImage*)icon {
	if (self = [super init])  {
        _bundleIdentifier = [bundleIdentifier copy];
        _playerStateScript = nil;
        _writeQueue    = dispatch_queue_create("io.alberti42.VolumeControl.sbWrite", DISPATCH_QUEUE_SERIAL);
        _writeInFlight = NO;
        _pendingWrite  = -1.0;
		[self setCurrentVolume: -100];
		[self setOldVolume: -1];
		musicPlayer = [SBApplication applicationWithBundleIdentifier:bundleIdentifier];
        // Most Apple Events to the player are sent synchronously on the main
        // thread. With the default timeout (about 2 minutes), a player that
        // stops answering freezes the whole app, including the status item.
        // The timeout is in ticks (1/60 s): 120 ticks = 2 s.
        [(SBApplication *)musicPlayer setTimeout:120];
        [self setIcon:icon];
	}
	return self;
}

@end

#pragma mark - Implementation AppDelegate

@implementation AppDelegate

// @synthesize AppleRemoteConnected=_AppleRemoteConnected;
@synthesize StartAtLogin=_StartAtLogin;
@synthesize Tapping=_Tapping;
@synthesize UseAppleCMDModifier=_UseAppleCMDModifier;
@synthesize LockSystemAndPlayerVolume=_LockSystemAndPlayerVolume;
@synthesize AppleCMDModifierPressed=_AppleCMDModifierPressed;
@synthesize AutomaticUpdates=_AutomaticUpdates;
@synthesize hideFromStatusBar = _hideFromStatusBar;
@synthesize hideVolumeWindow = _hideVolumeWindow;
@synthesize loadIntroAtStart = _loadIntroAtStart;
@synthesize statusBar = _statusBar;

@synthesize iTunesBtn = _iTunesBtn;
@synthesize spotifyBtn = _spotifyBtn;
@synthesize systemBtn = _systemBtn;
@synthesize dopplerBtn = _dopplerBtn;
@synthesize swinsianBtn = _swinsianBtn;

@synthesize iTunesPerc = _iTunesPerc;
@synthesize spotifyPerc = _spotifyPerc;
@synthesize systemPerc = _systemPerc;
@synthesize dopplerPerc = _dopplerPerc;
@synthesize swinsianPerc = _swinsianPerc;

@synthesize sparkle_updater = _sparkle_updater;

@synthesize statusMenu = _statusMenu;

static NSTimeInterval volumeRampTimeInterval=0.01f;
static NSTimeInterval statusBarHideDelay=10.0f;
static NSTimeInterval checkPlayerTimeout=0.3f;
//static NSTimeInterval volumeLockSyncInterval=1.0f;
static NSTimeInterval updateSystemVolumeInterval=0.1f;

- (NSString *)helperBundleID {
    return [[[NSBundle mainBundle] bundleIdentifier] stringByAppendingString:@"Helper"];
}

- (IBAction)terminate:(id)sender
{
    if (eventTap && CFMachPortIsValid(eventTap)) {
        if (CFMachPortIsValid(eventTap)) {
            CFMachPortInvalidate(eventTap);
        }
        if (runLoopSource) {
            CFRunLoopSourceInvalidate(runLoopSource);
            CFRelease(runLoopSource);
            runLoopSource = nil;
        }
        CFRelease(eventTap);
        eventTap = nil;
    }
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    
    systemAudio = nil;
    iTunes = nil;
    spotify = nil;
    doppler = nil;
    swinsian = nil;
    
    _statusBar = nil;
    
    accessibilityDialog = nil;
    introWindowController = nil;
    
    [volumeRampTimer invalidate];
    volumeRampTimer = nil;
    
    [checkPlayerTimer invalidate];
    checkPlayerTimer = nil;
    
    [timerImgSpeaker invalidate];
    timerImgSpeaker = nil;
    
    [updateSystemVolumeTimer invalidate];
    updateSystemVolumeTimer = nil;
    
    preferences = nil;
    
    // IMPORTANT: Use [NSApp terminate:nil] for a clean exit.
    // This ensures AppKit tears down the NSStatusItem properly
    // and preserves the status bar icon position between launches.
    // Simply returning or calling exit() would skip this cleanup
    // and cause the icon to reset to the default position.
    [NSApp terminate:nil];
}

- (void)updateStartAtLoginMenuItem
{
    BOOL enabled = [self StartAtLogin];
    NSMenuItem* menuItem = [self.statusMenu itemWithTag:START_AT_LOGIN_ID];
    [menuItem setState:enabled ? NSControlStateValueOn : NSControlStateValueOff];
}

- (IBAction)toggleStartAtLogin:(id)sender {
    BOOL currentlyEnabled = [self StartAtLogin];
    
    if (currentlyEnabled) {
        // User clicked to disable
        [self setStartAtLogin:NO savePreferences:YES];
    } else {
        // User clicked to enable
        [self setStartAtLogin:YES savePreferences:YES];
        
        if (@available(macOS 13.0, *)) {
            SMAppService *service = [SMAppService loginItemServiceWithIdentifier:[self helperBundleID]];
            if (service.status == SMAppServiceStatusRequiresApproval) {
                // TODO: prompt user to open System Settings
                NSLog(@"Login item requires approval in System Settings → Login Items");
            }
        }
    }
    [self updateStartAtLoginMenuItem];
}

- (void)setStartAtLogin:(BOOL)enabled savePreferences:(BOOL)savePreferences
{
    NSString *helperBundleID = [self helperBundleID];
    
    if (@available(macOS 13.0, *)) {
        SMAppService *service = [SMAppService loginItemServiceWithIdentifier:helperBundleID];
        NSError *error = nil;
        
        if (enabled) {
            if (service.status != SMAppServiceStatusEnabled) {
                if (![service registerAndReturnError:&error]) {
                    NSLog(@"[Volume Control] Error registering login item: %@", error.localizedDescription);
                }
            }
        } else {
            if (service.status != SMAppServiceStatusNotRegistered) {
                if (![service unregisterAndReturnError:&error]) {
                    NSLog(@"[Volume Control] Error unregistering login item: %@", error.localizedDescription);
                }
            }
        }
    } else {
        // Legacy fallback (macOS 12 and older)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (!SMLoginItemSetEnabled((__bridge CFStringRef)helperBundleID, enabled)) {
            NSLog(@"[Volume Control] SMLoginItemSetEnabled failed.");
        }
#pragma clang diagnostic pop
    }
    
    if (savePreferences) {
        [preferences setBool:enabled forKey:@"StartAtLoginPreference"];
    }
    
    [self updateStartAtLoginMenuItem];
}

- (bool)StartAtLogin
{
    // Enabled → the login item is registered and will launch at login.
    // NotRegistered → no login item exists.
    // RequiresApproval → your app tried to register the login item, but the user hasn’t granted approval yet in System Settings
    //
    // sfltool dumpbtm → dump the entire macOS database of login authorizations for inspection from the command line.
    // sfltool resetbtm → reset the entire macOS database of login authorizations. Be careful: the reset applies to all apps, not only this one
    
    NSString *helperBundleID = [self helperBundleID];
    
    if (@available(macOS 13.0, *)) {
        SMAppService *service = [SMAppService loginItemServiceWithIdentifier:helperBundleID];
        
        // In case of RequiresApproval, it means the user requested to start the app at login, but the request has not been approved yet.
        // In this case, "Start at login" should be assumed to be checked because it would confuse the user to have click on the toggle
        // and see no changes.
        return (service.status == SMAppServiceStatusEnabled ||
                service.status == SMAppServiceStatusRequiresApproval);
    } else {
        return [preferences boolForKey:@"StartAtLoginPreference"];
    }
}

- (void)wasAuthorized
{
    [accessibilityDialog close];
    accessibilityDialog = nil;
    
    [self completeInitialization];
}

- (void)stopVolumeRampTimer
{
    [volumeRampTimer invalidate];
    volumeRampTimer=nil;
    [self emitAcousticFeedback];

    checkPlayerTimer = [NSTimer timerWithTimeInterval:checkPlayerTimeout target:self selector:@selector(resetCurrentPlayer:) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:checkPlayerTimer forMode:NSRunLoopCommonModes];

#ifdef DEBUG
    if ([currentPlayer isKindOfClass:[PlayerApplication class]]) {
        PlayerApplication *p = (PlayerApplication *)currentPlayer;
        p.rampActive = NO;
        [p scheduleVolumeVerification];
    }
#endif
}

- (void)rampVolumeUp:(NSTimer*)theTimer
{
    [self setVolumeUp:true];
}

- (void)rampVolumeDown:(NSTimer*)theTimer
{
    [self setVolumeUp:false];
}

- (void)checkAccessibilityTrust:(NSTimer *)timer {
    if (eventTap && ![self isTappingTrusted]) {
        // NSLog(@"Accessibility permission revoked during runtime. Cleaning up tap.");
        [self handleEventTapDisabledByUser];
    }
}

- (BOOL)isTappingTrusted {
    // Key must be a CFStringRef (no need to retain/release since it's a constant)
    const void *keys[]   = { kAXTrustedCheckOptionPrompt };
    // Value must be a CFBooleanRef
    const void *values[] = { kCFBooleanFalse };
    
    CFDictionaryRef options = CFDictionaryCreate(
                                                 kCFAllocatorDefault,   // allocator
                                                 keys,                  // keys
                                                 values,                // values
                                                 1,                     // number of keys/values
                                                 &kCFTypeDictionaryKeyCallBacks,    // standard key callbacks
                                                 &kCFTypeDictionaryValueCallBacks   // standard value callbacks
                                                 );
    
    BOOL trusted = AXIsProcessTrustedWithOptions(options);
    CFRelease(options);
    
    return trusted;
}

- (BOOL)tryCreateEventTap {
    BOOL trusted = [self isTappingTrusted];
    
    if (trusted) {
        if ([self createEventTap]) {
            return YES;
        }
    }
    return NO;
}

- (bool)createEventTap
{
    if (eventTap != nil && CFMachPortIsValid(eventTap)) {
        CFMachPortInvalidate(eventTap);
        CFRunLoopSourceInvalidate(runLoopSource);
        CFRelease(eventTap);
        CFRelease(runLoopSource);
        eventTap = nil;
        runLoopSource = nil;
    }
    
    CGEventMask eventMask = CGEventMaskBit(NX_SYSDEFINED);
    eventTap = CGEventTapCreate(kCGSessionEventTap,
                                kCGHeadInsertEventTap,
                                kCGEventTapOptionDefault,
                                eventMask,
                                event_tap_callback,
                                (__bridge void *)self);
    
    if (eventTap != nil) {
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        
        // Start safety timer to monitor trust state
        accessibilityCheckTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                                   target:self
                                                                 selector:@selector(checkAccessibilityTrust:)
                                                                 userInfo:nil
                                                                  repeats:YES];
        
        return true;
    } else {
        return false;
    }
}

- (void)handleEventTapDisabledByUser {
    if (eventTap && CFMachPortIsValid(eventTap)) {
        if (CFMachPortIsValid(eventTap)) {
            CFMachPortInvalidate(eventTap);
        }
        if (runLoopSource) {
            CFRunLoopSourceInvalidate(runLoopSource);
            CFRelease(runLoopSource);
            runLoopSource = nil;
        }
        CFRelease(eventTap);
        eventTap = nil;
    }
    
    if (accessibilityCheckTimer) {
        [accessibilityCheckTimer invalidate];
        accessibilityCheckTimer = nil;
    }
    
    // Update toggle state to reflect reality
    [self setTapping:NO];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Accessibility Permission Revoked";
        alert.informativeText = @"Volume Control has lost permission to monitor keyboard events. "
        @"Keyboard input may stop working until you restore permission in "
        @"System Settings → Privacy & Security → Accessibility.";
        [alert runModal];
    });
}

- (void)handleAsynchronouslyTappedEventWithKeyCode:(int)keyCode
                                          keyState:(BOOL)keyState
                                       keyIsRepeat:(BOOL)keyIsRepeat
                                       keyModifier:(CGEventFlags)keyModifier
{
    [self setAppleCMDModifierPressed:(keyModifier & NX_COMMANDMASK) == NX_COMMANDMASK];

    // If the resolved target is the system output and that device exposes no
    // controllable volume (e.g. many HDMI/DisplayPort displays), don't handle
    // the key ourselves and don't show the HUD. Re-post it so macOS performs
    // its own native handling instead.
    if (keyCode == NX_KEYTYPE_MUTE ||
        keyCode == NX_KEYTYPE_SOUND_UP ||
        keyCode == NX_KEYTYPE_SOUND_DOWN)
    {
        if ([self runningPlayer] == systemAudio && ![systemAudio hasControllableVolume])
        {
            if (keyState == 1)
            {
                // Hand this key off to macOS: re-post the initial press (so a
                // single tap still registers), then flag it so the tap lets the
                // auto-repeat events and the release pass straight through until
                // the key is released, letting macOS ramp natively.
                atomic_store(&gPassThroughKeyCode, keyCode);
                [self repostSystemDefinedKey:keyCode keyDown:YES];
            }
            else
            {
                // Released before the tap saw the flag (fast tap) — clear it and
                // re-post the release so macOS sees a balanced key event.
                atomic_store(&gPassThroughKeyCode, -1);
                [self repostSystemDefinedKey:keyCode keyDown:NO];
            }
            return;
        }
    }

    switch (keyCode) {
        case NX_KEYTYPE_MUTE:
            if (_previousKeyCode != keyCode && self->volumeRampTimer) {
                [self stopVolumeRampTimer];
            }
            _previousKeyCode = keyCode;
            
            if (keyState == 1) {
                _muteDown = true;
                [self MuteVol];
            } else {
                _muteDown = false;
            }
            break;
            
        case NX_KEYTYPE_SOUND_UP:
        case NX_KEYTYPE_SOUND_DOWN:
            if (!_muteDown) {
                if (_previousKeyCode != keyCode && self->volumeRampTimer) {
                    [self stopVolumeRampTimer];
                }
                _previousKeyCode = keyCode;
                
                if (keyState == 1) {
                    if (!self->volumeRampTimer) {
                        BOOL increase = (keyCode == NX_KEYTYPE_SOUND_UP);
                        [self adjustVolumeUp:increase ramp:keyIsRepeat];
                    }
                } else {
                    if (self->volumeRampTimer) {
                        [self stopVolumeRampTimer];
                    }
                }
            }
            break;
    }
}

// Re-post a single system-defined volume/mute key so macOS handles it natively.
// The event is tagged (data2 == kPassThroughEventTag) so our own tap ignores
// it instead of re-catching it. Down and up are posted separately, mirroring the
// original events we consumed.
- (void)repostSystemDefinedKey:(int)keyCode keyDown:(BOOL)keyDown
{
    int stateNibble = keyDown ? 0xa : 0xb; // 0xa = key down, 0xb = key up

    NSEvent *ev = [NSEvent otherEventWithType:NSEventTypeSystemDefined
                                     location:NSZeroPoint
                                modifierFlags:(keyDown ? 0xa00 : 0xb00)
                                    timestamp:0
                                 windowNumber:0
                                      context:nil
                                      subtype:NX_SUBTYPE_AUX_CONTROL_BUTTONS
                                        data1:((keyCode << 16) | (stateNibble << 8))
                                        data2:kPassThroughEventTag];

    CGEventPost(kCGHIDEventTap, ev.CGEvent);
}

-(void) sendMediaKey: (int)key {
    // create and send down key event
    NSEvent* key_event;
    
    key_event = [NSEvent otherEventWithType:NSEventTypeSystemDefined location:CGPointZero modifierFlags:0xa00 timestamp:0 windowNumber:0 context:0 subtype:8 data1:((key << 16) | (0xa << 8)) data2:-1];
    CGEventPost(0, key_event.CGEvent);
    // NSLog(@"%d keycode (down) sent",key);
    
    // create and send up key event
    key_event = [NSEvent otherEventWithType:NSEventTypeSystemDefined location:CGPointZero modifierFlags:0xb00 timestamp:0 windowNumber:0 context:0 subtype:8 data1:((key << 16) | (0xb << 8)) data2:-1];
    CGEventPost(0, key_event.CGEvent);
    // NSLog(@"%d keycode (up) sent",key);
}

/*
- (void)PlayPauseMusic
{
    [self sendMediaKey:NX_KEYTYPE_PLAY];
}

- (void)NextTrackMusic
{
    [self sendMediaKey:NX_KEYTYPE_NEXT];
}

- (void)PreviousTrackMusic
{
    [self sendMediaKey:NX_KEYTYPE_PREVIOUS];
}
 */

- (void)MuteVol
{
	id runningPlayerPtr = [self runningPlayer];

	if (runningPlayerPtr != nil)
	{
		if([runningPlayerPtr oldVolume]<0)
		{
			[runningPlayerPtr setOldVolume:[runningPlayerPtr currentVolume]];
			[runningPlayerPtr setCurrentVolume:0];

			if (_LockSystemAndPlayerVolume && runningPlayerPtr != systemAudio) {
				[systemAudio setOldVolume:[systemAudio currentVolume]];
				[systemAudio setCurrentVolume:0];
			}

            if(!_hideVolumeWindow){
                if (@available(macOS 16.0, *)) {
                    // On Tahoe, show the new popover HUD.
                    [[TahoeVolumeHUD sharedManager] showHUDWithVolume:0 usingMusicPlayer:runningPlayerPtr andLabel:[systemAudio getDefaultOutputDeviceName]  anchoredToStatusButton:([self hideFromStatusBar] ? nil : self.statusBar.button)];
                } else {
                    // On older systems, use the classic OSD.
                    id osdMgr = [self->OSDManager sharedManager];
                    if (osdMgr) {
                        [osdMgr showImage:OSDGraphicSpeakerMute onDisplayID:CGSMainDisplayID() priority:OSDPriorityDefault msecUntilFade:1000 filledChiclets:0 totalChiclets:(unsigned int)100 locked:NO];
                    }
                }
            }
		}
		else
		{
			[runningPlayerPtr setCurrentVolume:[runningPlayerPtr oldVolume]];

			if (_LockSystemAndPlayerVolume && runningPlayerPtr != systemAudio) {
				[systemAudio setCurrentVolume:[systemAudio oldVolume]];
			}
            
            if(!_hideVolumeWindow)
            {
                if (@available(macOS 16.0, *)) {
                    // On Tahoe, show the new popover HUD.
                    [[TahoeVolumeHUD sharedManager] showHUDWithVolume:[runningPlayerPtr oldVolume] usingMusicPlayer:runningPlayerPtr andLabel:[systemAudio getDefaultOutputDeviceName] anchoredToStatusButton:([self hideFromStatusBar] ? nil : self.statusBar.button)];
                } else {
                    // On older systems, use the classic OSD.
                    id osdMgr = [self->OSDManager sharedManager];
                    if (osdMgr) {
                        [osdMgr showImage:OSDGraphicSpeaker onDisplayID:CGSMainDisplayID() priority:OSDPriorityDefault msecUntilFade:1000 filledChiclets:(unsigned int)[runningPlayerPtr oldVolume] totalChiclets:(unsigned int)100 locked:NO];
                    }
                }
            }
            
			[runningPlayerPtr setOldVolume:-1];
		}

		if (runningPlayerPtr == iTunes)
			[self setItunesVolume:[runningPlayerPtr currentVolume]];
		else if (runningPlayerPtr == spotify)
			[self setSpotifyVolume:[runningPlayerPtr currentVolume]];
		else if (runningPlayerPtr == doppler)
			[self setDopplerVolume:[runningPlayerPtr currentVolume]];
		else if (runningPlayerPtr == swinsian)
			[self setSwinsianVolume:[runningPlayerPtr currentVolume]];

		// Update system UI if system volume is affected or when locked
		if (_LockSystemAndPlayerVolume || runningPlayerPtr == systemAudio) {
			[self setSystemVolume:[systemAudio currentVolume]];
		}

	}
}

- (void)adjustVolumeUp:(BOOL)increase ramp:(BOOL)ramp {
    if (ramp) {
        [checkPlayerTimer invalidate];
        checkPlayerTimer = nil;

        SEL selector = increase ? @selector(rampVolumeUp:) : @selector(rampVolumeDown:);
        volumeRampTimer = [NSTimer timerWithTimeInterval:volumeRampTimeInterval * (NSTimeInterval)increment
                                                  target:self
                                                selector:selector
                                                userInfo:nil
                                                 repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:volumeRampTimer forMode:NSRunLoopCommonModes];

        if (timerImgSpeaker) {
            [timerImgSpeaker invalidate];
            timerImgSpeaker = nil;
        }

#ifdef DEBUG
        if ([currentPlayer isKindOfClass:[PlayerApplication class]]) {
            ((PlayerApplication *)currentPlayer).rampActive = YES;
        }
#endif
    } else {
        [self setVolumeUp:increase];
    }
}

- (id)init
{
	self = [super init];
	if(self)
	{
		self->eventTap = nil;
		menuIsVisible=false;
		currentPlayer=nil;

		updateSystemVolumeTimer=nil;
		volumeRampTimer=nil;
		timerImgSpeaker=nil;
		checkPlayerTimer=nil;
        
        // Explicitly initialize event tap state
        _previousKeyCode = 0;
        _muteDown = NO;
	}
	return self;
}

-(void)completeInitialization
{
	SPUUpdater* updater = [[self sparkle_updater] updater];
	[updater clearFeedURLFromUserDefaults];
	[[self sparkle_updater] userDriver];
	[updater setUpdateCheckInterval:60*60*24*7]; // look for new updates every 7 days

	//[[SUUpdater sharedUpdater] setFeedURL:[NSURL URLWithString:[NSString stringWithFormat: @"http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/VolumeControlCast.xml.php?version=%@&osxversion=%@",version,[operatingSystemVersionString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]]]];
	//[[SUUpdater sharedUpdater] setUpdateCheckInterval:60*60*24*7]; // look for new updates every 7 days

	// [self _loadBezelServices]; // El Capitan and probably older systems
    if (@available(macOS 16.0, *)) {
        // Running on Tahoe (2026) or newer
    } else {
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/OSD.framework"] load];
        self->OSDManager = NSClassFromString(@"OSDManager");
    }

    if (@available(macOS 16.0, *)) {
        iTunes = [[PlayerApplication alloc] initWithBundleIdentifier:@"com.apple.Music" andIcon:[NSImage imageNamed:@"AppleMusicTahoe"]];
    } else {
        iTunes = [[PlayerApplication alloc] initWithBundleIdentifier:@"com.apple.Music" andIcon:[NSImage imageNamed:@"AppleMusicSequoia"]];
    }
	
    spotify = [[PlayerApplication alloc] initWithBundleIdentifier:@"com.spotify.client" andIcon:[NSImage imageNamed:@"spotify"]];

    doppler = [[PlayerApplication alloc] initWithBundleIdentifier:@"co.brushedtype.doppler-macos" andIcon:[NSImage imageNamed:@"doppler"]];

    swinsian = [[PlayerApplication alloc] initWithBundleIdentifier:@"com.swinsian.Swinsian" andIcon:[NSImage imageNamed:@"swinsian"]];

	// Force MacOS to ask for authorization to AppleEvents if this was not already given
	if([iTunes isRunning])
		[iTunes currentVolume];
	if([spotify isRunning])
		[spotify currentVolume];
	if([doppler isRunning])
		[doppler currentVolume];
	if([swinsian isRunning])
		[swinsian currentVolume];

	systemAudio = [[SystemApplication alloc] init];

	// Install icon into the menu bar
	[self showInStatusBarWithCompletion:^{
		// This code will only run AFTER the icon has been created and is visible.

		// Initiate hiding it
		if([self hideFromStatusBar]) {
			// NSLog(@"Started hiding from status bar");
			[self setHideFromStatusBar:YES];
		}
	}];

	// NSString* iTunesVersion = [[NSString alloc] initWithString:[iTunes version]];
	// NSString* spotifyVersion = [[NSString alloc] initWithString:[spotify version]];

	[self initializePreferences];

	[self setStartAtLogin:[self StartAtLogin] savePreferences:false];

	volumeSound = [[NSSound alloc] initWithContentsOfFile:@"/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff" byReference:false];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	//    if (menuItem.tag == USE_APPLE_CMD_MODIFIER_MENU_ID) { // CMD Modifier menu item
	//        return ![self LockSystemAndPlayerVolume]; // Disable when locked
	//    }
	return YES; // Default behavior
}

- (void)emitAcousticFeedback
{
	if([self PlaySoundFeedback] && (_AppleCMDModifierPressed != _UseAppleCMDModifier || [[self runningPlayer] isKindOfClass:[SystemApplication class]]))
	{
		if([volumeSound isPlaying])
			[volumeSound stop];
		[volumeSound play];
	}
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self selector: @selector(receiveWakeNote:) name:NSWorkspaceDidWakeNotification object: NULL];

	signal(SIGTERM, handleSIGTERM);

	if ([self tryCreateEventTap]) {
		[self completeInitialization];
	} else {
		// Not yet trusted, show helper dialog
		accessibilityDialog = [[AccessibilityDialog alloc] initWithWindowNibName:@"AccessibilityDialog"];
		[accessibilityDialog showWindow:self];
	}
    
    [TahoeVolumeHUD sharedManager].delegate = self;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    if ([self hideFromStatusBar]) {
		// First, tell the status bar to show itself.
		[self showInStatusBarWithCompletion:^{
			// This code will only run AFTER the icon has been created and is visible.

			// Initiate hiding it
			[self setHideFromStatusBar:YES];

            // Actively show the popover to make sure user notices; delay it until status item has settled in its final position
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self showHideFromStatusBarHintPopover];
            });
		}];
	}
	return false;
}

- (void)showInStatusBarWithCompletion:(void (^)(void))completion
{
	if (!self.statusBar) {
		// the status bar item needs a custom view so that we can show a NSPopover for the hide-from-status-bar hint
		// the view now reacts to the mouseDown event to show the menu
		self.statusBar = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
		self.statusBar.menu = self.statusMenu;
	}

	// Defer the button configuration to the next run loop cycle.
	// This allows the system to create and place the status item
	// before you try to modify its view hierarchy.
	dispatch_async(dispatch_get_main_queue(), ^{
		// Show the status bar item first.
		[self showStatusBarItem];

		NSImage *icon = [NSImage imageNamed:@"statusbar-icon"];
		icon.template = YES;

		if (self.statusBar.button) {
			self.statusBar.button.image = icon;
		}

		// Now that the UI work is complete, call the completion handler.
		if (completion) {
			completion();
		}
	});
}


- (void)updateSystemVolume:(NSTimer*)theTimer
{
	BOOL controllable = [systemAudio hasControllableVolume];

	// Keep the System check mark in sync with availability (see setSystemVolume:).
	[[self systemBtn] setState:controllable ? NSControlStateValueOn : NSControlStateValueOff];

	if(!controllable)
		[[self systemPerc] setStringValue:@"(n/a)"];
	else if([systemAudio isMuted])
		[[self systemPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",0]];
	else
		[[self systemPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",(int)[systemAudio currentVolume]]];
}

- (void)initializePreferences
{
	preferences = [NSUserDefaults standardUserDefaults];
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
						  [NSNumber numberWithInt:2],      @"volumeIncrement",
						  [NSNumber numberWithBool:true] , @"TappingEnabled",
						  [NSNumber numberWithBool:false], @"UseAppleCMDModifier",
						  [NSNumber numberWithBool:false], @"LockSystemAndPlayerVolume",
						  [NSNumber numberWithBool:true],  @"AutomaticUpdates",
						  [NSNumber numberWithBool:false], @"hideFromStatusBarPreference",
						  [NSNumber numberWithBool:false], @"hideVolumeWindowPreference",
						  [NSNumber numberWithBool:true],  @"iTunesControl",
						  [NSNumber numberWithBool:true],  @"spotifyControl",
						  [NSNumber numberWithBool:true],  @"dopplerControl",
						  [NSNumber numberWithBool:true],  @"swinsianControl",
						  [NSNumber numberWithBool:true],  @"systemControl",
						  [NSNumber numberWithBool:true],  @"PlaySoundFeedback",
						  nil ]; // terminate the list
	[preferences registerDefaults:dict];
    
	[self setTapping:[preferences boolForKey:              @"TappingEnabled"]];
	[self setUseAppleCMDModifier:[preferences boolForKey:  @"UseAppleCMDModifier"]];
	[self setLockSystemAndPlayerVolume:[preferences boolForKey:  @"LockSystemAndPlayerVolume"]];
	[self setAutomaticUpdates:[preferences boolForKey:     @"AutomaticUpdates"]];
	[self setHideFromStatusBar:[preferences boolForKey:    @"hideFromStatusBarPreference"]];
    [self setHideVolumeWindow:[preferences boolForKey:     @"hideVolumeWindowPreference"]];
	[[self iTunesBtn] setState:[preferences boolForKey:    @"iTunesControl"]];
	if (@available(macOS 10.15, *)) {
		[[self iTunesBtn] setTitle:@"Music"];
	}
	[[self iTunesBtn] setState:[preferences boolForKey:    @"iTunesControl"]];
	[[self spotifyBtn] setState:[preferences boolForKey:   @"spotifyControl"]];
	[[self dopplerBtn] setState:[preferences boolForKey:   @"dopplerControl"]];
	[[self swinsianBtn] setState:[preferences boolForKey:  @"swinsianControl"]];
	//[[self systemBtn] setState:[preferences boolForKey:    @"systemControl"]];
	[[self systemBtn] setState:true];  // hard coded always to true
	[[self systemBtn] setEnabled:false];
	[self setPlaySoundFeedback:[preferences boolForKey:     @"PlaySoundFeedback"]];

	NSInteger volumeIncSetting = [preferences integerForKey:@"volumeIncrement"];
	[self setVolumeInc:volumeIncSetting];

	[[self volumeIncrementsSlider] setIntegerValue: volumeIncSetting];
}

- (IBAction)toggleAutomaticUpdates:(id)sender
{
	[self setAutomaticUpdates:![self AutomaticUpdates]];
}

- (void) setAutomaticUpdates:(bool)enabled
{
	NSMenuItem* menuItem=[_statusMenu itemWithTag:AUTOMATIC_UPDATES_ID];
	[menuItem setState:enabled];

	[preferences setBool:enabled forKey:@"AutomaticUpdates"];
	[preferences synchronize];

	_AutomaticUpdates=enabled;

	[[[self sparkle_updater] updater] setAutomaticallyChecksForUpdates:enabled];
}

- (IBAction)togglePlaySoundFeedback:(id)sender
{
	[self setPlaySoundFeedback:![self PlaySoundFeedback]];
}

- (void)setPlaySoundFeedback:(bool)enabled
{
	[preferences setBool:enabled forKey:@"PlaySoundFeedback"];
	[preferences synchronize];

	NSMenuItem* menuItem=[_statusMenu itemWithTag:PLAY_SOUND_FEEDBACK_ID];
	[menuItem setState:enabled];

	_PlaySoundFeedback=enabled;
}

- (void) setUseAppleCMDModifier:(bool)enabled
{
	NSMenuItem* menuItem=[_statusMenu itemWithTag:USE_APPLE_CMD_MODIFIER_MENU_ID];
	[menuItem setState:enabled];

	[preferences setBool:enabled forKey:@"UseAppleCMDModifier"];
	[preferences synchronize];

	_UseAppleCMDModifier=enabled;
}

- (IBAction)toggleUseAppleCMDModifier:(id)sender
{
	[self setUseAppleCMDModifier:![self UseAppleCMDModifier]];
}

- (IBAction)toggleLockSystemAndPlayerVolume:(id)sender
{
	[self setLockSystemAndPlayerVolume:![self LockSystemAndPlayerVolume]];
}

/*
 - (void) syncSystemVolume:(NSTimer*)theTimer
 {
 id runningPlayerPtr = [self runningPlayer];

 if (runningPlayerPtr != nil && runningPlayerPtr != systemAudio)
 {
 double systemVolume = [systemAudio currentVolume];
 double volume = [runningPlayerPtr currentVolume];
 double diff = systemVolume - volume;
 if (diff<0) diff = -diff;
 if( diff>1E-3 ) {
 NSLog(@"EQUALIZING");
 NSLog(@"Player volume: %1.5f",volume);
 NSLog(@"Apple Music: %d",runningPlayerPtr == iTunes);
 NSLog(@"System volume: %1.5f",systemVolume);
 NSLog(@"Diff: %1.10f",diff);
 [systemAudio setCurrentVolume:volume];
 [self setSystemVolume:volume];
 }
 }
 }
 */

- (void) setLockSystemAndPlayerVolume:(bool)enabled
{
	NSMenuItem* menuItem=[_statusMenu itemWithTag:LOCK_SYSTEM_AND_PLAYER_VOLUME_ID];
	[menuItem setState:enabled];

	[preferences setBool:enabled forKey:@"LockSystemAndPlayerVolume"];
	[preferences synchronize];

	_LockSystemAndPlayerVolume=enabled;

	/*
	 if(_LockSystemAndPlayerVolume) {
	 volumeLockSyncTimer = [NSTimer timerWithTimeInterval:volumeLockSyncInterval target:self selector:@selector(syncSystemVolume:) userInfo:nil repeats:YES];
	 [[NSRunLoop mainRunLoop] addTimer:volumeLockSyncTimer forMode:NSRunLoopCommonModes];
	 } else {
	 [volumeLockSyncTimer invalidate];
	 volumeLockSyncTimer = nil;
	 }
	 */
}

- (void)setTapping:(bool)enabled {
    if (eventTap) {
        CGEventTapEnable(eventTap, enabled);
        // Reset key state tracking to avoid stale state after re-creation
        _previousKeyCode = 0;
        _muteDown = NO;
    } else if (enabled) {
        // Try to recreate the tap if it was torn down
        if (![self createEventTap]) {
            NSLog(@"[Volume Control] Failed to recreate event tap.");
            // You could also show an alert here if desired
            enabled = NO; // fallback
        }
    }
    
    NSMenuItem *menuItem = [_statusMenu itemWithTag:TAPPING_ID];
    [menuItem setState:enabled];

    [[[self statusBar] button] setAppearsDisabled:!enabled];

    [preferences setBool:enabled forKey:@"TappingEnabled"];
    [preferences synchronize];

    _Tapping = enabled;
}

- (IBAction)toggleTapping:(id)sender
{
	[self setTapping:![self Tapping]];
}

- (IBAction)sliderValueChanged:(NSSliderCell*)slider
{
	NSInteger volumeIncSetting = [[self volumeIncrementsSlider] integerValue];

	[self setVolumeInc:volumeIncSetting];

	[preferences setInteger:volumeIncSetting forKey:@"volumeIncrement"];
	[preferences synchronize];

}

- (void) setVolumeInc:(NSInteger)volumeIncSetting
{
	switch(volumeIncSetting)
	{
		case 5:
			increment = 25;
			break;
		case 4:
			increment = 12.5;
			break;
		case 3:
			increment = 6.25;
			break;
		case 2:
			increment = 3.125;
			break;
		case 1:
		default:
			increment = 1.5625;
			break;

	}
}

- (IBAction)aboutPanel:(id)sender
{
    NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
    
    NSString *shortVersion = infoDict[@"CFBundleShortVersionString"]; // e.g. "1.7.7"
    NSString *buildNumber  = infoDict[@"CFBundleVersion"];            // e.g. "190"
    
    NSDictionary *options = @{NSAboutPanelOptionApplicationVersion: shortVersion, NSAboutPanelOptionVersion: buildNumber};
    
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [[NSApplication sharedApplication] orderFrontStandardAboutPanelWithOptions:options];
}

#pragma mark - Diagnostics

static NSString * const kGitHubIssuesURL = @"https://github.com/alberti42/Volume-Control/issues";

// hw.model, e.g. "MacBookPro18,3".
- (NSString *)hardwareModel
{
    size_t len = 0;
    if (sysctlbyname("hw.model", NULL, &len, NULL, 0) != 0 || len == 0) {
        return @"(unknown)";
    }
    char *buf = malloc(len);
    NSString *model = @"(unknown)";
    if (sysctlbyname("hw.model", buf, &len, NULL, 0) == 0) {
        model = [NSString stringWithUTF8String:buf] ?: @"(unknown)";
    }
    free(buf);
    return model;
}

// Automation (Apple Events) permission for a target app, without prompting.
// Returns the raw OSStatus so callers can both display it and branch on it —
// -playerDiagnosticsLine:enabled: queries a player only on noErr, so building
// the report never sends an Apple Event that would stall or prompt. Returns
// errAEEventFailed if the address descriptor itself could not be built.
- (OSStatus)automationPermissionForBundleID:(NSString *)bundleID
{
    const char *cstr = [bundleID UTF8String];
    if (cstr == NULL) {
        return errAEEventFailed;
    }

    AEAddressDesc target;
    if (AECreateDesc(typeApplicationBundleID, cstr, strlen(cstr), &target) != noErr) {
        return errAEEventFailed;
    }

    OSStatus status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false);
    AEDisposeDesc(&target);

    return status;
}

- (NSString *)automationStatusForBundleID:(NSString *)bundleID
{
    OSStatus status = [self automationPermissionForBundleID:bundleID];

    switch (status) {
        case errAEEventFailed:                  return @"(check failed)";
        case noErr:                             return @"granted";
        case errAEEventNotPermitted:            return @"denied";
        case errAEEventWouldRequireUserConsent: return @"not yet requested";
        case procNotFound:                      return @"app not running";
        default:                                return [NSString stringWithFormat:@"unknown (%d)", (int)status];
    }
}

// State of the CGEventTap that intercepts the keyboard volume keys. Everything
// downstream (players, devices, HUD) is irrelevant if the tap never receives an
// event, so this distinguishes "the keys never reach us" from "we act on them
// but nothing changes".
- (NSString *)eventTapDiagnostics
{
    BOOL created = (eventTap != NULL);
    BOOL valid   = created && CFMachPortIsValid(eventTap);
    BOOL live    = valid && CGEventTapIsEnabled(eventTap);

    NSMutableString *r = [NSMutableString string];
    [r appendFormat:@"Volume keys enabled (menu) : %@\n", [self Tapping] ? @"yes" : @"no"];
    [r appendFormat:@"Event tap created          : %@\n", created ? @"yes" : @"no"];
    [r appendFormat:@"Event tap port valid       : %@\n", valid   ? @"yes" : @"no"];
    [r appendFormat:@"Event tap receiving keys   : %@\n", live    ? @"yes" : @"no"];

    // The telling combination: macOS says we are trusted, yet the tap is not
    // running. That is what a stale Accessibility record looks like after an
    // app update or a change of signing identity, and re-ticking the existing
    // entry does not fix it — it has to be removed and added again.
    if (!live && AXIsProcessTrusted() && [self Tapping]) {
        [r appendString:@"\n# The tap is not receiving keys even though Accessibility is granted.\n"
                        @"# The permission record is probably stale: quit Volume Control, remove it\n"
                        @"# from System Settings > Privacy & Security > Accessibility with the \"-\"\n"
                        @"# button, then add it again and relaunch.\n"];
    }

    return r;
}

// Human-readable player state, shared by all four players: Music, Spotify,
// Doppler and Swinsian all use the same four-char codes in their sdef.
- (NSString *)descriptionForPlayerState:(NSInteger)state
{
    switch (state) {
        case 'kPSP': return @"playing";
        case 'kPSp': return @"paused";
        case 'kPSS': return @"stopped";
        default:     return [NSString stringWithFormat:@"state %ld", (long)state];
    }
}

// One line per player: whether the volume keys are allowed to target it (the
// tick in the menu), whether it is running, and whether it is playing. The keys
// act on the first ticked player that is playing, falling back to System, so an
// unticked or non-playing player explains "the keys do nothing" just as well as
// a dead event tap.
- (NSString *)playerDiagnosticsLine:(PlayerApplication *)player
                            enabled:(BOOL)enabled
{
    NSMutableString *s = [NSMutableString stringWithString:enabled ? @"targeted" : @"NOT targeted"];

    if (![player isRunning]) {
        [s appendString:@", not running"];
        return s;
    }
    [s appendString:@", running"];

    // -playerState sends an Apple Event. Only ask when we know it is permitted,
    // so building the report can never stall on, or trigger, a consent prompt.
    if ([self automationPermissionForBundleID:[player bundleIdentifier]] == noErr) {
        [s appendFormat:@", %@", [self descriptionForPlayerState:[player playerState]]];
    } else {
        [s appendString:@", state unknown (automation not granted)"];
    }

    return s;
}

- (NSString *)playerTargetingDiagnostics
{
    NSMutableString *r = [NSMutableString string];
    [r appendFormat:@"Apple Music : %@\n", [self playerDiagnosticsLine:iTunes   enabled:[_iTunesBtn state]   != NSControlStateValueOff]];
    [r appendFormat:@"Spotify     : %@\n", [self playerDiagnosticsLine:spotify  enabled:[_spotifyBtn state]  != NSControlStateValueOff]];
    [r appendFormat:@"Doppler     : %@\n", [self playerDiagnosticsLine:doppler  enabled:[_dopplerBtn state]  != NSControlStateValueOff]];
    [r appendFormat:@"Swinsian    : %@\n", [self playerDiagnosticsLine:swinsian enabled:[_swinsianBtn state] != NSControlStateValueOff]];
    [r appendFormat:@"System      : %@\n", ([_systemBtn state] != NSControlStateValueOff) ? @"targeted" : @"NOT targeted"];
    return r;
}

- (NSString *)settingsDiagnostics
{
    NSMutableString *r = [NSMutableString string];
    [r appendFormat:@"Command key inverts app/system : %@\n", [self UseAppleCMDModifier]       ? @"yes" : @"no"];
    [r appendFormat:@"Lock system and player volume  : %@\n", [self LockSystemAndPlayerVolume] ? @"yes" : @"no"];
    [r appendFormat:@"Volume HUD                     : %@\n", [self hideVolumeWindow]          ? @"hidden" : @"shown"];
    [r appendFormat:@"Hidden from status bar         : %@\n", [self hideFromStatusBar]         ? @"yes" : @"no"];
    [r appendFormat:@"Sound feedback                 : %@\n", [self PlaySoundFeedback]         ? @"on" : @"off"];
    return r;
}

// Builds the self-documenting plain-text diagnostics report placed on the
// clipboard. Sections are labelled and commented so the user can read it and
// remove anything they prefer not to share before posting.
- (NSString *)diagnosticsReport
{
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *shortVersion = info[@"CFBundleShortVersionString"] ?: @"?";
    NSString *buildNumber  = info[@"CFBundleVersion"] ?: @"?";
    NSString *osVersion    = [[NSProcessInfo processInfo] operatingSystemVersionString];

    NSMutableString *r = [NSMutableString string];
    [r appendString:@"# Volume Control — diagnostics\n"];
    [r appendString:@"# Plain text. Read it and delete any line you prefer not to share before posting.\n\n"];

    [r appendString:@"## Versions\n"];
    [r appendFormat:@"Volume Control : %@ (build %@)\n", shortVersion, buildNumber];
    [r appendFormat:@"macOS          : %@\n", osVersion];
    [r appendFormat:@"Mac model      : %@\n\n", [self hardwareModel]];

    [r appendString:@"## Permissions\n"];
    [r appendFormat:@"Accessibility (intercept volume keys) : %@\n", AXIsProcessTrusted() ? @"granted" : @"NOT granted"];
    [r appendString:@"Automation (control music players):\n"];
    [r appendFormat:@"  Apple Music : %@\n", [self automationStatusForBundleID:@"com.apple.Music"]];
    [r appendFormat:@"  Spotify     : %@\n", [self automationStatusForBundleID:@"com.spotify.client"]];
    [r appendFormat:@"  Doppler     : %@\n", [self automationStatusForBundleID:@"co.brushedtype.doppler-macos"]];
    [r appendFormat:@"  Swinsian    : %@\n\n", [self automationStatusForBundleID:@"com.swinsian.Swinsian"]];

    [r appendString:@"## Event tap (keyboard volume keys)\n"];
    [r appendString:@"# The event tap is how Volume Control sees the volume keys at all. If it is\n"];
    [r appendString:@"# not receiving keys, nothing below matters: the keys go straight to macOS.\n\n"];
    [r appendString:[self eventTapDiagnostics]];
    [r appendString:@"\n"];

    [r appendString:@"## Players targeted by the volume keys\n"];
    [r appendString:@"# \"targeted\" = ticked in the Volume Control menu. The keys act on the first\n"];
    [r appendString:@"# targeted player that is playing; if none is, they act on System.\n\n"];
    [r appendString:[self playerTargetingDiagnostics]];
    [r appendString:@"\n"];

    [r appendString:@"## Settings\n\n"];
    [r appendString:[self settingsDiagnostics]];
    [r appendString:@"\n"];

    [r appendString:@"## Audio output devices\n"];
    [r appendString:@"# If a device shows \"no\" everywhere it exposes no software volume control;\n"];
    [r appendString:@"# its volume must be changed on the device itself. master = one volume;\n"];
    [r appendString:@"# per-channel = separate left/right controls.\n\n"];
    [r appendString:[SystemApplication outputDevicesDiagnostics]];

    // Collapse the trailing blank line left by the per-device blocks into a
    // single newline.
    while ([r hasSuffix:@"\n"]) {
        [r deleteCharactersInRange:NSMakeRange(r.length - 1, 1)];
    }
    [r appendString:@"\n"];

    return r;
}

// A selectable text field showing the GitHub issues URL as a clickable link,
// for use as an NSAlert accessory view.
- (NSTextField *)diagnosticsLinkField
{
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 420, 18)];
    [field setBezeled:NO];
    [field setDrawsBackground:NO];
    [field setEditable:NO];
    [field setSelectable:YES];
    [field setAllowsEditingTextAttributes:YES];

    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:kGitHubIssuesURL];
    NSRange range = NSMakeRange(0, kGitHubIssuesURL.length);
    [attr addAttribute:NSLinkAttributeName value:kGitHubIssuesURL range:range];
    [attr addAttribute:NSForegroundColorAttributeName value:[NSColor linkColor] range:range];
    [attr addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
    [field setAttributedStringValue:attr];
    [field sizeToFit];

    return field;
}

- (IBAction)copyDiagnostics:(id)sender
{
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Copy Diagnostics";
    alert.informativeText = @"Volume Control will copy a diagnostics report to your clipboard, "
                            @"replacing its current contents.\n\n"
                            @"Nothing is sent over the Internet — it is plain text you can read and "
                            @"edit before sharing, for example when opening a GitHub issue:";
    alert.accessoryView = [self diagnosticsLinkField];
    [alert addButtonWithTitle:@"Copy to Clipboard"]; // NSAlertFirstButtonReturn (default)
    [alert addButtonWithTitle:@"Cancel"];

    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:[self diagnosticsReport] forType:NSPasteboardTypeString];

    NSAlert *done = [[NSAlert alloc] init];
    done.messageText = @"Diagnostics Copied";
    done.informativeText = @"The report is on your clipboard. Paste it into your GitHub issue.";
    [done addButtonWithTitle:@"Visit GitHub Issues Page"]; // NSAlertFirstButtonReturn
    [done addButtonWithTitle:@"Done"];

    if ([done runModal] == NSAlertFirstButtonReturn) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kGitHubIssuesURL]];
    }
}

- (void) receiveWakeNote: (NSNotification*) note
{
	NSLog(@"Received WakeNote: %@", [note name]);
	[self setTapping:[self Tapping]];
}

- (void)resetCurrentPlayer:(NSTimer*)theTimer
{
	// Keep memory of the current player until this timeout is reached
	// After the timeout, it is forced to check again what the current player is
	[checkPlayerTimer invalidate];
	checkPlayerTimer = nil;
	currentPlayer = nil;
}

- (id)runningPlayer
{
	if(currentPlayer)
		return currentPlayer;

	checkPlayerTimer = [NSTimer timerWithTimeInterval:checkPlayerTimeout target:self selector:@selector(resetCurrentPlayer:) userInfo:nil repeats:NO];
	[[NSRunLoop mainRunLoop] addTimer:checkPlayerTimer forMode:NSRunLoopCommonModes];

	if(_AppleCMDModifierPressed == _UseAppleCMDModifier)
	{
		if([_iTunesBtn state] && [iTunes isRunning] && [iTunes playerState] == iTunesEPlSPlaying)
		{
			currentPlayer = iTunes;
		}
		else if([_spotifyBtn state] && [spotify isRunning] && (SpotifyEPlS)[spotify playerState] == SpotifyEPlSPlaying)
		{
			currentPlayer = spotify;
		}
		else if([_dopplerBtn state] && [doppler isRunning] && (DopplerEPlS)[doppler playerState] == DopplerEPlSPlaying)
		{
			currentPlayer = doppler;
		}
		else if([_swinsianBtn state] && [swinsian isRunning] && (SwinsianPlayerState)[swinsian playerState] == SwinsianPlayerStatePlaying)
		{
			currentPlayer = swinsian;
		}
		else if([_systemBtn state])
		{
			currentPlayer = systemAudio;
		}
	}
	else
		currentPlayer = systemAudio;

	return currentPlayer;
}

- (void)setVolumeUp:(bool)increase
{
	id runningPlayerPtr = [self runningPlayer];

	if (runningPlayerPtr != nil)
	{
        // During a ramp (key held) use the locally-cached doubleVolume for
        // PlayerApplication instances to avoid a blocking ScriptingBridge round-trip
        // on every tick.  The cache is always current because setCurrentVolume:
        // updates it synchronously, and the ramp cannot start before at least one
        // write has been issued (the initial key-down press calls setVolumeUp: once
        // before the timer starts).
        // SystemApplication reads CoreAudio in-process (no IPC), so it is fast
        // enough to use currentVolume directly — and it has no doubleVolume cache.
        double volume = (self->volumeRampTimer != nil && [runningPlayerPtr isKindOfClass:[PlayerApplication class]])
                      ? [(PlayerApplication *)runningPlayerPtr doubleVolume]
                      : [runningPlayerPtr currentVolume];

#ifdef DEBUG
        double dbgPrevVolume = volume; // internal belief before this step
#endif

		if([runningPlayerPtr oldVolume]<0) // if it was not mute
		{
			//volume=[musicProgramPnt soundVolume]+_volumeInc*(increase?1:-1);
			volume += (increase?1:-1)*increment;
		}
		else // if it was mute
		{
			// [volumeImageLayer setContents:imgVolOn];  // restore the image of the speaker from mute speaker
			volume=[runningPlayerPtr oldVolume];
			[runningPlayerPtr setOldVolume:-1];  // this says that it is not mute
		}
		if (volume<0) volume=0;
		if (volume>100) volume=100;
        
        OSDGraphic image = 0;
        NSInteger numFullBlks = 0;
        NSInteger numQrtsBlks = 0;
        
        if (@available(macOS 16.0, *)) {
            // On Tahoe, show the new popover HUD anchored to the status item.
        } else {
            image = (volume > 0)? OSDGraphicSpeaker : OSDGraphicSpeakerMute;
            numFullBlks = floor(volume/6.25);
            numQrtsBlks = round((volume-(double)numFullBlks*6.25)/1.5625);
        }

		//NSLog(@"%d %d",(int)numFullBlks,(int)numQrtsBlks);

        if(!_hideVolumeWindow)
        {
            if (@available(macOS 16.0, *)) {
                // On Tahoe, show the new popover HUD anchored to the status item.
                [[TahoeVolumeHUD sharedManager] showHUDWithVolume:volume usingMusicPlayer:runningPlayerPtr andLabel:[systemAudio getDefaultOutputDeviceName] anchoredToStatusButton:([self hideFromStatusBar] ? nil : self.statusBar.button)];
            } else {
                if(image) {
                    id osdMgr = [self->OSDManager sharedManager];
                    if (osdMgr) {
                        [osdMgr showImage:image onDisplayID:CGSMainDisplayID() priority:OSDPriorityDefault msecUntilFade:1000 filledChiclets:(unsigned int)(round(((numFullBlks*4+numQrtsBlks)*1.5625)*100)) totalChiclets:(unsigned int)10000 locked:NO];
                    }
                }
            }
        }

#ifdef DEBUG
        NSLog(@"[VC] step  internal=%.2f  →  target=%.2f  (HUD: %@)",
              dbgPrevVolume,
              volume,
              _hideVolumeWindow ? @"hidden" : [NSString stringWithFormat:@"%.2f", volume]);
#endif

		[runningPlayerPtr setCurrentVolume:volume];
		if (_LockSystemAndPlayerVolume && runningPlayerPtr != systemAudio) {
			[systemAudio setCurrentVolume:volume];
		}

		if(self->volumeRampTimer == nil)
			[self emitAcousticFeedback];

		if( runningPlayerPtr == iTunes)
			[self setItunesVolume:volume];
		else if( runningPlayerPtr == spotify)
			[self setSpotifyVolume:volume];
		else if (runningPlayerPtr == doppler)
			[self setDopplerVolume:volume];
		else if (runningPlayerPtr == swinsian)
			[self setSwinsianVolume:volume];

		if(_LockSystemAndPlayerVolume || runningPlayerPtr == systemAudio)
			[self setSystemVolume:volume];

		[self refreshVolumeBar:(int)volume];
	}
}

- (void) setItunesVolume:(NSInteger)volume
{
	if (volume == -1)
		[[self iTunesPerc] setHidden:YES];
	else
	{
		[[self iTunesPerc] setHidden:NO];
		[[self iTunesPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",(int)volume]];
	}
}

- (void) setSpotifyVolume:(NSInteger)volume
{
	if (volume == -1)
		[[self spotifyPerc] setHidden:YES];
	else
	{
		[[self spotifyPerc] setHidden:NO];
		[[self spotifyPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",(int)volume]];
	}
}

- (void) setDopplerVolume:(NSInteger)volume
{
	if (volume == -1)
		[[self dopplerPerc] setHidden:YES];
	else
	{
		[[self dopplerPerc] setHidden:NO];
		[[self dopplerPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",(int)volume]];
	}
}

- (void) setSwinsianVolume:(NSInteger)volume
{
	if (volume == -1)
		[[self swinsianPerc] setHidden:YES];
	else
	{
		[[self swinsianPerc] setHidden:NO];
		[[self swinsianPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",(int)volume]];
	}
}

- (void) setSystemVolume:(NSInteger)volume
{
	if (volume == -1)
	{
		[[self systemPerc] setHidden:YES];
		return;
	}

	BOOL controllable = [systemAudio hasControllableVolume];

	// Reflect availability in the System check mark: unchecked when the output
	// device exposes no controllable volume, so the menu doesn't imply we can
	// change a volume we can't. The item stays disabled either way.
	[[self systemBtn] setState:controllable ? NSControlStateValueOn : NSControlStateValueOff];

	[[self systemPerc] setHidden:NO];
	if (controllable)
		[[self systemPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",(int)volume]];
	else
		[[self systemPerc] setStringValue:@"(n/a)"];
}

- (void) updatePercentages
{
	if([iTunes isRunning])
		[self setItunesVolume:[iTunes currentVolume]];
	else
		[self setItunesVolume:-1];

	if([spotify isRunning])
		[self setSpotifyVolume:[spotify currentVolume]];
	else
		[self setSpotifyVolume:-1];

	if ([doppler isRunning])
		[self setDopplerVolume:[doppler currentVolume]];
	else
		[self setDopplerVolume:-1];

	if ([swinsian isRunning])
		[self setSwinsianVolume:[swinsian currentVolume]];
	else
		[self setSwinsianVolume:-1];

	[self setSystemVolume:[systemAudio currentVolume]];
}

- (void) refreshVolumeBar:(NSInteger)volume
{
	NSInteger doubleFullRectangles = (NSInteger)round(32.0f * volume / 100.0f);
	NSInteger fullRectangles=doubleFullRectangles>>1;

	[CATransaction begin];
	[CATransaction setAnimationDuration: 0.0];
	[CATransaction setDisableActions: TRUE];

	if(volume==0)
	{
		[volumeImageLayer setContents:imgVolOff];
	}
	else
	{
		[volumeImageLayer setContents:imgVolOn];
	}

	CGRect frame;

	for(NSInteger i=0; i<fullRectangles; i++)
	{
		frame = [volumeBar[i] frame];
		frame.size.width=9;
		[volumeBar[i] setFrame:frame];

		[volumeBar[i] setHidden:NO];
	}
	for(NSInteger i=fullRectangles; i<16; i++)
	{
		frame = [volumeBar[i] frame];
		frame.size.width=9;
		[volumeBar[i] setFrame:frame];

		[volumeBar[i] setHidden:YES];
	}

	if(fullRectangles*2 != doubleFullRectangles)
	{

		frame = [volumeBar[fullRectangles] frame];
		frame.size.width=5;

		[volumeBar[fullRectangles] setFrame:frame];
		[volumeBar[fullRectangles] setHidden:NO];
	}

	[CATransaction commit];
}


#pragma mark - Hide From Status Bar

- (IBAction)toggleHideFromStatusBar:(id)sender
{
	[self setHideFromStatusBar:![self hideFromStatusBar]];
	if ([self hideFromStatusBar])
		[self showHideFromStatusBarHintPopover];
}

- (void)setHideFromStatusBar:(bool)want_hide
{
	// NSLog(@"Will it hide: %d",want_hide);

	_hideFromStatusBar=want_hide;

	NSMenuItem* menuItem=[_statusMenu itemWithTag:HIDE_FROM_STATUS_BAR_ID];
	[menuItem setState:[self hideFromStatusBar]];

	[preferences setBool:want_hide forKey:@"hideFromStatusBarPreference"];
	[preferences synchronize];
    
    if(want_hide){
        // Pre-create the popover so it's ready when we need to show it
        if (! _hideFromStatusBarHintPopover)
        {
            CGRect popoverRect = (CGRect) {
                .size.width = 250,
                .size.height = 63
            };

            _hideFromStatusBarHintLabel = [[NSTextField alloc] initWithFrame:CGRectInset(popoverRect, 10, 10)];
            [_hideFromStatusBarHintLabel setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
            [_hideFromStatusBarHintLabel setEditable:false];
            [_hideFromStatusBarHintLabel setSelectable:false];
            [_hideFromStatusBarHintLabel setBezeled:false];
            [_hideFromStatusBarHintLabel setBackgroundColor:[NSColor clearColor]];
            [_hideFromStatusBarHintLabel setAlignment:NSTextAlignmentCenter];

            _hintView = [[NSView alloc] initWithFrame:popoverRect];
            [_hintView addSubview:_hideFromStatusBarHintLabel];

            _hintVC = [[NSViewController alloc] init];
            [_hintVC setView:_hintView];

            _hideFromStatusBarHintPopover = [[NSPopover alloc] init];
            [_hideFromStatusBarHintPopover setContentViewController:_hintVC];
        }
    }

	if(want_hide && self.statusBar.isVisible)
	{
		if (![_statusBarHideTimer isValid] )
		{
			// NSLog(@"Start new timers");
			[self setHideFromStatusBarHintLabelWithSeconds:statusBarHideDelay];
			_statusBarHideTimer = [NSTimer timerWithTimeInterval:statusBarHideDelay target:self selector:@selector(doHideFromStatusBar:) userInfo:nil repeats:NO];
			[[NSRunLoop mainRunLoop] addTimer:_statusBarHideTimer forMode:NSRunLoopCommonModes];
			_hideFromStatusBarHintPopoverUpdateTimer = [NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(updateHideFromStatusBarHintPopover:) userInfo:nil repeats:YES];
			[[NSRunLoop mainRunLoop] addTimer:_hideFromStatusBarHintPopoverUpdateTimer forMode:NSRunLoopCommonModes];
		}
	}
	else
	{
		// NSLog(@"INVALIDATE TIMERS");
		[_hideFromStatusBarHintPopover close];
		[_statusBarHideTimer invalidate];
		_statusBarHideTimer = nil;
		[_hideFromStatusBarHintPopoverUpdateTimer invalidate];
		_hideFromStatusBarHintPopoverUpdateTimer = nil;
	}
}

-(void)hideStatusBarItem {
	if (self.statusBar) {
		self.statusBar.visible = NO;
		// Force the underlying NSStatusBarWindow out of visibility too. Setting
		// visible=NO alone removes the item from the menu bar composite but leaves
		// button.window.isVisible == YES, which would otherwise mislead anchoring
		// code (e.g. the Tahoe HUD) into using a stale cached frame.
		[self.statusBar.button.window orderOut:nil];
		// self.statusBar.length = 0; // collapses to zero width, however, some space remains allocated by macOS
	}
}

- (void)showStatusBarItem {
	if (self.statusBar) {
		self.statusBar.visible = YES;
		[self.statusBar.button.window orderFront:nil];
		// self.statusBar.length = NSSquareStatusItemLength;
	}
}

- (void)doHideFromStatusBar:(NSTimer*)aTimer
{
	// NSLog(@"doHideFromStatusBar");
	[_hideFromStatusBarHintPopoverUpdateTimer invalidate];
	_hideFromStatusBarHintPopoverUpdateTimer = nil;

	[_statusBarHideTimer invalidate];
	_statusBarHideTimer = nil;

	[_hideFromStatusBarHintPopover close];
	[self hideStatusBarItem];
	[self setHideFromStatusBar:true];
}

- (void)showHideFromStatusBarHintPopover
{
	if ([_hideFromStatusBarHintPopover isShown]) return;

	// NSLog(@"Will show popover");

	NSStatusBarButton *statusBarButton = [[self statusBar] button];
	[_hideFromStatusBarHintPopover showRelativeToRect:[statusBarButton bounds] ofView:statusBarButton preferredEdge:NSMinYEdge];
}

- (void)updateHideFromStatusBarHintPopover:(NSTimer*)aTimer
{
	NSDate *now = [NSDate date];
	NSTimeInterval remaining = [[_statusBarHideTimer fireDate] timeIntervalSinceDate:now];
	NSUInteger rounded = (NSUInteger)ceil(remaining);
	[self setHideFromStatusBarHintLabelWithSeconds:rounded];
	// NSLog(@"Timer remaining: %lu s", (unsigned long)rounded);
}

- (void)setHideFromStatusBarHintLabelWithSeconds:(NSUInteger)seconds
{
	[_hideFromStatusBarHintLabel setStringValue:[NSString stringWithFormat:@"Volume Control will hide after %ld seconds. Launch the app again to make the icon reappear in the menu bar.",seconds]];
}

#pragma mark - Music players

- (IBAction)toggleMusicPlayer:(id)sender
{
	if (sender == _iTunesBtn) {
		[preferences setBool:[sender state] forKey:@"iTunesControl"];
	}
	else if (sender == _spotifyBtn)
	{
		[preferences setBool:[sender state] forKey:@"spotifyControl"];
	}
	else if (sender == _dopplerBtn)
	{
		[preferences setBool:[sender state] forKey:@"dopplerControl"];
	}
	else if (sender == _swinsianBtn)
	{
		[preferences setBool:[sender state] forKey:@"swinsianControl"];
	}

	[preferences synchronize];
}

#pragma mark - NSMenuDelegate

- (IBAction)toggleHideVolumeWindow:(id)sender
{
	[self setHideVolumeWindow:![self hideVolumeWindow]];
}

- (void)setHideVolumeWindow:(bool)enabled
{
	_hideVolumeWindow=enabled;

	NSMenuItem* menuItem=[_statusMenu itemWithTag:HIDE_VOLUME_WINDOW_ID];
	[menuItem setState:[self hideVolumeWindow]];

	[preferences setBool:enabled forKey:@"hideVolumeWindowPreference"];
	[preferences synchronize];
}

- (void)menuWillOpen:(NSMenu *)menu
{
	[self updatePercentages];

	if(!_Tapping)
	{
		updateSystemVolumeTimer = [NSTimer timerWithTimeInterval:updateSystemVolumeInterval target:self selector:@selector(updateSystemVolume:) userInfo:nil repeats:YES];
		[[NSRunLoop mainRunLoop] addTimer:updateSystemVolumeTimer forMode:NSRunLoopCommonModes];
	}

	[_hideFromStatusBarHintPopover close];
	menuIsVisible=true;
}

- (void)menuDidClose:(NSMenu *)menu
{
	menuIsVisible=false;
	if([[self statusBar] isVisible] && [self hideFromStatusBar])
	{
		[self showHideFromStatusBarHintPopover];
	}

	// Remove timer used to update volume bar status in the menu bar
	if(updateSystemVolumeTimer)
	{
		[updateSystemVolumeTimer invalidate];
		updateSystemVolumeTimer = nil;
	}
}

#pragma mark - TahoeVolumeHUDDelegate

- (void)hud:(TahoeVolumeHUD *)hud didChangeVolume:(double)volume forPlayer:(PlayerApplication*)controlledPlayer{
    // This method is called every time the user drags the slider in the HUD.
    // The received 'volume' is a value between 0.0 and 1.0.

    // 1. Convert the 0.0-1.0 scale to the 0-100 scale our app uses.
    double volumePercent = volume * 100.0;

    // 2. Get the currently active player, just like we do for the volume keys.
    id runningPlayerPtr = controlledPlayer;
    
    if (runningPlayerPtr != nil) {
        // 3. Set the volume for the active player.
        [runningPlayerPtr setCurrentVolume:volumePercent];
        
        // 4. If volume is locked, also set the system volume.
        if (_LockSystemAndPlayerVolume && runningPlayerPtr != systemAudio) {
            [systemAudio setCurrentVolume:volumePercent];
        }

        // 5. Update the percentage labels in the status menu to reflect the change in real-time.
        if (runningPlayerPtr == iTunes) {
            [self setItunesVolume:volumePercent];
        } else if (runningPlayerPtr == spotify) {
            [self setSpotifyVolume:volumePercent];
        } else if (runningPlayerPtr == doppler) {
            [self setDopplerVolume:volumePercent];
        } else if (runningPlayerPtr == swinsian) {
            [self setSwinsianVolume:volumePercent];
        }

        if (_LockSystemAndPlayerVolume || runningPlayerPtr == systemAudio) {
            [self setSystemVolume:volumePercent];
        }
    }
}

- (void)didChangeVolumeFinal:(TahoeVolumeHUD *)hud {
    // This is called when the HUD fades out. We can play the feedback sound here
    [self emitAcousticFeedback];
}


#pragma mark - Sparkle Delegates

// This is the Objective-C equivalent of the Swift property 'supportsGentleScheduledUpdateReminders'
// This is the correct way to opt-in and remove the warning.
- (BOOL)supportsGentleScheduledUpdateReminders {
	return YES;
}

@end
