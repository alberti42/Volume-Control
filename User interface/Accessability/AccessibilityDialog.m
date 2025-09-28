//
//  AccessibilityDialog.m
//  iTunes Volume Control
//
//  Created by Andrea Alberti on 09.06.19.
//  Copyright © 2019 Andrea Alberti. All rights reserved.
//

#import "AccessibilityDialog.h"
#import "AppDelegate.h"

@interface AccessibilityDialog ()
@end

@implementation AccessibilityDialog

@synthesize openSecurityPrivacyBtn;
@synthesize exitBtn;
@synthesize restartBtn;
@synthesize screenshot;

- (IBAction)onExitButton:(id)sender
{
    [NSApp terminate:nil];
}

- (IBAction)onOpenSecurityPrivacy:(id)sender
{
    NSString *urlString = @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility";
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlString]];
}

- (IBAction)onRestart:(id)sender
{
    //$N = argv[N]
    NSString *killArg1AndOpenArg2Script = @"kill -15 $1 \n open \"$2\"";
    
    //NSTask needs its arguments to be strings
    NSString *ourPID = [NSString stringWithFormat:@"%d",
                        [[NSProcessInfo processInfo] processIdentifier]];
    
    //this will be the path to the .app bundle,
    //not the executable inside it; exactly what `open` wants
    NSString * pathToUs = [[NSBundle mainBundle] bundlePath];
    
    NSArray *shArgs = [NSArray arrayWithObjects:@"-c", // -c tells sh to execute the next argument, passing it the remaining arguments.
                       killArg1AndOpenArg2Script,
                       @"", //$0 path to script (ignored)
                       ourPID, //$1 in restartScript
                       pathToUs, //$2 in the restartScript
                       nil];
    NSTask *restartTask = [NSTask launchedTaskWithLaunchPath:@"/bin/sh" arguments:shArgs];
    [restartTask waitUntilExit]; //wait for killArg1AndOpenArg2Script to finish
    NSLog(@"*** ERROR: %@ should have been terminated, but we are still running", pathToUs);
    assert(!"We should not be running!");
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    
    [openSecurityPrivacyBtn setBezelStyle:NSBezelStyleRounded];
    [exitBtn setBezelStyle:NSBezelStyleRounded];
    [restartBtn setBezelStyle:NSBezelStyleRounded];
    
    [[self window] setDefaultButtonCell:[openSecurityPrivacyBtn cell]];
    [self window].styleMask &= ~NSWindowStyleMaskResizable;
}

- (void)checkAuthorization:(NSTimer*)aTimer
{
    extern CFStringRef kAXTrustedCheckOptionPrompt __attribute__((weak_import));
    
    if ( AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge id)kAXTrustedCheckOptionPrompt: @NO}) && [(AppDelegate*)[NSApp delegate] createEventTap] )
    {
        [aTimer invalidate];
        aTimer = nil;
        
        [(AppDelegate*)[NSApp delegate] wasAuthorized];
    }
}

- (IBAction)showWindow:(id)sender
{
    [super showWindow:sender];
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [[self window] makeKeyAndOrderFront:sender];
    
    checkAuthorizationTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(checkAuthorization:) userInfo:nil repeats:YES];
}

-(void)dealloc
{
    exitBtn = nil;
    openSecurityPrivacyBtn = nil;
    restartBtn = nil;
}

-(id) init
{
    if (self = [super init])  {
        self->authorized = false;
    }
    return self;
}

@end

@implementation ScreenshotView

- (void)awakeFromNib {
    [super awakeFromNib];
//    [self ignorem]
    //    self.ignoresMouseEvents = YES; // allow clicks to pass through
    [self setAppropriateImage];
}

- (void) setAppropriateImage
{
    bool isDark = [[[NSApp effectiveAppearance] name] isEqualToString:@"NSAppearanceNameDarkAqua"];
    
    if(isDark)
        screenshotImage = [NSImage imageNamed:@"SecurityPrivacyDark"];
    else
        screenshotImage = [NSImage imageNamed:@"SecurityPrivacyLight"];
    
    [self setImage:screenshotImage];
    
    [self setNeedsDisplay:YES];
}

- (void) viewDidChangeEffectiveAppearance
{
    [self setAppropriateImage];
}

@end
