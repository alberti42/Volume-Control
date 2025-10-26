//
//  VolumeSlider.h
//  Volume Control
//
//  Created by Andrea Alberti on 26.10.25.
//

#import <Cocoa/Cocoa.h>

@class VolumeSlider;

NS_ASSUME_NONNULL_BEGIN

// 1. Define a delegate protocol to communicate value changes.
@protocol VolumeSliderDelegate <NSObject>
- (void)volumeSlider:(VolumeSlider *)slider didChangeValue:(double)value;
- (void)hoverSliderDidEndDragging:(VolumeSlider *)slider;
@end

/**
 An NSSlider subclass that detects mouse hover events and manually handles dragging
 to ensure it works within a non-activating panel.
 */
@interface VolumeSlider : NSSlider

// 2. Add a delegate property.
@property (nonatomic, weak) id<VolumeSliderDelegate> trackingDelegate;

@end

NS_ASSUME_NONNULL_END
