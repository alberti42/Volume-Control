//
//  CustomVolumeSlider.m
//  Volume Control
//
//  Created by Andrea Alberti on 25.10.25.
//

#import "CustomVolumeSlider.h"
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>

@implementation CustomVolumeSlider
- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped {
    rect = NSInsetRect(rect, 0, (NSHeight(rect)-4)/2.0);
    [[NSColor colorWithWhite:1.0 alpha:0.25] setFill]; // background “track”
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:2 yRadius:2];
    [bg fill];

    CGFloat pct = (self.doubleValue - self.minValue) / (self.maxValue - self.minValue);
    NSRect fillRect = rect; fillRect.size.width = round(NSWidth(rect)*pct);
    [[NSColor colorWithWhite:1.0 alpha:0.85] setFill]; // active fill
    NSBezierPath *fg = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:2 yRadius:2];
    [fg fill];
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
