//
//  OSD.h
//  NativeDisplayBrightness
//
//  Created by Benno Krauss on 23.10.16.
//  Copyright © 2016 Benno Krauss. All rights reserved.
//

#ifndef OSD_h
#define OSD_h

//#include "CoreGraphicsPriv.h"

CG_EXTERN CGDirectDisplayID CGSMainDisplayID(void);

typedef enum {
    OSDGraphicBacklight                              = 1,//0xfffffff7,
    OSDGraphicEject                                  = 6,
    OSDGraphicNoWiFi                                 = 9,
    OSDGraphicSpeaker                                = 23,
    OSDGraphicSpeakerMute                            = 4,
    //You can reverse these yourself if you need them, it's easy trial-and-error
    /*
     BSGraphicKeyboardBacklightMeter                 = //0xfffffff1,
     BSGraphicKeyboardBacklightDisabledMeter         = //0xfffffff0,
     BSGraphicKeyboardBacklightNotConnected          = //0xffffffef,
     BSGraphicKeyboardBacklightDisabledNotConnected  = //0xffffffee,
     BSGraphicMacProOpen                             = //0xffffffe9,
     BSGraphicSpeakerMuted                           = //0xffffffe8,
     BSGraphicSpeaker                                = //0xffffffe7,
     BSGraphicSpeakerDisabled                        = //0xffffffe7,
     BSGraphicRemoteBattery                          = //0xffffffe6,
     BSGraphicHotspot                                = //0xffffffe5,
     BSGraphicSleep                                  = //0xffffffe3,
     BSGraphicSpeaker                                = 3//0xffffffe2,
     BSGraphicNewRemoteBattery                       = //0xffffffcb,
     */
} OSDGraphic;

typedef enum {
    OSDPriorityDefault = 0x1f4
} OSDPriority;

//@interface OSDManager : NSObject
//+ (instancetype)sharedManager;
//- (void)showImage:(OSDGraphic)image onDisplayID:(CGDirectDisplayID)display priority:(OSDPriority)priority msecUntilFade:(int)timeout;
//- (void)showImage:(OSDGraphic)image onDisplayID:(CGDirectDisplayID)display priority:(OSDPriority)priority msecUntilFade:(int)timeout withText:(NSString *)text;
//- (void)showImage:(OSDGraphic)image onDisplayID:(CGDirectDisplayID)display priority:(OSDPriority)priority msecUntilFade:(int)timeout filledChiclets:(int)filled totalChiclets:(int)total locked:(BOOL)locked;
//@end

@protocol OSDUIHelperProtocol
+ (instancetype)sharedManager;
- (void)showFullScreenImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecToAnimate:(unsigned int)arg4;
- (void)fadeClassicImageOnDisplay:(unsigned int)arg1;
- (void)showImageAtPath:(NSString *)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4 withText:(NSString *)arg5;
- (void)showImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4 filledChiclets:(unsigned int)arg5 totalChiclets:(unsigned int)arg6 locked:(BOOL)arg7;
- (void)showImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4 withText:(NSString *)arg5;
- (void)showImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4;
@end

@interface OSDManager : NSObject <OSDUIHelperProtocol>
{
    id <OSDUIHelperProtocol> _proxyObject;
    NSXPCConnection *connection;
}

@property(retain) NSXPCConnection *connection; // @synthesize connection;
- (void)showFullScreenImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecToAnimate:(unsigned int)arg4;
- (void)fadeClassicImageOnDisplay:(unsigned int)arg1;
- (void)showImageAtPath:(id)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4 withText:(id)arg5;
- (void)showImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4 filledChiclets:(unsigned int)arg5 totalChiclets:(unsigned int)arg6 locked:(BOOL)arg7;
- (void)showImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4 withText:(id)arg5;
- (void)showImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4;
@property(readonly) id <OSDUIHelperProtocol> remoteObjectProxy; // @dynamic remoteObjectProxy;

@end


#endif /* OSD_h */
