//
//  HoverSlider.m
//  Volume Control
//
//  Created by Andrea Alberti on 26.10.25.
//

#import "HoverSlider.h"
#import "CustomVolumeSlider.h" // We need this to access the 'isHovered' property

@implementation HoverSlider

// This method sets up the tracking area that allows us to receive mouse events.
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    
    // Remove any old tracking areas to prevent duplicates
    for (NSTrackingArea *area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }
    
    // **MODIFIED:** Changed the tracking option to be always active.
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways;
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                                options:options
                                                                  owner:self
                                                               userInfo:nil];
    [self addTrackingArea:trackingArea];
}

// Called when the mouse cursor enters the slider's bounds.
- (void)mouseEntered:(NSEvent *)event {
    [super mouseEntered:event];
    if ([self.cell isKindOfClass:[CustomVolumeSlider class]]) {
        // Tell our custom cell that it's being hovered
        ((CustomVolumeSlider *)self.cell).isHovered = YES;
        // Trigger a redraw to show the knob
        [self setNeedsDisplay:YES];
    }
}

// Called when the mouse cursor leaves the slider's bounds.
- (void)mouseExited:(NSEvent *)event {
    [super mouseExited:event];
    if ([self.cell isKindOfClass:[CustomVolumeSlider class]]) {
        // Tell our custom cell that the hover is over
        ((CustomVolumeSlider *)self.cell).isHovered = NO;
        // Trigger a redraw to hide the knob
        [self setNeedsDisplay:YES];
    }
}

@end
