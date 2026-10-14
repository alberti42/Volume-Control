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
#import <libproc.h>

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
#define STAY_AHEAD_ID 10
#define CONTROL_DISPLAY_VOLUME_ID 11

// "Stay ahead of other apps": how often the tap order is checked,
// and the race rule. If Volume Control has to move its tap back in front
// kStayAheadRaceCount times within kStayAheadRaceWindow, another app is doing
// the same, and the option turns itself off.
static const NSTimeInterval kStayAheadCheckInterval = 1.0;
static const NSUInteger     kStayAheadRaceCount     = 3;
static const NSTimeInterval kStayAheadRaceWindow    = 10.0;

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

// When the tap last received a media key (volume, brightness, play, ...), as
// CFAbsoluteTime, or 0 if never. For the diagnostics report: unlike
// CGEventTapIsEnabled, it shows whether keys actually reach the tap.
static _Atomic(CFAbsoluteTime) gLastTapKeyTime = 0;

CGEventRef event_tap_callback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    // Keep track of how many consecutive timeouts we’ve seen.
    // macOS fires kCGEventTapDisabledByTimeout when it thinks the tap is “hung”
    // (e.g. if the app is suspended by TCC while showing an Apple Events dialog).
    // We auto-resume a few times, then give up and alert the user if it persists.
    static int timeout_count = 0;
    
    // macOS can also disable the tap "by user input". That says nothing about
    // our responsiveness, so re-enable without counting it as a timeout.
    if (type == kCGEventTapDisabledByUserInput) {
        dispatch_async(dispatch_get_main_queue(), ^{
            AppDelegate *app = (__bridge AppDelegate *)refcon;
            if ([app Tapping]) {
                [app setTapping:YES];
            }
        });
        return event;
    }

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

    // An event arrived, so the timeouts counted above are no longer consecutive.
    timeout_count = 0;

    NSEvent *sysEvent = [NSEvent eventWithCGEvent:event];
    if ([sysEvent subtype] != NX_SUBTYPE_AUX_CONTROL_BUTTONS) return event;

    // Let our own re-posted volume keys flow straight through to macOS, so it can
    // perform its native handling. Without this guard we would re-catch and
    // re-process them, defeating the passthrough (and looping).
    if ([sysEvent data2] == kPassThroughEventTag) return event;

    atomic_store(&gLastTapKeyTime, CFAbsoluteTimeGetCurrent());

    // Extract key info
    int keyFlags   = ([sysEvent data1] & 0x0000FFFF);
    int keyCode    = (([sysEvent data1] & 0xFFFF0000) >> 16);
    int keyState   = (((keyFlags & 0xFF00) >> 8)) == 0xA;
    bool keyIsRepeat = (keyFlags & 0x1);
    CGEventFlags keyModifier = [sysEvent modifierFlags] | 0xFFFF;
    // The modifiers held on the keyboard at this moment, independent of the
    // flags the system stored on the event. Recorded for the diagnostics report.
    CGEventFlags keyboardModifier = CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState);

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

    // With Option held, macOS opens the Sound settings (Option + volume or mute
    // key) or changes the volume in fine steps (Option + Shift + volume key).
    // Hand such a press to macOS, with its auto-repeats and release. Option
    // counts as held if either the event or the keyboard says so, as Command
    // does in -handleAsynchronouslyTappedEventWithKeyCode:.
    BOOL optionHeld = (CGEventGetFlags(event) & kCGEventFlagMaskAlternate) != 0 ||
                      (keyboardModifier & kCGEventFlagMaskAlternate) != 0;
    if (isMediaKey && keyState == 1 && optionHeld) {
        atomic_store(&gPassThroughKeyCode, keyCode);
        return event;
    }

    if(isMediaKey /*&& keyModifier==1114111*/) {
        // Hand off all actual logic to main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            AppDelegate *app = (__bridge AppDelegate *)refcon;
            [app handleAsynchronouslyTappedEventWithKeyCode:keyCode
                                                   keyState:keyState
                                                keyIsRepeat:keyIsRepeat
                                                keyModifier:keyModifier
                                           keyboardModifier:keyboardModifier];
        });
        
        return NULL;
    } else {
        // Always return immediately to keep the system input flowing
        return event;
    }
}


#pragma mark - Class extension for status menu

@class BetterDisplayClient, DisplayVolumeTarget;

@interface AppDelegate () <NSMenuDelegate>
{
	// Last initial volume key press, for the diagnostics report.
	NSDate*   _lastKeyPressDate;
	int       _lastKeyPressCode;
	BOOL      _lastKeyPressEventCmd;     // ⌘ bit on the event's flags
	BOOL      _lastKeyPressKeyboardCmd;  // ⌘ held on the keyboard (HID state)
	NSString* _lastKeyPressTarget;
	NSDate*   _eventTapCreatedDate;      // nil while there is no tap
	NSTimer*  _stayAheadTimer;           // checks the tap order while "Stay ahead of other apps" is on
	NSUInteger _stayAheadRecreations;    // taps re-created since the option was turned on
	NSDate*   _stayAheadFirstRecreation; // nil until the first re-creation
	NSMutableArray<NSDictionary *> *_stayAheadRecent; // last re-creations: @{@"date", @"app"}, newest last
	NSString* _stayAheadStopReason;      // why the option turned itself off; nil otherwise
	BetterDisplayClient* _betterDisplay;
	DisplayVolumeTarget* _displayTarget;  // nil unless BetterDisplay controls the output display
	NSString* _displayTargetDeviceUID;    // output device the lookup below was made for
	NSDate*   _displayLookupDate;         // when that lookup finished; nil while none
	BOOL      _displayLookupInFlight;
	NSString* _displayMatchNote;          // how the display was found, or why not; for diagnostics
	BOOL      _betterDisplayMissingShown; // the "not running" dialog was shown since BetterDisplay last ran
	BOOL      _displayVolumeJustRead;     // set while acting on a key press right after reading the display's volume
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

// Records whether an Apple Event sent through an SBApplication failed. The
// probe gives its own SBApplication one of these, so its result cannot mix
// with events that the main thread and the write queue send meanwhile.
@interface SBFailureRecorder : NSObject <SBApplicationDelegate>
@property (atomic, assign) BOOL failed;
@end

@implementation SBFailureRecorder
- (id)eventDidFail:(const AppleEvent *)event withError:(NSError *)error
{
    self.failed = YES;
    return nil;
}
@end

#pragma mark - BetterDisplay integration

static NSString * const kBetterDisplayBundleID = @"pro.betterdisplay.BetterDisplay";

// Sends requests to BetterDisplay through its notification-based integration
// (https://betterdisplay.pro/guide/integration/third-party-apps/): a JSON
// object with uuid, commands and parameters, posted as the object of
// pro.betterdisplay.BetterDisplay.request. BetterDisplay answers on
// pro.betterdisplay.BetterDisplay.response with the same uuid, a result and a
// payload. The integration is on by default and works in the free version.
@interface BetterDisplayClient : NSObject
- (BOOL)isInstalled;
- (BOOL)isRunning;
- (BOOL)listensToNativeAudioKeys;
// Calls completion on the main thread: answered = NO if BetterDisplay did not
// answer within timeout. A parameter value of NSNull is sent as a flag.
- (void)send:(NSString *)command
  parameters:(NSDictionary<NSString *, id> *)parameters
     timeout:(NSTimeInterval)timeout
  completion:(void (^)(BOOL answered, BOOL result, NSString *payload))completion;
@end

@implementation BetterDisplayClient {
    NSMutableDictionary<NSString *, void (^)(BOOL, BOOL, NSString *)> *_pending;
    id _observer;
}

- (instancetype)init
{
    if (self = [super init]) {
        _pending = [NSMutableDictionary dictionary];
        __weak BetterDisplayClient *weakSelf = self;
        _observer = [[NSDistributedNotificationCenter defaultCenter]
            addObserverForName:@"pro.betterdisplay.BetterDisplay.response" object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) { [weakSelf handleResponse:note]; }];
    }
    return self;
}

- (void)dealloc
{
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:_observer];
}

- (BOOL)isInstalled
{
    return [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:kBetterDisplayBundleID] != nil;
}

- (BOOL)isRunning
{
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:kBetterDisplayBundleID].count > 0;
}

// BetterDisplay's "Listen to native audio keys", read from its user defaults
// (BetterDisplay is not sandboxed). The setting is stored inverted as
// audioMediaKeyDisabled; the key is missing until the user changes the
// setting, and then the setting is on.
- (BOOL)listensToNativeAudioKeys
{
    CFStringRef app = (__bridge CFStringRef)kBetterDisplayBundleID;
    CFPreferencesAppSynchronize(app);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("audioMediaKeyDisabled"), app);
    BOOL disabled = NO;
    if (value) {
        if (CFGetTypeID(value) == CFBooleanGetTypeID())
            disabled = CFBooleanGetValue((CFBooleanRef)value);
        else if (CFGetTypeID(value) == CFNumberGetTypeID())
            disabled = [(__bridge NSNumber *)value boolValue];
        CFRelease(value);
    }
    return !disabled;
}

- (void)send:(NSString *)command
  parameters:(NSDictionary<NSString *, id> *)parameters
     timeout:(NSTimeInterval)timeout
  completion:(void (^)(BOOL, BOOL, NSString *))completion
{
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSDictionary *request = @{@"uuid": uuid, @"commands": @[command], @"parameters": parameters ?: @{}};
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:NULL];
    if (!data) {
        if (completion) completion(NO, NO, nil);
        return;
    }
    if (completion)
        _pending[uuid] = [completion copy];

    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:@"pro.betterdisplay.BetterDisplay.request"
                      object:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                    userInfo:nil
          deliverImmediately:YES];

    if (!completion)
        return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        void (^pending)(BOOL, BOOL, NSString *) = self->_pending[uuid];
        if (pending) {
            [self->_pending removeObjectForKey:uuid];
            pending(NO, NO, nil);
        }
    });
}

- (void)handleResponse:(NSNotification *)note
{
    if (![note.object isKindOfClass:[NSString class]])
        return;
    NSDictionary *response = [NSJSONSerialization JSONObjectWithData:[note.object dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    if (![response isKindOfClass:[NSDictionary class]] || ![response[@"uuid"] isKindOfClass:[NSString class]])
        return;
    void (^completion)(BOOL, BOOL, NSString *) = _pending[response[@"uuid"]];
    if (!completion)
        return;
    [_pending removeObjectForKey:response[@"uuid"]];
    id payload = response[@"payload"];
    completion(YES, [response[@"result"] boolValue], [payload isKindOfClass:[NSString class]] ? payload : nil);
}

@end

// A volume target, like a player or the system volume, for a display whose
// volume BetterDisplay controls (DDC). BetterDisplay answers through
// distributed notifications, which macOS delivers on the main thread, so the
// volume cannot be read synchronously like a player's. Instead AppDelegate
// calls -refreshVolume: before each key press and acts in its completion;
// currentVolume (0-100) holds the value read or last set. Each change is sent
// as an absolute value (0-1).
@interface DisplayVolumeTarget : NSObject
- (instancetype)initWithClient:(BetterDisplayClient *)client tagID:(NSString *)tagID name:(NSString *)name icon:(NSImage *)icon;
- (void)refreshVolume:(void (^)(BOOL ok))completion;
@property (assign, nonatomic) double currentVolume;
@property (assign, nonatomic) double oldVolume;
@property (strong, nonatomic) NSImage *icon;
@property (copy, nonatomic, readonly) NSString *tagID;
@property (copy, nonatomic, readonly) NSString *name;
@property (assign, nonatomic, readonly) BOOL lastReadOK; // NO until a read succeeds, and after a failed one
@end

@implementation DisplayVolumeTarget {
    BetterDisplayClient *_client;
}

- (instancetype)initWithClient:(BetterDisplayClient *)client tagID:(NSString *)tagID name:(NSString *)name icon:(NSImage *)icon
{
    if (self = [super init]) {
        _client = client;
        _tagID = [tagID copy];
        _name = [name copy];
        _icon = icon;
        _oldVolume = -1;
    }
    return self;
}

- (void)setCurrentVolume:(double)currentVolume
{
    _currentVolume = currentVolume;
    if (currentVolume < 0)
        return;
    NSString *value = [NSString stringWithFormat:@"%.4f", currentVolume / 100.0];
    [_client send:@"set" parameters:@{@"tagID": _tagID, @"volume": value} timeout:1.0 completion:nil];
}

- (void)refreshVolume:(void (^)(BOOL))completion
{
    [_client send:@"get" parameters:@{@"tagID": _tagID, @"volume": [NSNull null]} timeout:0.25
       completion:^(BOOL answered, BOOL result, NSString *payload) {
        BOOL ok = answered && result && payload.length > 0;
        self->_lastReadOK = ok;
        if (ok)
            self->_currentVolume = [payload doubleValue] * 100.0;
        if (completion) completion(ok);
    }];
}

@end

@interface PlayerApplication () <SBApplicationDelegate> {
    dispatch_queue_t _writeQueue;  // serial queue for ScriptingBridge writes
    BOOL             _writeInFlight; // YES while a write is executing on _writeQueue
    double           _pendingWrite;  // latest desired volume while write is in flight; -1 = none
    BOOL             _rampActive;    // YES while a key-hold ramp is in progress
    BOOL             _volumeReadTimedOut; // YES if the last -currentVolume read timed out
    double           _volumeReadTolerance; // a read closer than this to the cache keeps the cache
    _Atomic(BOOL)    _unresponsive;  // YES from an Apple Event timeout until the player answers again
    _Atomic(BOOL)    _probing;       // YES while the background probe is scheduled
    dispatch_queue_t _probeQueue;    // serial queue for probe Apple Events
    SBApplication   *_probePlayer;   // separate SBApplication, used only on _probeQueue
    id<SBApplicationDelegate> _probeFailureRecorder;
}
- (void)startProbing;
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
                          (fabs(sbVol - cachedVol) >= self->_volumeReadTolerance) ? @"  ⚠️ MISMATCH" : @"");
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
              (fabs(sbVol - expected) >= self->_volumeReadTolerance) ? @"  ⚠️ MISMATCH" : @"");
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

  // An unresponsive player gets no Apple Event from here; it reads as a
  // timed-out read without the 2 s wait.
  if (atomic_load(&_unresponsive)) {
    _volumeReadTimedOut = YES;
    return 0;
  }

  _volumeReadTimedOut = NO;
  double vol = [[musicPlayer valueForKey:@"soundVolume"] doubleValue];

  if (fabs(vol-[self doubleVolume])<_volumeReadTolerance) {
    vol = [self doubleVolume];
  }

	return vol;
}

- (BOOL) volumeReadTimedOut
{
	return _volumeReadTimedOut;
}

// SBApplicationDelegate: ScriptingBridge calls this for every Apple Event
// that fails, and the event then returns nil (or 0 for a scalar).
- (id) eventDidFail:(const AppleEvent *)event withError:(NSError *)error
{
	if ([error code] == errAETimeout) {
		_volumeReadTimedOut = YES;
		atomic_store(&_unresponsive, YES);
		[self startProbing];
	}
	return nil;
}

- (BOOL) isUnresponsive
{
	return atomic_load(&_unresponsive);
}

// While the player is unresponsive, ask it for its player state every 3 s
// on _probeQueue. When it answers, or quits, clear _unresponsive so the
// main thread talks to it again.
- (void) startProbing
{
	BOOL expected = NO;
	if (!atomic_compare_exchange_strong(&_probing, &expected, YES))
		return;

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), _probeQueue, ^{
		SBFailureRecorder *recorder = (SBFailureRecorder *)self->_probeFailureRecorder;
		recorder.failed = NO;
		BOOL running = [self->_probePlayer isRunning];
		if (running) {
			[self->_probePlayer valueForKey:@"playerState"];
		}
		atomic_store(&self->_probing, NO);
		if (!running || !recorder.failed) {
			atomic_store(&self->_unresponsive, NO);
		} else {
			[self startProbing];
		}
	});
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
    // An unresponsive player reads as not playing (0 is no player state),
    // so -runningPlayer falls back to the next player without waiting.
    if (atomic_load(&_unresponsive))
        return 0;
    return [[musicPlayer valueForKey:@"playerState"] integerValue];
}

-(id)initWithBundleIdentifier:(NSString*) bundleIdentifier andIcon:(NSImage*)icon {
	if (self = [super init])  {
        _bundleIdentifier = [bundleIdentifier copy];
        _playerStateScript = nil;
        _writeQueue    = dispatch_queue_create("io.alberti42.VolumeControl.sbWrite", DISPATCH_QUEUE_SERIAL);
        _writeInFlight = NO;
        _pendingWrite  = -1.0;
        // Spotify stores the volume as int(v * 655.35) and reports it divided
        // by 655.35 and truncated, so it mostly reads back one less than the
        // integer written: 50 -> 49, but 20 -> 20 (issue #43). With rounding
        // of the write, a read can differ from the cache by up to 1.5 while
        // both agree. A tolerance of 1 made volume up step 2 and volume down
        // step 3.38 at an increment of 3.125.
        _volumeReadTolerance = [bundleIdentifier isEqualToString:@"com.spotify.client"] ? 1.5 : 1.0;
		[self setCurrentVolume: -100];
		[self setOldVolume: -1];
		musicPlayer = [SBApplication applicationWithBundleIdentifier:bundleIdentifier];
        // Most Apple Events to the player are sent synchronously on the main
        // thread. With the default timeout (about 2 minutes), a player that
        // stops answering freezes the whole app, including the status item.
        // The timeout is in ticks (1/60 s): 120 ticks = 2 s.
        [(SBApplication *)musicPlayer setTimeout:120];
        [(SBApplication *)musicPlayer setDelegate:self];
        atomic_store(&_unresponsive, NO);
        atomic_store(&_probing, NO);
        _probeQueue = dispatch_queue_create("io.alberti42.VolumeControl.sbProbe", DISPATCH_QUEUE_SERIAL);
        _probePlayer = [SBApplication applicationWithBundleIdentifier:bundleIdentifier];
        [_probePlayer setTimeout:120];
        _probeFailureRecorder = [[SBFailureRecorder alloc] init];
        [_probePlayer setDelegate:_probeFailureRecorder];
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
@synthesize StayAheadOfOtherApps=_StayAheadOfOtherApps;
@synthesize ControlDisplayVolume=_ControlDisplayVolume;
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
    [self destroyEventTap];
    
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

// Remove the tap, its run loop source and the trust timer. Also removes a tap
// whose port is no longer valid, which would otherwise stay registered.
- (void)destroyEventTap
{
    if (eventTap) {
        if (CFMachPortIsValid(eventTap)) {
            CFMachPortInvalidate(eventTap);
        }
        CFRelease(eventTap);
        eventTap = nil;
    }
    if (runLoopSource) {
        CFRunLoopSourceInvalidate(runLoopSource);
        CFRelease(runLoopSource);
        runLoopSource = nil;
    }
    if (accessibilityCheckTimer) {
        [accessibilityCheckTimer invalidate];
        accessibilityCheckTimer = nil;
    }
    _eventTapCreatedDate = nil;
}

- (bool)createEventTap
{
    [self destroyEventTap];
    
    CGEventMask eventMask = CGEventMaskBit(NX_SYSDEFINED);
    eventTap = CGEventTapCreate(kCGSessionEventTap,
                                kCGHeadInsertEventTap,
                                kCGEventTapOptionDefault,
                                eventMask,
                                event_tap_callback,
                                (__bridge void *)self);
    
    if (eventTap != nil) {
        _eventTapCreatedDate = [NSDate date];
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
    [self destroyEventTap];
    
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
                                  keyboardModifier:(CGEventFlags)keyboardModifier
{
    // On some setups the volume key event arrives without the Command bit
    // although Command is held (seen on macOS 27 with a MacBookPro18,1), so
    // Command counts as pressed if either the event or the keyboard says so.
    BOOL eventCmd    = (keyModifier & NX_COMMANDMASK) == NX_COMMANDMASK;
    BOOL keyboardCmd = (keyboardModifier & kCGEventFlagMaskCommand) == kCGEventFlagMaskCommand;
    [self setAppleCMDModifierPressed:eventCmd || keyboardCmd];

    // Record the initial press for the diagnostics report. -runningPlayer
    // caches its result, so the calls below use the same target.
    if (keyState == 1 && !keyIsRepeat) {
        _lastKeyPressDate        = [NSDate date];
        _lastKeyPressCode        = keyCode;
        _lastKeyPressEventCmd    = eventCmd;
        _lastKeyPressKeyboardCmd = keyboardCmd;
        _lastKeyPressTarget      = [self nameOfPlayer:[self runningPlayer]];
    }

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

	// Muting stores the current volume to restore it later: read a display's
	// volume from BetterDisplay first (see -setVolumeUp:).
	if ([runningPlayerPtr isKindOfClass:[DisplayVolumeTarget class]] &&
	    [runningPlayerPtr oldVolume] < 0 && !_displayVolumeJustRead) {
		[(DisplayVolumeTarget *)runningPlayerPtr refreshVolume:^(BOOL ok) {
			if (!ok)
				return;
			self->_displayVolumeJustRead = YES;
			[self MuteVol];
			self->_displayVolumeJustRead = NO;
		}];
		return;
	}

	if (runningPlayerPtr != nil)
	{
		if([runningPlayerPtr oldVolume]<0)
		{
			double volume = [runningPlayerPtr currentVolume];

			// A timed-out read returns 0; storing it as the volume to restore
			// would unmute the player to 0, so ignore the key press.
			if ([runningPlayerPtr isKindOfClass:[PlayerApplication class]] &&
				[(PlayerApplication *)runningPlayerPtr volumeReadTimedOut])
				return;

			[runningPlayerPtr setOldVolume:volume];
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
	[self prefetchDisplayVolumeTarget];
	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(applicationDidLaunch:)
	                                                           name:NSWorkspaceDidLaunchApplicationNotification object:nil];

	// Look up the BetterDisplay display as soon as the output device changes,
	// so the first key press afterwards already finds it. Without this, that
	// press started the lookup and went to macOS.
	AudioObjectPropertyAddress defaultOutput = {
		kAudioHardwarePropertyDefaultOutputDevice,
		kAudioObjectPropertyScopeGlobal,
		kAudioObjectPropertyElementMain
	};
	__weak AppDelegate *weakSelf = self;
	AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &defaultOutput, dispatch_get_main_queue(),
		^(UInt32 count, const AudioObjectPropertyAddress *addresses) {
			[weakSelf prefetchDisplayVolumeTarget];
		});

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
		[self showUncontrollableSystemPercentage];
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
						  [NSNumber numberWithBool:false], @"StayAheadOfOtherApps",
						  [NSNumber numberWithBool:false], @"ControlDisplayVolume",
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
	[self setStayAheadOfOtherApps:[preferences boolForKey:   @"StayAheadOfOtherApps"]];
	[self setControlDisplayVolume:[preferences boolForKey:   @"ControlDisplayVolume"]];

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
    // Enabling always creates a new tap. A tap can stop receiving keys while
    // macOS still reports it valid and enabled (seen after sleep, issue #43);
    // re-enabling such a tap does not help, and only a new tap does. This is
    // also what the wake handler and the "Enable" menu item rely on.
    if (enabled) {
        if (![self createEventTap]) {
            NSLog(@"[Volume Control] Failed to create event tap.");
            enabled = NO;
        }
    } else {
        [self destroyEventTap];
    }
    // Reset key state tracking to avoid stale state after re-creation
    _previousKeyCode = 0;
    _muteDown = NO;
    
    NSMenuItem *menuItem = [_statusMenu itemWithTag:TAPPING_ID];
    [menuItem setState:enabled];

    [[[self statusBar] button] setAppearsDisabled:!enabled];

    [preferences setBool:enabled forKey:@"TappingEnabled"];
    [preferences synchronize];

    _Tapping = enabled;
}

- (IBAction)toggleStayAheadOfOtherApps:(id)sender
{
    if (![self StayAheadOfOtherApps]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Keep Volume Control ahead of other apps?";
        alert.informativeText =
            @"Another app that handles the volume keys, such as BetterDisplay or MonitorControl, "
            @"can take them away from Volume Control. If you can, turn off that app's handling "
            @"of the volume keys instead of using this option.\n\n"
            @"When this option is on, Volume Control checks every second whether such an app "
            @"receives the system keys before it. If one does, Volume Control reconnects to the "
            @"keyboard, which puts it in front again. Each check takes about 30 µs.\n\n"
            @"If the other app also moves itself back in front, the two apps would keep taking "
            @"turns. Volume Control then turns this option off and tells you which app it is.";
        [alert addButtonWithTitle:@"Yes"];
        [alert addButtonWithTitle:@"No"];
        [NSApp activateIgnoringOtherApps:YES];
        if ([alert runModal] != NSAlertFirstButtonReturn)
            return;
    }
    [self setStayAheadOfOtherApps:![self StayAheadOfOtherApps]];
}

- (void)setStayAheadOfOtherApps:(bool)enabled
{
    NSMenuItem *menuItem = [_statusMenu itemWithTag:STAY_AHEAD_ID];
    [menuItem setState:enabled];

    [preferences setBool:enabled forKey:@"StayAheadOfOtherApps"];
    [preferences synchronize];

    _StayAheadOfOtherApps = enabled;

    [_stayAheadTimer invalidate];
    _stayAheadTimer = nil;
    if (enabled) {
        _stayAheadRecreations     = 0;
        _stayAheadFirstRecreation = nil;
        _stayAheadRecent          = [NSMutableArray array];
        _stayAheadStopReason      = nil;
        _stayAheadTimer = [NSTimer timerWithTimeInterval:kStayAheadCheckInterval
                                                  target:self
                                                selector:@selector(checkStayingAhead:)
                                                userInfo:nil
                                                 repeats:YES];
        _stayAheadTimer.tolerance = 0.2;
        [[NSRunLoop mainRunLoop] addTimer:_stayAheadTimer forMode:NSRunLoopCommonModes];
    }
}

// If another app's tap that can block system keys comes before ours, creates
// a new tap, which macOS puts in front (kCGHeadInsertEventTap). Only taps at
// the session level count: a tap at the HID level comes before every session
// tap, so a new tap of ours could never get ahead of it.
- (void)checkStayingAhead:(NSTimer *)timer
{
    if (![self Tapping] || eventTap == NULL)
        return;

    pid_t first = [self firstBlockingSystemKeyTapProcess];
    if (first == 0 || first == getpid())
        return;

    NSString *app = [self nameOfProcess:first];
    NSDate *now = [NSDate date];
    _stayAheadRecreations++;
    if (!_stayAheadFirstRecreation)
        _stayAheadFirstRecreation = now;
    [_stayAheadRecent addObject:@{@"date": now, @"app": app}];
    while (_stayAheadRecent.count > kStayAheadRaceCount)
        [_stayAheadRecent removeObjectAtIndex:0];

    if (_stayAheadRecent.count == kStayAheadRaceCount &&
        [now timeIntervalSinceDate:_stayAheadRecent.firstObject[@"date"]] <= kStayAheadRaceWindow) {
        [self stopStayingAheadBecauseOf:app];
        return;
    }

    NSLog(@"[Volume Control] %@ receives system keys before Volume Control; creating a new tap.", app);
    [self setTapping:YES];
}

- (void)stopStayingAheadBecauseOf:(NSString *)app
{
    [self setStayAheadOfOtherApps:NO];

    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"HH:mm:ss";
    _stayAheadStopReason = [NSString stringWithFormat:@"turned off at %@: %@ moved itself back in front %lu times within %.0f s",
                            [f stringFromDate:[NSDate date]], app,
                            (unsigned long)kStayAheadRaceCount, kStayAheadRaceWindow];
    NSLog(@"[Volume Control] Stay ahead of other apps %@.", _stayAheadStopReason);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Stay Ahead of Other Apps Is Off";
        alert.informativeText = [NSString stringWithFormat:
            @"%@ moved itself back in front of Volume Control %lu times within %.0f seconds, "
            @"so the two apps were taking turns with the volume keys. Volume Control turned the "
            @"option off.\n\n"
            @"To use the volume keys with Volume Control, turn off %@'s handling of the volume keys, "
            @"or quit %@.",
            app, (unsigned long)kStayAheadRaceCount, kStayAheadRaceWindow, app, app];
        [alert addButtonWithTitle:@"OK"];
        [NSApp activateIgnoringOtherApps:YES];
        [alert runModal];
    });
}

#pragma mark - Control display volume (BetterDisplay)

- (IBAction)toggleControlDisplayVolume:(id)sender
{
    if ([self ControlDisplayVolume]) {
        [self setControlDisplayVolume:NO];
        return;
    }
    if (!_betterDisplay)
        _betterDisplay = [[BetterDisplayClient alloc] init];

    if (![_betterDisplay isInstalled]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Control Display Volume";
        alert.informativeText =
            @"The speakers of most monitors and TVs have no software volume control, so macOS "
            @"cannot change their volume. BetterDisplay can, and Volume Control can use it for the "
            @"volume keys. The free version of BetterDisplay is enough.";
        [alert addButtonWithTitle:@"Get BetterDisplay"];
        [alert addButtonWithTitle:@"Cancel"];
        [NSApp activateIgnoringOtherApps:YES];
        if ([alert runModal] == NSAlertFirstButtonReturn)
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/waydabber/BetterDisplay#readme"]];
        return;
    }

    if (![_betterDisplay isRunning]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"BetterDisplay Is Not Running";
        alert.informativeText = @"Volume Control controls display volume through BetterDisplay. "
                                @"Start BetterDisplay, then choose \"Control display volume\" again.";
        [alert addButtonWithTitle:@"Open BetterDisplay"];
        [alert addButtonWithTitle:@"Cancel"];
        [NSApp activateIgnoringOtherApps:YES];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            NSURL *url = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:kBetterDisplayBundleID];
            [[NSWorkspace sharedWorkspace] openApplicationAtURL:url
                                                 configuration:[NSWorkspaceOpenConfiguration configuration]
                                             completionHandler:nil];
        }
        return;
    }

    // BetterDisplay runs: check that it answers requests before turning on.
    [_betterDisplay send:@"get" parameters:@{@"identifiers": [NSNull null]} timeout:1.0
              completion:^(BOOL answered, BOOL result, NSString *payload) {
        NSAlert *alert = [[NSAlert alloc] init];
        if (!answered) {
            alert.messageText = @"BetterDisplay Did Not Answer";
            alert.informativeText = @"In BetterDisplay's settings, turn on \"CLI access and notification "
                                    @"based integration\", then choose \"Control display volume\" again.";
            [alert addButtonWithTitle:@"OK"];
            [NSApp activateIgnoringOtherApps:YES];
            [alert runModal];
            return;
        }
        NSString *explanation =
            @"Volume Control can change the volume of a display through BetterDisplay. It does so "
            @"when the volume keys act on the system volume and the output is a display that "
            @"BetterDisplay controls.";
        if ([self->_betterDisplay listensToNativeAudioKeys])
            explanation = [explanation stringByAppendingString:
                @"\n\n⚠️ \"Listen to native audio keys\" is on in BetterDisplay's settings. Open "
                @"BetterDisplay's settings and turn it off, so that only Volume Control handles "
                @"the volume keys."];
        alert.messageText = @"Use BetterDisplay to control the display's volume?";
        alert.informativeText = explanation;
        [alert addButtonWithTitle:@"Yes"];
        [alert addButtonWithTitle:@"No"];
        [NSApp activateIgnoringOtherApps:YES];
        if ([alert runModal] == NSAlertFirstButtonReturn)
            [self setControlDisplayVolume:YES];
    }];
}

- (void)setControlDisplayVolume:(bool)enabled
{
    NSMenuItem *menuItem = [_statusMenu itemWithTag:CONTROL_DISPLAY_VOLUME_ID];
    [menuItem setState:enabled];

    [preferences setBool:enabled forKey:@"ControlDisplayVolume"];
    [preferences synchronize];

    _ControlDisplayVolume = enabled;
    if (enabled && !_betterDisplay)
        _betterDisplay = [[BetterDisplayClient alloc] init];

    // Look the display up again on the next key press.
    _displayTarget = nil;
    _displayTargetDeviceUID = nil;
    _displayLookupDate = nil;
    _displayMatchNote = nil;
    _betterDisplayMissingShown = NO;
    if (enabled)
        [self prefetchDisplayVolumeTarget];
}

// Starts the display lookup ahead of the first key press, without the
// "not running" dialog. Called when the option is turned on, after launch,
// and when BetterDisplay starts.
- (void)prefetchDisplayVolumeTarget
{
    if (![self ControlDisplayVolume] || !systemAudio || [systemAudio hasControllableVolume] || ![_betterDisplay isRunning])
        return;
    NSString *uid = [systemAudio getDefaultOutputDeviceUID];
    if (uid && !_displayLookupInFlight && !(_displayTarget && [uid isEqualToString:_displayTargetDeviceUID]))
        [self lookUpDisplayForDeviceUID:uid name:[systemAudio getDefaultOutputDeviceName]];
}

- (void)applicationDidLaunch:(NSNotification *)note
{
    NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
    if ([app.bundleIdentifier isEqualToString:kBetterDisplayBundleID]) {
        // Give BetterDisplay a moment to set up its integration.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self->_displayTarget = nil;
            self->_displayTargetDeviceUID = nil;
            [self prefetchDisplayVolumeTarget];
        });
    }
}

// The display target for the current output device, or nil to keep the system
// volume (and pass the key on to macOS, see -handleAsynchronouslyTapped...).
// Uses only cached results: a lookup runs in the background, so the first key
// press after the output changes still goes to macOS.
- (DisplayVolumeTarget *)displayVolumeTarget
{
    if (![self ControlDisplayVolume] || [systemAudio hasControllableVolume])
        return nil;

    if (![_betterDisplay isRunning]) {
        [self showBetterDisplayMissingOnce];
        _displayTarget = nil;
        _displayTargetDeviceUID = nil;
        return nil;
    }
    _betterDisplayMissingShown = NO;

    NSString *uid = [systemAudio getDefaultOutputDeviceUID];
    BOOL sameDevice = (uid && [uid isEqualToString:_displayTargetDeviceUID]);
    if (sameDevice && _displayTarget)
        return _displayTarget;
    // No display found for this device: look again after 10 s, in case
    // BetterDisplay has meanwhile started controlling it.
    if (sameDevice && _displayLookupDate && -[_displayLookupDate timeIntervalSinceNow] < 10.0)
        return nil;
    if (uid && !_displayLookupInFlight)
        [self lookUpDisplayForDeviceUID:uid name:[systemAudio getDefaultOutputDeviceName]];
    return nil;
}

- (void)showBetterDisplayMissingOnce
{
    if (_betterDisplayMissingShown)
        return;
    _betterDisplayMissingShown = YES;
    NSString *device = [systemAudio getDefaultOutputDeviceName];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"BetterDisplay Is Not Running";
        alert.informativeText = [NSString stringWithFormat:
            @"\"Control display volume\" is on, but BetterDisplay is not running, so Volume Control "
            @"cannot change the volume of %@. Start BetterDisplay, or turn off \"Control display volume\".",
            device];
        [alert addButtonWithTitle:@"OK"];
        [NSApp activateIgnoringOtherApps:YES];
        [alert runModal];
    });
}

// For a display's audio device, macOS builds the UID from the display's EDID,
// e.g. "1D742532-0000-0000-1523-0104C5462778": vendor (1D74), product with its
// two bytes swapped (2532 = 0x3225), serial number (0000-0000), week (15 hex)
// and year (23 hex, + 1990). Returns nil if the UID does not have this form.
static NSDictionary *EDIDFieldsFromAudioDeviceUID(NSString *uid)
{
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
        @"^([0-9A-F]{4})([0-9A-F]{2})([0-9A-F]{2})-([0-9A-F]{2})([0-9A-F]{2})-([0-9A-F]{2})([0-9A-F]{2})-([0-9A-F]{2})([0-9A-F]{2})-"
        options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:uid options:0 range:NSMakeRange(0, uid.length)];
    if (!m)
        return nil;
    unsigned v[10] = {0};
    for (NSUInteger i = 1; i <= 9; i++)
        [[NSScanner scannerWithString:[uid substringWithRange:[m rangeAtIndex:i]]] scanHexInt:&v[i]];
    unsigned serialLE = v[4] | (v[5] << 8) | (v[6] << 16) | ((unsigned)v[7] << 24);
    unsigned serialBE = ((unsigned)v[4] << 24) | (v[5] << 16) | (v[6] << 8) | v[7];
    return @{@"vendor": @(v[1]),
             @"model": @(v[2] | (v[3] << 8)),
             @"serials": @[@(serialLE), @(serialBE)],
             @"week": @(v[8]),
             @"year": @(v[9] + 1990)};
}

- (void)lookUpDisplayForDeviceUID:(NSString *)uid name:(NSString *)deviceName
{
    _displayLookupInFlight = YES;
    [_betterDisplay send:@"get" parameters:@{@"identifiers": [NSNull null]} timeout:1.0
              completion:^(BOOL answered, BOOL result, NSString *payload) {
        self->_displayLookupInFlight = NO;
        self->_displayTargetDeviceUID = uid;
        self->_displayLookupDate = [NSDate date];
        self->_displayTarget = nil;
        if (!answered || !result || payload.length == 0) {
            self->_displayMatchNote = @"BetterDisplay did not answer";
            return;
        }

        // The payload lists one JSON object per display, separated by commas.
        NSData *json = [[NSString stringWithFormat:@"[%@]", payload] dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *items = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
        NSMutableArray<NSDictionary *> *displays = [NSMutableArray array];
        for (id item in ([items isKindOfClass:[NSArray class]] ? items : @[]))
            if ([item isKindOfClass:[NSDictionary class]] && [item[@"deviceType"] isEqual:@"Display"] && item[@"tagID"])
                [displays addObject:item];

        NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
        NSString *how = @"EDID";
        NSDictionary *edid = EDIDFieldsFromAudioDeviceUID(uid);
        if (edid) {
            for (NSDictionary *d in displays) {
                if ([d[@"vendor"] integerValue] == [edid[@"vendor"] integerValue] &&
                    [d[@"model"] integerValue] == [edid[@"model"] integerValue] &&
                    [edid[@"serials"] containsObject:@([d[@"serial"] longLongValue])] &&
                    [d[@"weekOfManufacture"] integerValue] == [edid[@"week"] integerValue] &&
                    [d[@"yearOfManufacture"] integerValue] == [edid[@"year"] integerValue])
                    [matches addObject:d];
            }
        }
        if (matches.count == 0) {
            how = @"name";
            for (NSDictionary *d in displays)
                if ([d[@"name"] isEqual:deviceName] || [d[@"originalName"] isEqual:deviceName] || [d[@"productName"] isEqual:deviceName])
                    [matches addObject:d];
        }
        if (matches.count == 0) {
            self->_displayMatchNote = [NSString stringWithFormat:@"BetterDisplay controls no display matching \"%@\"", deviceName];
            return;
        }

        NSDictionary *d = matches.firstObject;
        DisplayVolumeTarget *target = [[DisplayVolumeTarget alloc] initWithClient:self->_betterDisplay
                                                                            tagID:[NSString stringWithFormat:@"%@", d[@"tagID"]]
                                                                             name:d[@"name"] ?: deviceName
                                                                             icon:[self->systemAudio icon]];
        NSString *note = [NSString stringWithFormat:@"\"%@\" (tagID %@), matched by %@", target.name, target.tagID, how];
        if (matches.count > 1)
            note = [note stringByAppendingFormat:@"; %lu displays match, the first is used", (unsigned long)matches.count];
        [target refreshVolume:^(BOOL ok) {
            if (![uid isEqualToString:self->_displayTargetDeviceUID])
                return;
            if (!ok) {
                self->_displayMatchNote = [note stringByAppendingString:@"; BetterDisplay could not read its volume"];
                return;
            }
            self->_displayMatchNote = note;
            self->_displayTarget = target;
        }];
    }];
}

// Marks the menu item with ⚠️ while the option is on but cannot work as
// intended; the tooltip says why.
- (void)updateControlDisplayVolumeMenuItem
{
    NSMenuItem *item = [_statusMenu itemWithTag:CONTROL_DISPLAY_VOLUME_ID];
    NSString *problem = nil;
    if ([self ControlDisplayVolume]) {
        BetterDisplayClient *client = _betterDisplay ?: [[BetterDisplayClient alloc] init];
        if (![client isInstalled])
            problem = @"BetterDisplay is not installed.";
        else if ([client listensToNativeAudioKeys])
            problem = @"\"Listen to native audio keys\" is on in BetterDisplay's settings. Turn it off, "
                      @"so that only Volume Control handles the volume keys.";
        else if (![client isRunning])
            problem = @"BetterDisplay is not running.";
    }
    item.title = problem ? @"⚠️ Control display volume..." : @"Control display volume...";
    item.toolTip = problem;
}

- (NSString *)controlDisplayVolumeDiagnostics
{
    NSMutableString *r = [NSMutableString string];
    [r appendFormat:@"Setting       : %@\n", [self ControlDisplayVolume] ? @"on" : @"off"];
    BetterDisplayClient *client = _betterDisplay ?: [[BetterDisplayClient alloc] init];
    [r appendFormat:@"BetterDisplay : %@\n", ![client isInstalled] ? @"not installed"
                                            : [client isRunning] ? @"running" : @"installed, not running"];
    if ([client isInstalled])
        [r appendFormat:@"Listen to native audio keys (BetterDisplay) : %@\n", [client listensToNativeAudioKeys] ? @"on" : @"off"];
    if ([self ControlDisplayVolume])
        [r appendFormat:@"Display       : %@\n", _displayMatchNote ?: @"not looked up yet"];
    return r;
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

// Returned by -automationPermissionForBundleID: when macOS did not answer in
// time. Positive, so it cannot collide with an Apple Event error code.
static const OSStatus kAutomationCheckTimedOut = 1;

// Automation (Apple Events) permission for a target app, without prompting.
// Returns the raw OSStatus so callers can both display it and branch on it —
// -playerDiagnosticsLine:enabled: queries a player only on noErr, so building
// the report never sends an Apple Event that would stall or prompt. Returns
// errAEEventFailed if the address descriptor itself could not be built.
//
// AEDeterminePermissionToAutomateTarget can block for a long time: on
// macOS 27 it had not returned for Spotify, running or not, after 1 min 43 s,
// while it answered for Apple Music in 0.04 s. Called on the main thread, that froze Volume Control.
// The check therefore runs on a background queue, and the caller waits at most
// 1 s. A check that is still waiting from an earlier call is not started again;
// the caller gets kAutomationCheckTimedOut at once.
- (OSStatus)automationPermissionForBundleID:(NSString *)bundleID
{
    const char *cstr = [bundleID UTF8String];
    if (cstr == NULL) {
        return errAEEventFailed;
    }

    static NSMutableSet<NSString *> *pending;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ pending = [NSMutableSet set]; });

    @synchronized (pending) {
        if ([pending containsObject:bundleID])
            return kAutomationCheckTimedOut;
        [pending addObject:bundleID];
    }

    NSString *key = [bundleID copy];
    __block _Atomic(OSStatus) result = errAEEventFailed;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        const char *id = [key UTF8String];
        AEAddressDesc target;
        OSStatus status = AECreateDesc(typeApplicationBundleID, id, strlen(id), &target);
        if (status == noErr) {
            status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false);
            AEDisposeDesc(&target);
        } else {
            status = errAEEventFailed;
        }
        atomic_store(&result, status);
        @synchronized (pending) {
            [pending removeObject:key];
        }
        dispatch_semaphore_signal(done);
    });

    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC))) != 0)
        return kAutomationCheckTimedOut;
    return atomic_load(&result);
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
        case kAutomationCheckTimedOut:          return @"macOS did not answer within 1 s";
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

    NSString *createdText = (created && _eventTapCreatedDate)
        ? [NSString stringWithFormat:@"yes, %.0f s ago", -[_eventTapCreatedDate timeIntervalSinceNow]]
        : (created ? @"yes" : @"no");

    CFAbsoluteTime lastKey = atomic_load(&gLastTapKeyTime);
    NSString *lastKeyText = (lastKey == 0)
        ? @"none since Volume Control started"
        : [NSString stringWithFormat:@"%.0f s ago", CFAbsoluteTimeGetCurrent() - lastKey];

    NSMutableString *r = [NSMutableString string];
    [r appendFormat:@"Volume keys enabled (menu) : %@\n", [self Tapping] ? @"yes" : @"no"];
    [r appendFormat:@"Event tap created          : %@\n", createdText];
    [r appendFormat:@"Event tap port valid       : %@\n", valid   ? @"yes" : @"no"];
    [r appendFormat:@"Event tap enabled          : %@\n", live    ? @"yes" : @"no"];
    [r appendFormat:@"Last media key seen by tap : %@\n", lastKeyText];

    // The telling combination: macOS says we are trusted, yet the tap is not
    // running. That is what a stale Accessibility record looks like after an
    // app update or a change of signing identity, and re-ticking the existing
    // entry does not fix it — it has to be removed and added again.
    if (!live && AXIsProcessTrusted() && [self Tapping]) {
        [r appendString:@"\n# The tap is not enabled even though Accessibility is granted.\n"
                        @"# The permission record is probably stale: quit Volume Control, remove it\n"
                        @"# from System Settings > Privacy & Security > Accessibility with the \"-\"\n"
                        @"# button, then add it again and relaunch.\n"];
    }

    return r;
}

- (NSString *)nameOfProcess:(pid_t)pid
{
    NSString *name = [[NSRunningApplication runningApplicationWithProcessIdentifier:pid] localizedName];
    if (!name) {
        char buf[2 * MAXCOMLEN] = {0};
        name = (proc_name(pid, buf, sizeof(buf)) > 0)
            ? [NSString stringWithUTF8String:buf] : @"unknown process";
    }
    return name;
}

// The process of the first enabled, session-level tap that can block
// NX_SYSDEFINED events (the system keys), in the order CGGetEventTapList
// returns them; 0 if there is none or the list is not available.
- (pid_t)firstBlockingSystemKeyTapProcess
{
    uint32_t count = 0;
    if (CGGetEventTapList(0, NULL, &count) != kCGErrorSuccess || count == 0)
        return 0;

    CGEventTapInformation *taps = calloc(count, sizeof(CGEventTapInformation));
    if (!taps)
        return 0;
    pid_t first = 0;
    if (CGGetEventTapList(count, taps, &count) == kCGErrorSuccess) {
        for (uint32_t i = 0; i < count; i++) {
            CGEventTapInformation t = taps[i];
            if (t.enabled && (t.eventsOfInterest & CGEventMaskBit(NX_SYSDEFINED)) &&
                t.options == kCGEventTapOptionDefault && t.tapPoint == kCGSessionEventTap) {
                first = t.tappingProcess;
                break;
            }
        }
    }
    free(taps);
    return first;
}

// State of "Stay ahead of other apps", for the diagnostics report.
- (NSString *)stayAheadDiagnostics
{
    NSMutableString *r = [NSMutableString string];
    if ([self StayAheadOfOtherApps])
        [r appendFormat:@"Setting                 : on, check every %.0f s\n", kStayAheadCheckInterval];
    else if (_stayAheadStopReason)
        [r appendFormat:@"Setting                 : off (%@)\n", _stayAheadStopReason];
    else
        [r appendString:@"Setting                 : off\n"];

    if (_stayAheadRecreations == 0)
        return r;

    [r appendFormat:@"Taps re-created         : %lu since the option was turned on\n", (unsigned long)_stayAheadRecreations];
    if (_stayAheadRecreations >= 2) {
        NSDate *last = [_stayAheadRecent.lastObject objectForKey:@"date"];
        [r appendFormat:@"Average time between    : %.1f s\n",
            [last timeIntervalSinceDate:_stayAheadFirstRecreation] / (double)(_stayAheadRecreations - 1)];
    }
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"HH:mm:ss";
    NSString *label = @"Last re-creations       : ";
    for (NSDictionary *e in [_stayAheadRecent reverseObjectEnumerator]) {
        [r appendFormat:@"%@%@ (%@ was ahead)\n", label, [f stringFromDate:e[@"date"]], e[@"app"]];
        label = @"                          ";
    }
    return r;
}

// Every enabled event tap that receives NX_SYSDEFINED events (the volume
// keys), in the order CGGetEventTapList returns them, with the owning
// process. A tap that can block and sits before ours can take the volume keys
// away from Volume Control while ours still receives other events (issue #43).
- (NSString *)volumeKeyTapsDiagnostics
{
    uint32_t count = 0;
    if (CGGetEventTapList(0, NULL, &count) != kCGErrorSuccess || count == 0)
        return @"(the list of event taps is not available)\n";

    CGEventTapInformation *taps = calloc(count, sizeof(CGEventTapInformation));
    if (!taps)
        return @"(the list of event taps is not available)\n";
    if (CGGetEventTapList(count, taps, &count) != kCGErrorSuccess) {
        free(taps);
        return @"(the list of event taps is not available)\n";
    }

    NSMutableString *r = [NSMutableString string];
    pid_t ownPid = getpid();
    int shown = 0;
    for (uint32_t i = 0; i < count; i++) {
        CGEventTapInformation t = taps[i];
        if (!t.enabled || !(t.eventsOfInterest & CGEventMaskBit(NX_SYSDEFINED)))
            continue;

        NSString *name = [self nameOfProcess:t.tappingProcess];
        if (t.tappingProcess == ownPid)
            name = [name stringByAppendingString:@" (this app)"];

        const char *point = (t.tapPoint == kCGHIDEventTap) ? "HID"
                          : (t.tapPoint == kCGSessionEventTap) ? "session"
                          : "app";
        [r appendFormat:@"%d. %@ (pid %d): %s, %s level\n", ++shown, name, t.tappingProcess,
            (t.options == kCGEventTapOptionListenOnly) ? "listens" : "can block", point];
    }
    free(taps);

    if (shown == 0)
        [r appendString:@"(none)\n"];
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
    if ([player isUnresponsive]) {
        [s appendString:@", not responding to Apple Events"];
    } else {
        OSStatus permission = [self automationPermissionForBundleID:[player bundleIdentifier]];
        if (permission == noErr) {
            [s appendFormat:@", %@", [self descriptionForPlayerState:[player playerState]]];
        } else if (permission == kAutomationCheckTimedOut) {
            [s appendString:@", state unknown (automation permission check did not answer)"];
        } else {
            [s appendString:@", state unknown (automation not granted)"];
        }
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
    [r appendFormat:@"System      : %@\n", [systemAudio hasControllableVolume]
        ? @"targeted, volume controllable"
        : @"targeted, no software volume control (keys are passed on to macOS)"];
    return r;
}

- (NSString *)nameOfPlayer:(id)player
{
    if (player == nil)         return @"none";
    if (player == iTunes)      return @"Apple Music";
    if (player == spotify)     return @"Spotify";
    if (player == doppler)     return @"Doppler";
    if (player == swinsian)    return @"Swinsian";
    if (player == systemAudio) return @"System";
    return @"?";
}

// The last initial volume key press. The volume keys arrive as system-defined
// events; the app counts ⌘ as pressed if the flags stored on the event or the
// keyboard state say so. When the event arrives without the ⌘ bit, "on the
// event" reads "no" while "on the keyboard" reads "yes".
- (NSString *)lastKeyPressDiagnostics
{
    if (_lastKeyPressDate == nil)
        return @"No volume key pressed since Volume Control started.\n";

    NSString *key;
    switch (_lastKeyPressCode) {
        case NX_KEYTYPE_SOUND_UP:   key = @"volume up";   break;
        case NX_KEYTYPE_SOUND_DOWN: key = @"volume down"; break;
        case NX_KEYTYPE_MUTE:       key = @"mute";        break;
        default:                    key = [NSString stringWithFormat:@"key %d", _lastKeyPressCode]; break;
    }

    NSMutableString *r = [NSMutableString string];
    [r appendFormat:@"Key                    : %@, %.0f s ago\n", key, -[_lastKeyPressDate timeIntervalSinceNow]];
    [r appendFormat:@"Command on the event   : %@\n", _lastKeyPressEventCmd    ? @"yes" : @"no"];
    [r appendFormat:@"Command on the keyboard: %@\n", _lastKeyPressKeyboardCmd ? @"yes" : @"no"];
    [r appendFormat:@"Acted on               : %@\n", _lastKeyPressTarget];
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
    [r appendString:@"# not receiving keys, nothing below matters: the keys go straight to macOS.\n"];
    [r appendString:@"# \"Last media key seen by tap\" updates on every volume key press. If it\n"];
    [r appendString:@"# does not, the keys do not reach Volume Control.\n\n"];
    [r appendString:[self eventTapDiagnostics]];
    [r appendString:@"\n"];

    [r appendString:@"## Apps that intercept system keys\n"];
    [r appendString:@"# System keys are the volume, brightness and media keys. Each app below\n"];
    [r appendString:@"# sees every system key press, in the order macOS lists them; which keys it\n"];
    [r appendString:@"# acts on depends on the app's settings. \"can block\" = it can stop a key\n"];
    [r appendString:@"# from reaching the apps after it; \"listens\" = it only watches. An app\n"];
    [r appendString:@"# that can block, listed before Volume Control, may take the volume keys away.\n\n"];
    [r appendString:[self volumeKeyTapsDiagnostics]];
    [r appendString:@"\n"];

    [r appendString:@"## Control display volume\n"];
    [r appendString:@"# When on, the volume keys change the volume of a display through\n"];
    [r appendString:@"# BetterDisplay when the system volume is the target and the output\n"];
    [r appendString:@"# device has no software volume control.\n\n"];
    [r appendString:[self controlDisplayVolumeDiagnostics]];
    [r appendString:@"\n"];

    [r appendString:@"## Stay ahead of other apps\n"];
    [r appendString:@"# When on, Volume Control reconnects to the keyboard whenever another app\n"];
    [r appendString:@"# that can block system keys is listed before it. Re-creations a few seconds\n"];
    [r appendString:@"# apart mean the other app moves itself back in front as well.\n\n"];
    [r appendString:[self stayAheadDiagnostics]];
    [r appendString:@"\n"];

    [r appendString:@"## Players targeted by the volume keys\n"];
    [r appendString:@"# \"targeted\" = ticked in the Volume Control menu. The keys act on the first\n"];
    [r appendString:@"# targeted player that is playing; if none is, they act on System.\n\n"];
    [r appendString:[self playerTargetingDiagnostics]];
    [r appendString:@"\n"];

    [r appendString:@"## Settings\n\n"];
    [r appendString:[self settingsDiagnostics]];
    [r appendString:@"\n"];

    [r appendString:@"## Last volume key press\n"];
    [r appendString:@"# To check the Command key: press Command + volume up, then create this report.\n\n"];
    [r appendString:[self lastKeyPressDiagnostics]];
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
		else
		{
			// The System check mark only shows whether the output device has a
			// software volume control (see -setSystemVolume:). It must not decide
			// the target: without it, a key pressed while no player plays found no
			// target and was dropped instead of being passed on to macOS.
			currentPlayer = systemAudio;
		}
	}
	else
		currentPlayer = systemAudio;

	// A display whose volume BetterDisplay controls takes the place of the
	// system volume, which Volume Control cannot change on such a display.
	if (currentPlayer == systemAudio) {
		DisplayVolumeTarget *display = [self displayVolumeTarget];
		if (display)
			currentPlayer = display;
	}

	return currentPlayer;
}

- (void)setVolumeUp:(bool)increase
{
	id runningPlayerPtr = [self runningPlayer];

	// A display's volume is read from BetterDisplay before each key press, as
	// a player's is; the answer arrives asynchronously, so step in its
	// completion. During a ramp no read happens: the step starts from the
	// value just set, as for players. No answer: ignore the key press.
	if ([runningPlayerPtr isKindOfClass:[DisplayVolumeTarget class]] &&
	    self->volumeRampTimer == nil && !_displayVolumeJustRead) {
		[(DisplayVolumeTarget *)runningPlayerPtr refreshVolume:^(BOOL ok) {
			if (!ok)
				return;
			self->_displayVolumeJustRead = YES;
			[self setVolumeUp:increase];
			self->_displayVolumeJustRead = NO;
		}];
		return;
	}

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

        // A timed-out read returns 0, not the player's volume. Stepping from
        // it would send the player 0 + increment once it answers again, so
        // ignore the key press. During a ramp no read happens, and the flag
        // still holds the result of the read made by the initial key press.
        if ([runningPlayerPtr isKindOfClass:[PlayerApplication class]] &&
            [(PlayerApplication *)runningPlayerPtr volumeReadTimedOut])
            return;

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

// The System line in the menu when the output device has no software volume
// control: the display's volume through BetterDisplay if available, else n/a.
- (DisplayVolumeTarget *)menuDisplayTarget
{
	if (![self ControlDisplayVolume] || !_displayTarget || ![_betterDisplay isRunning])
		return nil;
	NSString *uid = [systemAudio getDefaultOutputDeviceUID];
	return (uid && [uid isEqualToString:_displayTargetDeviceUID]) ? _displayTarget : nil;
}

- (void)showUncontrollableSystemPercentage
{
	DisplayVolumeTarget *display = [self menuDisplayTarget];
	BOOL readable = display && display.lastReadOK;
	[[self systemBtn] setState:readable ? NSControlStateValueOn : NSControlStateValueOff];
	[[self systemPerc] setStringValue:readable ? [NSString stringWithFormat:@"(%d%%)", (int)round(display.currentVolume)] : @"(n/a)"];
}

// Reads the display's volume for the menu; the System line updates when
// BetterDisplay answers.
- (void)refreshMenuDisplayVolume
{
	DisplayVolumeTarget *display = [self menuDisplayTarget];
	if (!display || [systemAudio hasControllableVolume])
		return;
	[display refreshVolume:^(BOOL ok) {
		if (![self->systemAudio hasControllableVolume])
			[self showUncontrollableSystemPercentage];
	}];
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
		[self showUncontrollableSystemPercentage];
}

// Shows "(n/a)" in the player's menu field when its last volume read
// timed out. Returns YES if it did.
- (BOOL) showNotAvailableForPlayer:(PlayerApplication*)player inField:(NSTextField*)field
{
	if (![player volumeReadTimedOut])
		return NO;
	[field setHidden:NO];
	[field setStringValue:@"(n/a)"];
	return YES;
}

- (void) updatePercentages
{
	if([iTunes isRunning]) {
		double volume = [iTunes currentVolume];
		if (![self showNotAvailableForPlayer:iTunes inField:[self iTunesPerc]])
			[self setItunesVolume:volume];
	} else
		[self setItunesVolume:-1];

	if([spotify isRunning]) {
		double volume = [spotify currentVolume];
		if (![self showNotAvailableForPlayer:spotify inField:[self spotifyPerc]])
			[self setSpotifyVolume:volume];
	} else
		[self setSpotifyVolume:-1];

	if ([doppler isRunning]) {
		double volume = [doppler currentVolume];
		if (![self showNotAvailableForPlayer:doppler inField:[self dopplerPerc]])
			[self setDopplerVolume:volume];
	} else
		[self setDopplerVolume:-1];

	if ([swinsian isRunning]) {
		double volume = [swinsian currentVolume];
		if (![self showNotAvailableForPlayer:swinsian inField:[self swinsianPerc]])
			[self setSwinsianVolume:volume];
	} else
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
	[self updateControlDisplayVolumeMenuItem];
	[self refreshMenuDisplayVolume];

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
