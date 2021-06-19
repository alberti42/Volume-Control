//
//  IntroWindowController.h
//  iTunes Volume Control
//
//  Created by Andrea Alberti on 15.12.13.
//  Copyright (c) 2013 Andrea Alberti. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class AppDelegate;

@interface IntroWindowController : NSWindowController
{
    AppDelegate *appDelegate;
    
    CALayer* iTunesScreenshotIntroLayer;
    CALayer* statusbarScreenshotIntroLayer;
    CALayer* arrow_1_Layer;
    CALayer* arrow_2_Layer;

    IBOutlet NSTextField *iTune_label_1;
    IBOutlet NSTextField *iTune_label_2;
    IBOutlet NSTextField *iTune_label_3;
    
    int step_number;
    
@public
}

@property (nonatomic,assign) IBOutlet NSButton *closeButton;
@property (nonatomic,assign) IBOutlet NSButton *nextButton;
@property (nonatomic,assign) IBOutlet NSButton *previousButton;
@property (nonatomic,assign) IBOutlet NSButton *loadIntroAtStartButton;

- (IBAction)nextButtonClicked:(id)sender;
- (IBAction)prevButtonClicked:(id)sender;
- (IBAction)closeButtonClicked:(id)sender;
- (IBAction)loadIntroAtStartChanged:(id)sender;


@end
