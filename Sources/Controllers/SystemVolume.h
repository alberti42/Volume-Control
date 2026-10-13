//
//  AppDelegate.m
//  iTunes Volume Control
//
//  Created by Andrea Alberti on 25.12.12.
//  Copyright (c) 2012 Andrea Alberti. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <AudioToolbox/AudioServices.h>
#import "AppDelegate.h"

@interface SystemApplication : NSObject{
    
@private

}

-(id)init;
-(bool)isMuted;
-(bool)hasControllableVolume;
-(NSString *)getDefaultOutputDeviceName;
// Unique ID of the default output device (kAudioDevicePropertyDeviceUID), or
// nil. For a display's audio device, macOS builds it from the display's EDID.
-(NSString *)getDefaultOutputDeviceUID;

// Builds a human-readable, self-documenting report of every audio output device
// and the volume controls it exposes (master / per-channel / mute). Used by the
// "Copy Diagnostics" menu item. Reports the raw device capabilities and is not
// affected by the FAKE_* debug switches.
+ (NSString *)outputDevicesDiagnostics;
    
@property (assign, nonatomic) double currentVolume;  // The sound output volume (0 = minimum, 100 = maximum)
@property (assign, nonatomic) double oldVolume;
@property (assign, nonatomic) NSImage* icon;

@end
