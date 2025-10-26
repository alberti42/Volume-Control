//
//  HoverSlider.h
//  Volume Control
//
//  Created by Andrea Alberti on 26.10.25.
//

#import <Cocoa/Cocoa.h>

@class HoverSlider;

NS_ASSUME_NONNULL_BEGIN

// 1. Define a delegate protocol to communicate value changes.
@protocol HoverSliderDelegate <NSObject>
- (void)hoverSlider:(HoverSlider *)slider didChangeValue:(double)value;
- (void)hoverSliderDidEndDragging:(HoverSlider *)slider;
@end

/**
 An NSSlider subclass that detects mouse hover events and manually handles dragging
 to ensure it works within a non-activating panel.
 */
@interface HoverSlider : NSSlider

// 2. Add a delegate property.
@property (nonatomic, weak) id<HoverSliderDelegate> trackingDelegate;

@end

NS_ASSUME_NONNULL_END
