//
//  AccessibilityDialog.h
//  iTunes Volume Control
//
//  Created by Andrea Alberti on 09.06.19.
//  Copyright © 2019 Andrea Alberti. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScreenshotView : NSImageView
{
        NSImage* screenshotImage;
}

-(void)setAppropriateImage;

@end

@interface AccessibilityDialog : NSWindowController
{
    NSTimer* checkAuthorizationTimer;    
    
@public
    
    BOOL authorized;
}

@property (nonatomic, assign) IBOutlet NSButton* exitBtn;
@property (nonatomic, assign) IBOutlet NSButton* openSecurityPrivacyBtn;
@property (nonatomic, assign) IBOutlet NSButton* restartBtn;
@property (nonatomic, assign) IBOutlet ScreenshotView* screenshot;

- (IBAction)onRestart:(id)sender;
- (IBAction)onExitButton:(id)sender;
- (IBAction)onOpenSecurityPrivacy:(id)sender;

// we need our own Enum because the system's AVAuthorizationStatus is not available prior to 10.14
typedef NS_ENUM(NSInteger, PrivacyConsentState) {
    PrivacyConsentStateUnknown,
    PrivacyConsentStateGranted,
    PrivacyConsentStateDenied
};

@end


NS_ASSUME_NONNULL_END
