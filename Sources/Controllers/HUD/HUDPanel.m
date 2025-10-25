// FILE: HUDPanel.m
#import "HUDPanel.h"

@implementation HUDPanel

// Allow this nonactivating panel to be key so controls (slider) behave nicely.
- (BOOL)canBecomeKeyWindow { return YES; }

// Do not pretend to be the main app window.
- (BOOL)canBecomeMainWindow { return NO; }

// Keep it nonactivating: clicks won’t steal app focus.
- (BOOL)worksWhenModal { return YES; }

@end
