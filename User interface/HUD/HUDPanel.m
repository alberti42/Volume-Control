// FILE: HUDPanel.m
#import "HUDPanel.h"

@implementation HUDPanel

// Allow this nonactivating panel to be key so controls (slider) behave nicely.
- (BOOL)canBecomeKeyWindow { return YES; }

// Explicitly state that the panel can become the first responder.
// This allows controls within the panel (like the slider) to receive and process mouse events.
- (BOOL)acceptsFirstResponder { return YES; }

// Do not pretend to be the main app window.
- (BOOL)canBecomeMainWindow { return NO; }

// Keep it nonactivating: clicks won’t steal app focus.
- (BOOL)worksWhenModal { return YES; }

// Draw as an active, key window although the panel never becomes key. Liquid Glass
// draws its bright rim and darker fill only in windows with an active appearance; in
// an inactive window it is flat and lighter than the background. ControlCenter's
// SystemBannerWindow, which shows the system volume HUD, overrides the same three
// private NSWindow methods to return YES (checked on macOS 27.0.1).
- (BOOL)_hasActiveAppearance { return YES; }
- (BOOL)_hasActiveControls { return YES; }
- (BOOL)hasKeyAppearance { return YES; }

@end
