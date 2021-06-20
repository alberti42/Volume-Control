#import "VolumeWindow.h"

@implementation VolumeWindow

- (id) initWithContentRect: (NSRect) contentRect
                 styleMask: (NSWindowStyleMask) aStyle
                   backing: (NSBackingStoreType) bufferingType
                     defer: (BOOL) flag
{
    self = [super initWithContentRect: contentRect styleMask: NSWindowStyleMaskBorderless backing: bufferingType defer: flag];
    if (!self) return nil;
    
    [self setHasShadow:NO];
    [self setCanBecomeVisibleWithoutLogin:YES];
    [self setCollectionBehavior: 0x12];
    [self setIgnoresMouseEvents: YES];
    [self setBackgroundColor: [NSColor clearColor]];
    [self setOpaque:NO];
    [self setLevel: 0x7d5]; // NSFloatingWindowLevel
    [self orderOut:nil];
    [self setAlphaValue:1];
    
    return self;
}

/*
- (NSImage *)_cornerMaskabout
{
    NSLog(@"triggered");
    CGFloat radius = 18.0;
    CGFloat dimension = 300;
    NSSize size = NSMakeSize(dimension, dimension);
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        NSBezierPath *bezierPath = [NSBezierPath bezierPathWithRoundedRect:dstRect xRadius:radius yRadius:radius];
        [[NSColor whiteColor] set];
        [bezierPath fill];
        return YES;
    }];
    image.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
    image.resizingMode = NSImageResizingModeStretch;
    return image;
}

- (NSImage *)cornerMask
{
    return [self _cornerMask];
}

- (NSImage *) maskImageWithBounds: (NSRect) bounds
{
return [NSImage imageWithSize:bounds.size flipped:YES drawingHandler:^BOOL(NSRect dstRect) {

    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:18.0 yRadius:18.0];

    // [path setLineJoinStyle:NSRoundLineJoinStyle];
    [path fill];

    return YES;
}];
}
*/

-(void)awakeFromNib
{
    /*
    NSRect screenFrame = [[NSScreen mainScreen] frame];
     
    [self setFrame:CGRectMake(round((screenFrame.size.width-200)/2)+200,140,200,200) display:NO animate:NO];
    
    NSVisualEffectView* visualEffectView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    visualEffectView.material =  0x1a; // NSVisualEffectMaterialLight;
    visualEffectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    visualEffectView.state = NSVisualEffectStateActive;
    visualEffectView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    
    visualEffectView.maskImage = [self _cornerMask];

    
    [[self contentView] addSubview:visualEffectView positioned:1 relativeTo:0];
     */
    
    
    // [self setStyleMask:self.styleMask | NSFullSizeContentViewWindowMask];
    // [self setTitlebarAppearsTransparent:true];
    
    //[[self contentView] addConstraints:(NSLayoutConstraint.constraintsWithVisualFormat("V:|-0-[visualEffectView]-0-|", views: ["visualEffectView":visualEffectView]))];
    //self.contentView.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("H:|-0-[visualEffectView]-0-|", options: NSLayoutFormatOptions.DirectionLeadingToTrailing, metrics: nil, views: ["visualEffectView":visualEffectView]))
}




@end
