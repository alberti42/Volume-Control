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
    
    NSInteger osxVersion;
}

-(id)initWithVersion:(NSInteger)osxVersion;
-(bool)isMuted;
    
@property (assign, nonatomic) double currentVolume;  // The sound output volume (0 = minimum, 100 = maximum)
@property (assign, nonatomic) double oldVolume;

@end
