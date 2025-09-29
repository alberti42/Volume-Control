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

-(AudioDeviceID) getDefaultOutputDevice
{
	AudioObjectPropertyAddress getDefaultOutputDevicePropertyAddress = {
		kAudioHardwarePropertyDefaultOutputDevice,
		kAudioObjectPropertyScopeGlobal,
		kAudioObjectPropertyElementMain
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

- (void)setCurrentVolume:(double)currentVolume
{
	AudioDeviceID defaultOutputDeviceID = [self getDefaultOutputDevice];

	AudioObjectPropertyAddress volumePropertyAddress = {
		kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
		kAudioDevicePropertyScopeOutput,
		kAudioObjectPropertyElementMain
	};

	AudioObjectPropertyAddress mutePropertyAddress = {
		kAudioDevicePropertyMute,
		kAudioDevicePropertyScopeOutput,
		kAudioObjectPropertyElementMain
	};

	Float32 volume = (Float32)(currentVolume / 100.);
	UInt32 dataSize;

	if (volume == 0) {
		// Mute the device
		UInt32 mute = 1;
		dataSize = sizeof(mute);
		OSStatus result = AudioObjectSetPropertyData(defaultOutputDeviceID,
													 &mutePropertyAddress,
													 0, NULL,
													 dataSize, &mute);
		if (result != noErr) {
			NSLog(@"Failed to mute device 0x%0x", defaultOutputDeviceID);
		}
	} else {
		// Unmute the device
		UInt32 mute = 0;
		dataSize = sizeof(mute);
		AudioObjectSetPropertyData(defaultOutputDeviceID,
								   &mutePropertyAddress,
								   0, NULL,
								   dataSize, &mute);

		// Set the volume
		dataSize = sizeof(volume);
		OSStatus result = AudioObjectSetPropertyData(defaultOutputDeviceID,
													 &volumePropertyAddress,
													 0, NULL,
													 dataSize, &volume);
		if (result != noErr) {
			NSLog(@"Failed to set volume for device 0x%0x", defaultOutputDeviceID);
		}
	}
}

- (bool) isMuted
{
	AudioDeviceID defaultOutputDeviceID = [self getDefaultOutputDevice];

	AudioObjectPropertyAddress volumePropertyAddress = {
		kAudioDevicePropertyMute,
		kAudioDevicePropertyScopeOutput,
		kAudioObjectPropertyElementMain
	};

	UInt32 muteVal;
	UInt32 muteValSize = sizeof(muteVal);
	OSStatus result = AudioObjectGetPropertyData(defaultOutputDeviceID,
										&volumePropertyAddress,
										0, NULL,
										&muteValSize, &muteVal);

	if (result != kAudioHardwareNoError) {
		NSLog(@"No volume reported for device 0x%0x", defaultOutputDeviceID);
	}

	return muteVal;
}

- (double) currentVolume
{
	AudioDeviceID defaultOutputDeviceID = [self getDefaultOutputDevice];

	// First, check mute state
	AudioObjectPropertyAddress mutePropertyAddress = {
		kAudioDevicePropertyMute,
		kAudioDevicePropertyScopeOutput,
		kAudioObjectPropertyElementMain
	};

	UInt32 muteVal = 0;
	UInt32 muteValSize = sizeof(muteVal);
	OSStatus muteResult = AudioObjectGetPropertyData(defaultOutputDeviceID,
													 &mutePropertyAddress,
													 0, NULL,
													 &muteValSize, &muteVal);

	if (muteResult == kAudioHardwareNoError && muteVal == 1) {
		return 0.0; // Treat mute as 0%
	}

	// Otherwise, get the real volume
	AudioObjectPropertyAddress volumePropertyAddress = {
		kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
		kAudioDevicePropertyScopeOutput,
		kAudioObjectPropertyElementMain
	};

	Float32 volume = 0;
	UInt32 volumedataSize = sizeof(volume);
	OSStatus result = AudioObjectGetPropertyData(defaultOutputDeviceID,
												 &volumePropertyAddress,
												 0, NULL,
												 &volumedataSize, &volume);

	if (result != kAudioHardwareNoError) {
		NSLog(@"No volume reported for device 0x%0x", defaultOutputDeviceID);
	}

	return ((double)volume) * 100.0;
}


-(void)dealloc
{
}

-(id)init{
	if (self = [super init])  {
		[self setOldVolume:[self currentVolume]];
	}
	return self;
}

@end
