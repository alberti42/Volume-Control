//
//  CustomGlassEffectView.h
//  Volume Control
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(macos(16.0))
@interface CustomGlassEffectView : NSView

/// The view displayed above the glass layer (your actual content).
@property (nonatomic, strong, nullable) NSView *contentView;

/// Initializes a view backed by the private NSGlassEffectView (or fallback).
/// The parameters correspond to internal Tahoe glass properties.
///
- (instancetype)initWithFrame:(NSRect)frameRect
                      variant:(NSInteger)variant
                   scrimState:(NSInteger)scrimState
                 subduedState:(NSInteger)subduedState
             interactionState:(NSInteger)interactionState
               contentLensing:(NSInteger)contentLensing
           adaptiveAppearance:(NSInteger)adaptiveAppearance
       useReducedShadowRadius:(NSInteger)useReducedShadowRadius
                        style:(NSGlassEffectViewStyle)style
                 cornerRadius:(CGFloat)cornerRadius NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
