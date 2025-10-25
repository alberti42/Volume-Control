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

    // Extract key info
    int keyFlags   = ([sysEvent data1] & 0x0000FFFF);
    int keyCode    = (([sysEvent data1] & 0xFFFF0000) >> 16);
    int keyState   = (((keyFlags & 0xFF00) >> 8)) == 0xA;
    bool keyIsRepeat = (keyFlags & 0x1);
    CGEventFlags keyModifier = [sysEvent modifierFlags] | 0xFFFF;

    // Decide here if it's a volume/mute event
    BOOL isMediaKey = (keyCode == NX_KEYTYPE_MUTE ||
                       //keyCode == NX_KEYTYPE_SOUND_UP ||
                       keyCode == NX_KEYTYPE_SOUND_DOWN);
    
    if(isMediaKey) {
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
- (void) setItunesVolume:(NSInteger)volume;
- (void) setSpotifyVolume:(NSInteger)volume;
- (void) setSystemVolume:(NSInteger)volume;
- (void)stopVolumeRampTimer;
- (void)updatePercentages;
- (bool)createEventTap;
- (void)handleEventTapDisabledByUser;

@end

#pragma mark - Extention music applications

@implementation PlayerApplication

@synthesize currentVolume = _currentVolume;
@synthesize icon = _icon;

- (void) setCurrentVolume:(double)currentVolume
{
	[self setDoubleVolume:currentVolume];

	[musicPlayer setSoundVolume:round(currentVolume)];
}

- (double) currentVolume
{
    double vol = [musicPlayer soundVolume];

    if (fabs(vol-[self doubleVolume])<1)
	{
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
	return [musicPlayer playerState];
}

-(id)initWithBundleIdentifier:(NSString*) bundleIdentifier andIcon:(NSImage*)icon {
	if (self = [super init])  {
		[self setCurrentVolume: -100];
		[self setOldVolume: -1];
		musicPlayer = [SBApplication applicationWithBundleIdentifier:bundleIdentifier];
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

@synthesize iTunesPerc = _iTunesPerc;
@synthesize spotifyPerc = _spotifyPerc;
@synthesize systemPerc = _systemPerc;
@synthesize dopplerPerc = _dopplerPerc;

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
                    [[TahoeVolumeHUD sharedManager] showHUDWithVolume:0 usingIcon:[runningPlayerPtr icon] anchoredToStatusButton:self.statusBar.button];
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
                    [[TahoeVolumeHUD sharedManager] showHUDWithVolume:[runningPlayerPtr oldVolume] usingIcon:[runningPlayerPtr icon] anchoredToStatusButton:self.statusBar.button];
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
			[self setSpotifyVolume:[runningPlayerPtr currentVolume]];

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

    iTunes = [[PlayerApplication alloc] initWithBundleIdentifier:@"com.apple.iTunes" andIcon:[NSImage imageNamed:@"iTunes"]];
	
    spotify = [[PlayerApplication alloc] initWithBundleIdentifier:@"com.spotify.client" andIcon:[NSImage imageNamed:@"spotify"]];

    doppler = [[PlayerApplication alloc] initWithBundleIdentifier:@"co.brushedtype.doppler-macos" andIcon:[NSImage imageNamed:@"doppler"]];

	// Force MacOS to ask for authorization to AppleEvents if this was not already given
	if([iTunes isRunning])
		[iTunes currentVolume];
	if([spotify isRunning])
		[spotify currentVolume];
	if([doppler isRunning])
		[doppler currentVolume];

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
	if([systemAudio isMuted])
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
						  [NSNumber numberWithBool:true],  @"systemControl",
						  [NSNumber numberWithBool:true],  @"PlaySoundFeedback",
						  nil ]; // terminate the list
	[preferences registerDefaults:dict];
    
	[self setTapping:[preferences boolForKey:              @"TappingEnabled"]];
	[self setUseAppleCMDModifier:[preferences boolForKey:  @"UseAppleCMDModifier"]];
	[self setLockSystemAndPlayerVolume:[preferences boolForKey:  @"LockSystemAndPlayerVolume"]];
	[self setAutomaticUpdates:[preferences boolForKey:     @"AutomaticUpdates"]];
	[self setHideFromStatusBar:[preferences boolForKey:    @"hideFromStatusBarPreference"]];
    if (@available(macOS 16.0, *)) {
        // Running on Tahoe (2026) or newer
        NSMenuItem *item = [self.statusMenu itemWithTag:HIDE_VOLUME_WINDOW_ID];
        [item setHidden:YES];
    } else {
        [self setHideVolumeWindow:[preferences boolForKey:     @"hideVolumeWindowPreference"]];
    }
	[[self iTunesBtn] setState:[preferences boolForKey:    @"iTunesControl"]];
	if (@available(macOS 10.15, *)) {
		[[self iTunesBtn] setTitle:@"Music"];
	}
	[[self iTunesBtn] setState:[preferences boolForKey:    @"iTunesControl"]];
	[[self spotifyBtn] setState:[preferences boolForKey:   @"spotifyControl"]];
	[[self dopplerBtn] setState:[preferences boolForKey:   @"dopplerControl"]];
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
		double volume = [runningPlayerPtr currentVolume];
		// NSLog(@"Current volume: %1.2f%%", volume);

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
            // Running on Tahoe (2026) or newer
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
                [[TahoeVolumeHUD sharedManager] showHUDWithVolume:volume usingIcon:[runningPlayerPtr icon] anchoredToStatusButton:self.statusBar.button];
            } else {
                if(image) {
                    id osdMgr = [self->OSDManager sharedManager];
                    if (osdMgr) {
                        [osdMgr showImage:image onDisplayID:CGSMainDisplayID() priority:OSDPriorityDefault msecUntilFade:1000 filledChiclets:(unsigned int)(round(((numFullBlks*4+numQrtsBlks)*1.5625)*100)) totalChiclets:(unsigned int)10000 locked:NO];
                    }
                }
            }
        }

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

		if(_LockSystemAndPlayerVolume || runningPlayerPtr == systemAudio)
			[self setSystemVolume:volume];

		[self refreshVolumeBar:(int)volume];

		// NSLog(@"New volume: %1.2f%%", [runningPlayerPtr currentVolume]);
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

- (void) setSystemVolume:(NSInteger)volume
{
	if (volume == -1)
		[[self systemPerc] setHidden:YES];
	else
	{
		[[self systemPerc] setHidden:NO];
		[[self systemPerc] setStringValue:[NSString stringWithFormat:@"(%d%%)",(int)volume]];
	}

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
		// self.statusBar.length = 0; // collapses to zero width, however, some space remains allocated by macOS
	}
}

- (void)showStatusBarItem {
	if (self.statusBar) {
		self.statusBar.visible = YES;
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

#pragma mark - Sparkle Delegates

// This is the Objective-C equivalent of the Swift property 'supportsGentleScheduledUpdateReminders'
// This is the correct way to opt-in and remove the warning.
- (BOOL)supportsGentleScheduledUpdateReminders {
	return YES;
}

@end
