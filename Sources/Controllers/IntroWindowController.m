//
//  IntroWindowController.m
//  iTunes Volume Control
//
//  Created by Andrea Alberti on 15.12.13.
//  Copyright (c) 2013 Andrea Alberti. All rights reserved.
//

#import "IntroWindowController.h"
#import <QuartzCore/CoreAnimation.h>
#import "AppDelegate.h"

@interface IntroWindowController ()

@end

@implementation IntroWindowController

@synthesize nextButton;
@synthesize previousButton;
@synthesize closeButton;
@synthesize loadIntroAtStartButton;

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
        
        appDelegate = [[NSApplication sharedApplication] delegate];
        
        [[NSNotificationCenter defaultCenter] addObserver:appDelegate selector:@selector(introWindowWillClose:) name:NSWindowWillCloseNotification object:window];
        
        step_number = 0;
    }
    return self;
}


- (IBAction)loadIntroAtStartChanged:(id)sender
{
    [appDelegate setLoadIntroAtStart:[loadIntroAtStartButton state]];
}

- (IBAction)closeButtonClicked:(id)sender
{
    [NSTimer scheduledTimerWithTimeInterval:0.2 target:[self window] selector:@selector(close) userInfo:nil repeats:NO];
}

- (IBAction)nextButtonClicked:(id)sender
{
    //    CABasicAnimation* fadeOutAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    //    [fadeOutAnimation setDuration:1.f];
    //    [fadeOutAnimation setRemovedOnCompletion:NO];
    //    [fadeOutAnimation setFillMode:kCAFillModeForwards];
    //    [fadeOutAnimation setFromValue:[NSNumber numberWithFloat:1.0f]];
    //    [fadeOutAnimation setToValue:[NSNumber numberWithFloat:0.0f]];
    
    switch (step_number)
    {
        case 0:
            
            [previousButton setEnabled:YES];
            
            [[NSAnimationContext currentContext] setDuration:1.0f];
            [NSAnimationContext beginGrouping];
            //    [introLayer addAnimation:fadeOutAnimation forKey:@"decreaseOpacity"];
            [[iTune_label_2 animator] setAlphaValue:1.f];
            [arrow_2_Layer setOpacity:1.f];
            [NSAnimationContext endGrouping];
            break;
        case 1:
            [nextButton setEnabled:NO];
            [closeButton setEnabled:YES];
            
            [[NSAnimationContext currentContext] setDuration:0.8f];
            [NSAnimationContext beginGrouping];
            [[iTune_label_1 animator] setAlphaValue:0.f];
            [[iTune_label_2 animator] setAlphaValue:0.f];
            [arrow_1_Layer setOpacity:0.f];
            [arrow_2_Layer setOpacity:0.f];
            [statusbarScreenshotIntroLayer setOpacity:1.0f];
            [iTunesScreenshotIntroLayer setOpacity:0.0f];
            [NSAnimationContext endGrouping];

            
            break;
    }
    
    step_number++;
    
}

- (IBAction)prevButtonClicked:(id)sender
{
    switch (step_number)
    {
        case 1:
            [previousButton setEnabled:NO];
            
            [[NSAnimationContext currentContext] setDuration:0.4f];
            [NSAnimationContext beginGrouping];
            //    [introLayer addAnimation:fadeOutAnimation forKey:@"decreaseOpacity"];
            [[iTune_label_2 animator] setAlphaValue:0.f];
            [arrow_2_Layer setOpacity:0.f];
            [NSAnimationContext endGrouping];
            
            
            break;
        case 2:
            [nextButton setEnabled:YES];
            [closeButton setEnabled:NO];
            
            [[NSAnimationContext currentContext] setDuration:0.4f];
            [NSAnimationContext beginGrouping];
            [[iTune_label_1 animator] setAlphaValue:1.f];
            [[iTune_label_2 animator] setAlphaValue:1.f];
            [arrow_1_Layer setOpacity:1.f];
            [arrow_2_Layer setOpacity:1.f];
            [statusbarScreenshotIntroLayer setOpacity:0.0f];
            [iTunesScreenshotIntroLayer setOpacity:1.0f];
            [NSAnimationContext endGrouping];
            break;
    }
    
    step_number--;
}


-(void)showFirstMessage:(NSTimer*)theTimer
{
    [[NSAnimationContext currentContext] setDuration:1.3f];
    [NSAnimationContext beginGrouping];
    [[iTune_label_1 animator] setAlphaValue:1.f];
    [arrow_1_Layer setOpacity:1.f];
    [NSAnimationContext endGrouping];
}

-(void)awakeFromNib
{
    NSWindow* introWindow = [self window];
    NSView* introContentView = [introWindow contentView];
    
    CGSize windowViewSize = [introContentView frame].size;
    
    NSRect imageRect = NSZeroRect;
    
    NSImage *iTunesScreenshot=[NSImage imageNamed:@"iTunes-screenshot"];
    NSImage *iTunes_arrow_1=[NSImage imageNamed:@"iTunes-arrow-1"];
    NSImage *iTunes_arrow_2=[NSImage imageNamed:@"iTunes-arrow-2"];
//    NSImage *statusbarScreenshot=[NSImage imageNamed:@"statusbar-screenshot"];
    NSImage *statusbarScreenshot=[NSImage imageNamed:@"keyboard"];
    
    //[introWindow setContentBorderThickness:36 forEdge:NSMinYEdge];
    
    CALayer* toplayer = [CALayer layer];
    //CGColorRef backgroundColor=CGColorCreateGenericRGB(1.f, 1.f, 1.f, 1.f);
    //[toplayer setBackgroundColor:backgroundColor];
    //CFRelease(backgroundColor);
    
    // iTunes screenshot
    iTunesScreenshotIntroLayer = [CALayer layer];
    imageRect.size = [iTunesScreenshot size];
    [iTunesScreenshotIntroLayer setFrame:NSRectToCGRect(imageRect)];
    [iTunesScreenshotIntroLayer setPosition:CGPointMake(windowViewSize.width/2-16,windowViewSize.height-imageRect.size.height/2-60)];
    [iTunesScreenshotIntroLayer setContents:iTunesScreenshot];
    //[introLayer setBorderColor:CGColorCreateGenericRGB(1.f, 0.f, 0.f, 1.f)];
    //[introLayer setBorderWidth:1];
    [toplayer addSublayer:iTunesScreenshotIntroLayer];
    
    // Statusbar screenshot
    statusbarScreenshotIntroLayer = [CALayer layer];
    //  [statusbarScreenshotIntroLayer setCompositingFilter:[CIFilter filterWithName:@"CIAdditionCompositing"]];

    imageRect.size = [statusbarScreenshot size];
    [statusbarScreenshotIntroLayer setFrame:NSRectToCGRect(imageRect)];
    [statusbarScreenshotIntroLayer setPosition:CGPointMake(350,windowViewSize.height-250)];
    [statusbarScreenshotIntroLayer setContents:statusbarScreenshot];
    [statusbarScreenshotIntroLayer setOpacity:0.f];
    [toplayer addSublayer:statusbarScreenshotIntroLayer];
    
    arrow_1_Layer = [CALayer layer];
    imageRect.size = [iTunes_arrow_1 size];
    [arrow_1_Layer setFrame:NSRectToCGRect(imageRect)];
    [arrow_1_Layer setPosition:CGPointMake(313,windowViewSize.height-94)];
    [arrow_1_Layer setContents:iTunes_arrow_1];
    [arrow_1_Layer setOpacity:0.f];
    [toplayer addSublayer:arrow_1_Layer];
    
    [iTune_label_1 setAlphaValue:0.f];
    
    arrow_2_Layer = [CALayer layer];
    imageRect.size = [iTunes_arrow_2 size];
    [arrow_2_Layer setFrame:NSRectToCGRect(imageRect)];
    [arrow_2_Layer setPosition:CGPointMake(240,windowViewSize.height-95)];
    [arrow_2_Layer setContents:iTunes_arrow_2];
    [arrow_2_Layer setOpacity:0.f];
    [toplayer addSublayer:arrow_2_Layer];
    
    [iTune_label_2 setAlphaValue:0.f];
    
    NSRect frameRect = NSMakeRect(20,20,40,40); // This will change based on the size you need
    iTune_label_3 = [[NSTextField alloc] initWithFrame:frameRect];
    [iTune_label_3 setStringValue:@"My Label"];
    [iTune_label_3 setBezeled:NO];
    [iTune_label_3 setDrawsBackground:NO];
    [iTune_label_3 setEditable:NO];
    [iTune_label_3 setSelectable:NO];
    [introContentView addSubview:iTune_label_3];
    
    [introContentView setLayer:toplayer];
    [introContentView setWantsLayer:YES];
    
    NSImage *closeButtonImage=[NSImage imageNamed:@"introButtons-close"];
    NSImage *closeButtonImageHL=[NSImage imageNamed:@"introButtons-close-HL"];
    [closeButton setImage: closeButtonImage];
    [closeButton setAlternateImage: closeButtonImageHL];
    [closeButton setBordered:NO];
    [closeButton setEnabled:NO];
    [[closeButton cell] setHighlightsBy:1];
    
    NSImage *nextButtonImage=[NSImage imageNamed:@"introButtons-next"];
    NSImage *nextButtonImageHL=[NSImage imageNamed:@"introButtons-next-HL"];
    [nextButton setImage: nextButtonImage];
    [nextButton setAlternateImage: nextButtonImageHL];
    [nextButton setBordered:NO];
    [[nextButton cell] setHighlightsBy:1];
    
    NSImage *prevButtonImage=[NSImage imageNamed:@"introButtons-prev"];
    NSImage *prevButtonImageHL=[NSImage imageNamed:@"introButtons-prev-HL"];
    [previousButton setImage: prevButtonImage];
    [previousButton setAlternateImage: prevButtonImageHL];
    [previousButton setBordered:NO];
    [previousButton setEnabled:NO];
    [[previousButton cell] setHighlightsBy:1];
    
    [NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(showFirstMessage:) userInfo:nil repeats:NO];

    [loadIntroAtStartButton setState: [appDelegate loadIntroAtStart]];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

@end
