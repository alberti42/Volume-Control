//
//  AppDelegate.m
//  iTunes Volume Control
//
//  Created by Andrea Alberti on 25.12.12.
//  Copyright (c) 2012 Andrea Alberti. All rights reserved.
//

#import <Carbon/Carbon.h>
#import "AppDelegate.h"

#import "SystemVolume.h"

@implementation SystemApplication

@synthesize currentVolume = _currentVolume;

- (void) setCurrentVolume:(double)currentVolume
{
    AudioDeviceID defaultOutputDeviceID = [self getDefaultOutputDevice];
    
    AudioObjectPropertyAddress volumePropertyAddress = {
        kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMaster
    };
    
    Float32 volume = (Float32)(currentVolume/100.);
    UInt32 volumedataSize = sizeof(volume);
    
    OSStatus result = AudioObjectSetPropertyData(defaultOutputDeviceID,
                                        &volumePropertyAddress,
                                        0, NULL,
                                        volumedataSize, &volume);
    
    if (result != kAudioHardwareNoError) {
        NSLog(@"No volume set for device 0x%0x", defaultOutputDeviceID);
    }        
}

-(AudioDeviceID) getDefaultOutputDevice
{
    AudioObjectPropertyAddress getDefaultOutputDevicePropertyAddress = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMaster
    };
    
    AudioDeviceID defaultOutputDeviceID;
    UInt32 volumedataSize = sizeof(defaultOutputDeviceID);
    OSStatus result = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                                 &getDefaultOutputDevicePropertyAddress,
                                                 0, NULL,
                                                 &volumedataSize, &defaultOutputDeviceID);
    
    if(kAudioHardwareNoError != result)
    {
        NSLog(@"Cannot find default output device!");
    }
    
    return defaultOutputDeviceID;
}

- (double) currentVolume
{
    AudioDeviceID defaultOutputDeviceID = [self getDefaultOutputDevice];
    
    AudioObjectPropertyAddress volumePropertyAddress = {
        kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMaster
    };
    
    Float32 volume;
    UInt32 volumedataSize = sizeof(volume);
    OSStatus result = AudioObjectGetPropertyData(defaultOutputDeviceID,
                                        &volumePropertyAddress,
                                        0, NULL,
                                        &volumedataSize, &volume);
    
    if (result != kAudioHardwareNoError) {
        NSLog(@"No volume reported for device 0x%0x", defaultOutputDeviceID);
    }
    
    return ((double)volume)*100.;
}

-(void)dealloc
{
}

-(id)initWithVersion:(NSInteger)osxVersion{
    if (self = [super init])  {
        [self setOldVolume:[self currentVolume]];
        self->osxVersion = osxVersion;
    }
    return self;
}

@end
