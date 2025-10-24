//
//  CustomGlassEffectView.h
//  Volume Control
//
//  Created by AI Assistant on 24.10.25.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(macos(16.0))
@interface CustomGlassEffectView : NSView

@property (nonatomic, strong, nullable) NSView *contentView;

// A complete initializer based on the disassembled properties.
- (instancetype)initWithFrame:(NSRect)frameRect
                      variant:(NSInteger)variant
                   scrimState:(NSInteger)scrimState
                 subduedState:(NSInteger)subduedState
             interactionState:(NSInteger)interactionState
               contentLensing:(NSInteger)contentLensing
           adaptiveAppearance:(NSInteger)adaptiveAppearance
       useReducedShadowRadius:(NSInteger)useReducedShadowRadius
                        style:(NSGlassEffectViewStyle)style
                 cornerRadius:(CGFloat)cornerRadius;

@end

NS_ASSUME_NONNULL_END
