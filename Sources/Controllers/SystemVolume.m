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

// Debug aid: set to 1 to force -hasControllableVolume to always report NO, so
// the "no output controls" handling can be exercised on hardware that actually
// supports software volume control (e.g. the built-in speakers). This simulates
// the behavior of digital outputs such as HDMI/DisplayPort displays that expose
// no controllable volume. MUST be 0 in shipping builds.
#define FAKE_NO_CONTROLLABLE_VOLUME 0

// Debug aid: set to 1 to force the master-volume check to report NO, so the
// per-channel kAudioDevicePropertyVolumeScalar fallback is exercised instead of
// the master path.
//
// To actually reach (and control the volume through) this fallback you must test
// with an output device that offers per-channel volume controls, such as Apple
// AirPods. The Apple MacBook built-in speakers only expose a master control and
// no per-channel controls, so disabling the master here leaves no way to control
// their volume: hasControllableVolume then correctly reports NO and the code
// takes the "no output controls" path instead of the per-channel fallback.
//
// MUST be 0 in shipping builds.
#define FAKE_NO_MASTER_VOLUME 0

@interface SystemApplication ()
// YES if the device exposes a single master output volume element (subject to
// the FAKE_NO_MASTER_VOLUME override).
- (BOOL)hasMasterVolumeForDevice:(AudioDeviceID)deviceID;
// Fills channels[0]/channels[1] with the device's preferred stereo output
// channel numbers. Returns YES on success. channels must point to 2 UInt32s.
- (BOOL)getStereoOutputChannels:(UInt32 *)channels forDevice:(AudioDeviceID)deviceID;
@end

@implementation SystemApplication

@synthesize currentVolume = _currentVolume;
@synthesize icon = _icon;

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

- (BOOL)hasMasterVolumeForDevice:(AudioDeviceID)deviceID
{
#if FAKE_NO_MASTER_VOLUME
	return NO;
#else
	AudioObjectPropertyAddress masterVolumeAddress = {
		kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
		kAudioDevicePropertyScopeOutput,
		kAudioObjectPropertyElementMain
	};

	return AudioObjectHasProperty(deviceID, &masterVolumeAddress) ? YES : NO;
#endif
}

- (BOOL)getStereoOutputChannels:(UInt32 *)channels forDevice:(AudioDeviceID)deviceID
{
	AudioObjectPropertyAddress stereoChannelsAddress = {
		kAudioDevicePropertyPreferredChannelsForStereo,
		kAudioDevicePropertyScopeOutput,
		kAudioObjectPropertyElementMain
	};

	UInt32 dataSize = sizeof(UInt32) * 2;
	OSStatus result = AudioObjectGetPropertyData(deviceID,
												 &stereoChannelsAddress,
												 0, NULL,
												 &dataSize, channels);

	return result == kAudioHardwareNoError;
}

- (void)setCurrentVolume:(double)currentVolume
{
	AudioDeviceID defaultOutputDeviceID = [self getDefaultOutputDevice];

	AudioObjectPropertyAddress mutePropertyAddress = {
		kAudioDevicePropertyMute,
		kAudioDevicePropertyScopeOutput,
		kAudioObjectPropertyElementMain
	};

	Float32 volume = (Float32)(currentVolume / 100.);
	UInt32 dataSize;

	// Raising the volume above 0 should also clear any active mute, matching
	// the behavior of the native macOS volume keys. We intentionally do NOT set
	// the mute flag when the level reaches 0: a scalar of 0 already produces
	// silence, and muting here would conflate "user lowered the volume to 0%"
	// with an explicit device mute (handled separately via the mute key). On
	// hardware that keeps mute and scalar independent, forcing a mute at 0%
	// could otherwise leave the device stuck muted after the volume is raised
	// again.
	if (volume > 0) {
		// Clear the mute flag in case the device was previously muted, so that
		// raising the volume actually produces sound again.
		UInt32 mute = 0;
		dataSize = sizeof(mute);
		AudioObjectSetPropertyData(defaultOutputDeviceID,
								   &mutePropertyAddress,
								   0, NULL,
								   dataSize, &mute);
	}

	dataSize = sizeof(volume);

	if ([self hasMasterVolumeForDevice:defaultOutputDeviceID]) {
		// Preferred path: set the single master volume element.
		AudioObjectPropertyAddress masterVolumeAddress = {
			kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
			kAudioDevicePropertyScopeOutput,
			kAudioObjectPropertyElementMain
		};

		OSStatus result = AudioObjectSetPropertyData(defaultOutputDeviceID,
													 &masterVolumeAddress,
													 0, NULL,
													 dataSize, &volume);
		if (result != noErr) {
			NSLog(@"Failed to set master volume for device 0x%0x", defaultOutputDeviceID);
		}
	} else {
		// Fallback: the device has no master element, so set each output
		// channel's volume individually (as macOS itself does).
		UInt32 channels[2];
		if ([self getStereoOutputChannels:channels forDevice:defaultOutputDeviceID]) {
			for (int i = 0; i < 2; i++) {
				AudioObjectPropertyAddress channelVolumeAddress = {
					kAudioDevicePropertyVolumeScalar,
					kAudioDevicePropertyScopeOutput,
					channels[i]
				};

				if (!AudioObjectHasProperty(defaultOutputDeviceID, &channelVolumeAddress)) {
					continue;
				}

				OSStatus result = AudioObjectSetPropertyData(defaultOutputDeviceID,
															 &channelVolumeAddress,
															 0, NULL,
															 dataSize, &volume);
				if (result != noErr) {
					NSLog(@"Failed to set volume for channel %u of device 0x%0x", channels[i], defaultOutputDeviceID);
				}
			}
		} else {
			NSLog(@"No controllable volume (master or per-channel) for device 0x%0x", defaultOutputDeviceID);
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

// Reports whether the current default output device exposes a software-
// controllable volume. Digital outputs such as HDMI/DisplayPort displays often
// do not implement a master volume element, in which case macOS itself cannot
// change their volume and neither can we. Callers use this to present an honest
// "no output controls" state instead of a misleading 0%.
- (bool)hasControllableVolume
{
#if FAKE_NO_CONTROLLABLE_VOLUME
	return NO;
#else
	AudioDeviceID defaultOutputDeviceID = [self getDefaultOutputDevice];

	if (defaultOutputDeviceID == kAudioObjectUnknown) {
		return NO;
	}

	// Controllable if the device has a master volume element ...
	if ([self hasMasterVolumeForDevice:defaultOutputDeviceID]) {
		return YES;
	}

	// ... or at least one output channel exposes a per-channel volume scalar.
	UInt32 channels[2];
	if ([self getStereoOutputChannels:channels forDevice:defaultOutputDeviceID]) {
		for (int i = 0; i < 2; i++) {
			AudioObjectPropertyAddress channelVolumeAddress = {
				kAudioDevicePropertyVolumeScalar,
				kAudioDevicePropertyScopeOutput,
				channels[i]
			};

			if (AudioObjectHasProperty(defaultOutputDeviceID, &channelVolumeAddress)) {
				return YES;
			}
		}
	}

	return NO;
#endif
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

	Float32 volume = 0;

	if ([self hasMasterVolumeForDevice:defaultOutputDeviceID]) {
		// Preferred path: read the single master volume element.
		AudioObjectPropertyAddress masterVolumeAddress = {
			kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
			kAudioDevicePropertyScopeOutput,
			kAudioObjectPropertyElementMain
		};

		UInt32 volumedataSize = sizeof(volume);
		OSStatus result = AudioObjectGetPropertyData(defaultOutputDeviceID,
													 &masterVolumeAddress,
													 0, NULL,
													 &volumedataSize, &volume);

		if (result != kAudioHardwareNoError) {
			NSLog(@"No master volume reported for device 0x%0x", defaultOutputDeviceID);
		}
	} else {
		// Fallback: no master element, so average the per-channel volumes (as
		// macOS itself does when synthesizing a master level).
		UInt32 channels[2];
		if ([self getStereoOutputChannels:channels forDevice:defaultOutputDeviceID]) {
			Float32 sum = 0;
			int count = 0;
			for (int i = 0; i < 2; i++) {
				AudioObjectPropertyAddress channelVolumeAddress = {
					kAudioDevicePropertyVolumeScalar,
					kAudioDevicePropertyScopeOutput,
					channels[i]
				};

				if (!AudioObjectHasProperty(defaultOutputDeviceID, &channelVolumeAddress)) {
					continue;
				}

				Float32 channelVolume = 0;
				UInt32 volumedataSize = sizeof(channelVolume);
				if (AudioObjectGetPropertyData(defaultOutputDeviceID,
											   &channelVolumeAddress,
											   0, NULL,
											   &volumedataSize, &channelVolume) == kAudioHardwareNoError) {
					sum += channelVolume;
					count++;
				}
			}

			if (count > 0) {
				volume = sum / (Float32)count;
			}
		} else {
			NSLog(@"No volume reported for device 0x%0x", defaultOutputDeviceID);
		}
	}

	return ((double)volume) * 100.0;
}

- (NSString *)getDefaultOutputDeviceUID
{
    AudioDeviceID deviceID = [self getDefaultOutputDevice];
    if (deviceID == kAudioObjectUnknown)
        return nil;

    CFStringRef uid = NULL;
    UInt32 dataSize = sizeof(uid);
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyDeviceUID,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &dataSize, &uid) != kAudioHardwareNoError || uid == NULL)
        return nil;
    return (__bridge_transfer NSString *)uid;
}

- (NSString *)getDefaultOutputDeviceName
{
    AudioDeviceID defaultOutputDeviceID = [self getDefaultOutputDevice];
    
    if (defaultOutputDeviceID == kAudioObjectUnknown) {
        return @"Unknown Device";
    }
    
    CFStringRef deviceName = NULL;
    UInt32 dataSize = sizeof(deviceName);
    
    AudioObjectPropertyAddress propertyAddress = {
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    OSStatus result = AudioObjectGetPropertyData(defaultOutputDeviceID,
                                                 &propertyAddress,
                                                 0,
                                                 NULL,
                                                 &dataSize,
                                                 &deviceName);
    
    if (result != kAudioHardwareNoError || deviceName == NULL) {
        NSLog(@"Could not get device name for device 0x%0x", defaultOutputDeviceID);
        return @"Unknown Device";
    }
    
    NSString *name = [NSString stringWithString:(__bridge NSString *)deviceName];
    CFRelease(deviceName);
    return name;
}


#pragma mark - Diagnostics

// Raw, un-faked helpers used only by the diagnostics report. They deliberately
// query the hardware directly (no FAKE_* overrides) so the report reflects the
// device's real capabilities.

static NSString *VCDeviceName(AudioObjectID dev)
{
	CFStringRef name = NULL;
	UInt32 size = sizeof(name);
	AudioObjectPropertyAddress addr = {
		kAudioObjectPropertyName,
		kAudioObjectPropertyScopeGlobal,
		kAudioObjectPropertyElementMain
	};
	if (AudioObjectGetPropertyData(dev, &addr, 0, NULL, &size, &name) == noErr && name) {
		return (__bridge_transfer NSString *)name;
	}
	return @"(unknown)";
}

static UInt32 VCOutputChannelCount(AudioObjectID dev)
{
	AudioObjectPropertyAddress addr = {
		kAudioDevicePropertyStreamConfiguration,
		kAudioDevicePropertyScopeOutput,
		kAudioObjectPropertyElementMain
	};
	UInt32 size = 0;
	if (AudioObjectGetPropertyDataSize(dev, &addr, 0, NULL, &size) != noErr || size == 0) {
		return 0;
	}
	AudioBufferList *list = malloc(size);
	UInt32 count = 0;
	if (AudioObjectGetPropertyData(dev, &addr, 0, NULL, &size, list) == noErr) {
		for (UInt32 i = 0; i < list->mNumberBuffers; i++) {
			count += list->mBuffers[i].mNumberChannels;
		}
	}
	free(list);
	return count;
}

static BOOL VCHasOutputProperty(AudioObjectID dev, AudioObjectPropertySelector selector, UInt32 element)
{
	AudioObjectPropertyAddress addr = { selector, kAudioDevicePropertyScopeOutput, element };
	return AudioObjectHasProperty(dev, &addr) ? YES : NO;
}

static NSString *VCYesNo(BOOL value)
{
	return value ? @"yes" : @"no";
}

+ (NSString *)outputDevicesDiagnostics
{
	AudioObjectPropertyAddress devicesAddr = {
		kAudioHardwarePropertyDevices,
		kAudioObjectPropertyScopeGlobal,
		kAudioObjectPropertyElementMain
	};

	UInt32 size = 0;
	if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &devicesAddr, 0, NULL, &size) != noErr || size == 0) {
		return @"(could not enumerate audio devices)\n";
	}

	UInt32 count = size / sizeof(AudioObjectID);
	AudioObjectID *devices = malloc(size);
	if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &devicesAddr, 0, NULL, &size, devices) != noErr) {
		free(devices);
		return @"(could not enumerate audio devices)\n";
	}

	// Current default output device, to flag it in the listing.
	AudioObjectPropertyAddress defAddr = {
		kAudioHardwarePropertyDefaultOutputDevice,
		kAudioObjectPropertyScopeGlobal,
		kAudioObjectPropertyElementMain
	};
	AudioObjectID defaultDev = kAudioObjectUnknown;
	UInt32 defSize = sizeof(defaultDev);
	AudioObjectGetPropertyData(kAudioObjectSystemObject, &defAddr, 0, NULL, &defSize, &defaultDev);

	NSMutableString *out = [NSMutableString string];

	for (UInt32 i = 0; i < count; i++) {
		AudioObjectID dev = devices[i];
		if (VCOutputChannelCount(dev) == 0) {
			continue; // not an output device
		}

		BOOL master = VCHasOutputProperty(dev, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain);
		BOOL masterScalar = VCHasOutputProperty(dev, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain);
		BOOL mute = VCHasOutputProperty(dev, kAudioDevicePropertyMute, kAudioObjectPropertyElementMain);

		// Preferred stereo channels and whether each carries a volume scalar.
		BOOL leftCh = NO, rightCh = NO;
		AudioObjectPropertyAddress stereoAddr = {
			kAudioDevicePropertyPreferredChannelsForStereo,
			kAudioDevicePropertyScopeOutput,
			kAudioObjectPropertyElementMain
		};
		UInt32 channels[2] = {0, 0};
		UInt32 channelsSize = sizeof(channels);
		if (AudioObjectGetPropertyData(dev, &stereoAddr, 0, NULL, &channelsSize, channels) == noErr) {
			leftCh = VCHasOutputProperty(dev, kAudioDevicePropertyVolumeScalar, channels[0]);
			rightCh = VCHasOutputProperty(dev, kAudioDevicePropertyVolumeScalar, channels[1]);
		}

		BOOL controllable = master || leftCh || rightCh;

		[out appendFormat:@"%@%@\n", (dev == defaultDev) ? @"[DEFAULT] " : @"", VCDeviceName(dev)];
		[out appendFormat:@"  master VirtualMainVolume : %@\n", VCYesNo(master)];
		[out appendFormat:@"  master VolumeScalar      : %@\n", VCYesNo(masterScalar)];
		[out appendFormat:@"  per-channel L / R        : %@ / %@\n", VCYesNo(leftCh), VCYesNo(rightCh)];
		[out appendFormat:@"  mute                     : %@\n", VCYesNo(mute)];
		[out appendFormat:@"  -> Volume Control can control this device: %@\n\n", controllable ? @"YES" : @"NO"];
	}

	free(devices);
	return out;
}

-(void)dealloc
{
}

-(id)init{
	if (self = [super init])  {
		[self setOldVolume:[self currentVolume]];
        if (@available(macOS 16.0, *)) {
            [self setIcon:[NSImage imageNamed:@"FinderTahoe"]];
        } else {
            [self setIcon:[NSImage imageNamed:@"FinderSequoia"]];
        }
	}
	return self;
}

@end
