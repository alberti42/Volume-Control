//
//  AppDelegate.h
//  iTunes Volume Control
//
//  Created by Andrea Alberti on 25.12.12.
//  Copyright (c) 2012 Andrea Alberti. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <QuartzCore/CoreAnimation.h>

#import "iTunes.h"
// #import "Music.h"
#import "Spotify.h"
// #import "AppleRemote.h"

//#define OWN_WINDOW

@class IntroWindowController, AccessibilityDialog, StatusBarItem, PlayerApplication, SystemApplication;

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    CALayer *mainLayer;
    CALayer *volumeImageLayer;
    CALayer *iconLayer;
    CALayer *volumeBar[16];
    
    NSImage *imgVolOn,*imgVolOff;
    NSImage *iTunesIcon,*spotifyIcon;
    
    NSUserDefaults *preferences;
    
    CABasicAnimation *fadeOutAnimation;
    CABasicAnimation *fadeInAnimation;
    
    CFMachPortRef eventTap;
    CFRunLoopSourceRef runLoopSource;

    // AppleRemote* remote;
    
    NSInteger oldVolumeSetting;
    
    NSInteger osxVersion;
    
    double increment;
    
    Class OSDManager;
    
@public
    PlayerApplication* iTunes;
    PlayerApplication* spotify;
    SystemApplication* systemAudio;
    
    IntroWindowController *introWindowController;
    AccessibilityDialog *accessibilityDialog;
    
    NSTimer* timer;
    NSTimer* timerImgSpeaker;
    NSTimeInterval waitOverlayPanel;
    bool fadeInAnimationReady;
}

@property (nonatomic, assign) IBOutlet NSWindow* volumeWindow;
@property (nonatomic, assign) IBOutlet NSMenu* statusMenu;
@property (nonatomic, assign) IBOutlet NSSliderCell* volumeIncrementsSlider;

@property (nonatomic, assign) IBOutlet NSButton* iTunesBtn;
@property (nonatomic, assign) IBOutlet NSButton* spotifyBtn;
@property (nonatomic, assign) IBOutlet NSButton* systemBtn;

@property (nonatomic, assign) IBOutlet NSTextField* iTunesPerc;
@property (nonatomic, assign) IBOutlet NSTextField* spotifyPerc;
@property (nonatomic, assign) IBOutlet NSTextField* systemPerc;

@property (nonatomic, readonly, strong) NSStatusItem* statusBar;

@property (assign, nonatomic) NSInteger volumeInc;
@property (assign, nonatomic) bool AppleRemoteConnected;
@property (assign, nonatomic) bool StartAtLogin;
@property (assign, nonatomic) bool PlaySoundFeedback;
@property (assign, nonatomic) bool Tapping;
@property (assign, nonatomic) bool UseAppleCMDModifier;
@property (assign, nonatomic) bool AppleCMDModifierPressed;
@property (assign, nonatomic) bool AutomaticUpdates;
@property (assign, nonatomic) bool hideFromStatusBar;
@property (assign, nonatomic) bool hideVolumeWindow;
@property (assign, nonatomic) bool loadIntroAtStart;

- (IBAction)toggleUseAppleCMDModifier:(id)sender;
- (IBAction)toggleAutomaticUpdates:(id)sender;
- (IBAction)toggleHideFromStatusBar:(id)sender;
- (IBAction)toggleHideVolumeWindow:(id)sender;
- (IBAction)toggleStartAtLogin:(id)sender;
- (IBAction)togglePlaySoundFeedback:(id)sender;
- (IBAction)toggleTapping:(id)sender;
- (IBAction)aboutPanel:(id)sender;
- (IBAction)sliderValueChanged:(NSSliderCell*)slider;
//- (IBAction)showIntroWindow:(id)sender;
- (IBAction)terminate:(id)sender;

// - (void)appleRemoteButton: (AppleRemoteEventIdentifier)buttonIdentifier pressedDown: (BOOL) pressedDown clickCount: (unsigned int) count;

- (void)resetEventTap;

- (void) hideSpeakerImg:(NSTimer*)theTimer;

- (void)stopTimer;

- (void)updatePercentages;

- (void)wasAuthorized;

- (bool)createEventTap;

@end

@interface PlayerApplication : NSObject {
    id musicPlayer;
}

- (BOOL) isRunning;
- (iTunesEPlS) playerState;

@property (assign, nonatomic) double currentVolume;
@property (assign, nonatomic) double oldVolume;
@property (assign, nonatomic) double doubleVolume;


@end
