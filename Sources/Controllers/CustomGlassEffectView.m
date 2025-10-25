//
//  CustomGlassEffectView.m
//  Volume Control
//

#import "CustomGlassEffectView.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@interface CustomGlassEffectView ()
@property (nonatomic, strong) NSView *glassView; // NSGlassEffectView if present, else NSVisualEffectView
@end

@implementation CustomGlassEffectView

- (instancetype)initWithFrame:(NSRect)frameRect
                      variant:(NSInteger)variant
                   scrimState:(NSInteger)scrimState
                 subduedState:(NSInteger)subduedState
             interactionState:(NSInteger)interactionState
               contentLensing:(NSInteger)contentLensing
           adaptiveAppearance:(NSInteger)adaptiveAppearance
       useReducedShadowRadius:(NSInteger)useReducedShadowRadius
                        style:(NSGlassEffectViewStyle)style
                 cornerRadius:(CGFloat)cornerRadius
{
    self = [super initWithFrame:frameRect];
    if (!self) return nil;

    // Transparent host that clips to rounded corners
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.clearColor.CGColor;
    self.layer.cornerRadius = cornerRadius;
    self.layer.masksToBounds = YES;

    Class GlassEffectViewClass = NSClassFromString(@"NSGlassEffectView");
    if (GlassEffectViewClass) {
        // Normal ObjC messaging—no objc_msgSend needed
        NSView *glass = [(NSView *)[GlassEffectViewClass alloc] initWithFrame:self.bounds];
        glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        glass.wantsLayer = YES;
        glass.layer.backgroundColor = NSColor.clearColor.CGColor;
        glass.layer.cornerRadius = cornerRadius;
        glass.layer.masksToBounds = YES;

        // Public properties (via KVC to avoid needing the SDK at compile time)
        @try {
            [glass setValue:@(style) forKey:@"style"];
            [glass setValue:@(cornerRadius) forKey:@"cornerRadius"];
            // Optional: subtle neutral tint
            // [glass setValue:[NSColor colorWithWhite:0 alpha:0.08] forKey:@"tintColor"];
        } @catch (...) {}

        // Private knobs (best-effort; ignore if not present)
        [self safeSetValue:@(variant)                forKey:@"_variant"                on:glass];
        [self safeSetValue:@(scrimState)             forKey:@"_scrimState"             on:glass];
        [self safeSetValue:@(subduedState)           forKey:@"_subduedState"           on:glass];
        [self safeSetValue:@(interactionState)       forKey:@"_interactionState"       on:glass];
        [self safeSetValue:@(contentLensing)         forKey:@"_contentLensing"         on:glass];
        [self safeSetValue:@(adaptiveAppearance)     forKey:@"_adaptiveAppearance"     on:glass];
        [self safeSetValue:@(useReducedShadowRadius) forKey:@"_useReducedShadowRadius" on:glass];

        self.glassView = glass;
    } else {
        // Fallback for pre-Tahoe
        NSVisualEffectView *visual = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
        visual.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        visual.material = NSVisualEffectMaterialUnderWindowBackground;
        visual.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        visual.state = NSVisualEffectStateActive;

        visual.wantsLayer = YES;
        visual.layer.backgroundColor = NSColor.clearColor.CGColor;
        visual.layer.cornerRadius = cornerRadius;
        visual.layer.masksToBounds = YES;

        self.glassView = visual;
    }

    // Put the glass behind any content
    [self addSubview:self.glassView positioned:NSWindowBelow relativeTo:nil];

    return self;
}

- (void)safeSetValue:(id)value forKey:(NSString *)key on:(id)obj {
    @try { [obj setValue:value forKey:key]; } @catch (...) {}
}

#pragma mark - contentView proxy

- (void)setContentView:(NSView *)contentView {
    if (!contentView) return;

    contentView.translatesAutoresizingMaskIntoConstraints = NO;

    // If this is a real NSGlassEffectView, set its contentView via KVC.
    // Otherwise, place the content above the fallback visual effect view.
    if ([self.glassView respondsToSelector:NSSelectorFromString(@"setContentView:")]) {
        [self.glassView setValue:contentView forKey:@"contentView"];

        // Ensure it fills our bounds (constraints can be to self; both share an ancestor)
        [NSLayoutConstraint activateConstraints:@[
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    } else {
        [self addSubview:contentView positioned:NSWindowAbove relativeTo:self.glassView];
        [NSLayoutConstraint activateConstraints:@[
            [contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
}

- (NSView *)contentView {
    if ([self.glassView respondsToSelector:NSSelectorFromString(@"contentView")]) {
        @try { return [self.glassView valueForKey:@"contentView"]; } @catch (...) {}
    }
    return nil;
}

@end
