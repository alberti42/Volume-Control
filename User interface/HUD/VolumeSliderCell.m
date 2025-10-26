//
//  CustomVolumeSlider.m
//  Volume Control
//
//  Created by Andrea Alberti on 25.10.25.
//

#import "VolumeSliderCell.h"
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>

@implementation VolumeSliderCell
- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped {
    // This rect is the area for the bar. We'll make it 4pt tall and centered.
    rect = NSInsetRect(rect, 0, (NSHeight(rect) - 4.0) / 2.0);

    // 1. Draw the background "track"
    [[NSColor colorWithWhite:1.0 alpha:0.25] setFill];
    NSBezierPath *backgroundPath = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:2 yRadius:2];
    [backgroundPath fill];

    // 2. Calculate the width of the "filled" portion
    CGFloat percentage = (self.doubleValue - self.minValue) / (self.maxValue - self.minValue);
    NSRect fillRect = rect;
    fillRect.size.width = round(NSWidth(rect) * percentage);

    // 3. Draw the active "fill" portion
    [[NSColor colorWithWhite:1.0 alpha:0.85] setFill];
    NSBezierPath *fillPath = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:2 yRadius:2];
    [fillPath fill];
}

- (void)drawKnob:(NSRect)knobRect {
    if (self.isHovered) {
        /*
        CGFloat d = 12;
        knobRect = NSMakeRect(NSMidX(knobRect)-d/2.0, NSMidY(knobRect)-d/2.0, d, d);
        [[NSColor whiteColor] setFill];
        NSBezierPath *circle = [NSBezierPath bezierPathWithRoundedRect:knobRect xRadius:d/2 yRadius:d/2];
        [circle fill];
        */
        [super drawKnob:knobRect]; // Draws Apple's standard system knob
    }
}
@end
