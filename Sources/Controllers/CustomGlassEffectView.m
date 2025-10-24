//
//  CustomGlassEffectView.m
//  Volume Control
//
//  Created by AI Assistant on 24.10.25.
//

#import "CustomGlassEffectView.h"

@interface CustomGlassEffectView ()
@property (nonatomic, strong) NSGlassEffectView *glassView;
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
                 cornerRadius:(CGFloat)cornerRadius {
    
    self = [super initWithFrame:frameRect];
    if (self) {
        Class GlassEffectViewClass = NSClassFromString(@"NSGlassEffectView");
        if (!GlassEffectViewClass) {
            return self;
        }

        _glassView = [[GlassEffectViewClass alloc] initWithFrame:self.bounds];
        _glassView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        
        // Configure with all known properties
        [self configureGlassViewWithVariant:variant
                                 scrimState:scrimState
                               subduedState:subduedState
                           interactionState:interactionState
                             contentLensing:contentLensing
                         adaptiveAppearance:adaptiveAppearance
                     useReducedShadowRadius:useReducedShadowRadius
                                      style:style
                               cornerRadius:cornerRadius];
        
        [self addSubview:_glassView];
    }
    return self;
}

- (void)configureGlassViewWithVariant:(NSInteger)variant
                           scrimState:(NSInteger)scrimState
                         subduedState:(NSInteger)subduedState
                     interactionState:(NSInteger)interactionState
                       contentLensing:(NSInteger)contentLensing
                   adaptiveAppearance:(NSInteger)adaptiveAppearance
               useReducedShadowRadius:(NSInteger)useReducedShadowRadius
                                style:(NSGlassEffectViewStyle)style
                         cornerRadius:(CGFloat)cornerRadius {
    
    // Public properties
    _glassView.style = style;
    _glassView.cornerRadius = cornerRadius;
    
    // Private properties via KVC
    [_glassView setValue:@(variant) forKey:@"_variant"];
    [_glassView setValue:@(scrimState) forKey:@"_scrimState"];
    [_glassView setValue:@(subduedState) forKey:@"_subduedState"];
    
    // The newly discovered, critical properties
    [_glassView setValue:@(interactionState) forKey:@"_interactionState"];
    [_glassView setValue:@(contentLensing) forKey:@"_contentLensing"];
    [_glassView setValue:@(adaptiveAppearance) forKey:@"_adaptiveAppearance"];
    [_glassView setValue:@(useReducedShadowRadius) forKey:@"_useReducedShadowRadius"];
}

- (void)setContentView:(NSView *)contentView {
    _glassView.contentView = contentView;
}

- (NSView *)contentView {
    return _glassView.contentView;
}

@end
