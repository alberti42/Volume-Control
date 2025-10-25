//
//  CustomVolumeSlider.h
//  Volume Control
//
//  Created by Andrea Alberti on 25.10.25.
//

#import <AppKit/NSSliderCell.h>

@interface CustomVolumeSlider : NSSliderCell

// Add a property to track the hover state
@property (nonatomic, assign) BOOL isHovered;

@end
