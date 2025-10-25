//
//  HoverSlider.h
//  Volume Control
//
//  Created by Andrea Alberti on 26.10.25.
//


#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An NSSlider subclass that detects mouse hover events (mouseEntered:/mouseExited:)
 and communicates the hover state to its CustomVolumeSlider cell.
 */
@interface HoverSlider : NSSlider

@end

NS_ASSUME_NONNULL_END
