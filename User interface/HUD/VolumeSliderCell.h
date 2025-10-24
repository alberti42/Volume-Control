//
//  CustomVolumeSlider.h
//  Volume Control
//
//  Created by Andrea Alberti on 25.10.25.
//

#import <AppKit/NSSliderCell.h>

@interface VolumeSliderCell : NSSliderCell

// This property will control whether the knob is visible.
@property (nonatomic, assign) BOOL isHovered;

@end
