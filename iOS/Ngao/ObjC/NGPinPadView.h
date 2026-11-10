#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NGPinPadView;

NS_SWIFT_UI_ACTOR
@protocol NGPinPadViewDelegate <NSObject>
/// Called once the user has entered `length` digits. The pad clears itself afterwards.
- (void)pinPadView:(NGPinPadView *)pad didCompletePIN:(NSString *)pin;
@end

/// Six-dot PIN entry with its own keypad. Written in Objective-C on purpose: banking apps
/// in the field carry years of Objective-C, and this view is what a legacy component looks
/// like when it is kept honest: ARC, nullability annotations, no UITextField (so no
/// autocorrect, no clipboard, no keyboard cache), Core Animation for feedback.
IB_DESIGNABLE NS_SWIFT_UI_ACTOR
@interface NGPinPadView : UIView

@property (nonatomic, weak, nullable) id<NGPinPadViewDelegate> delegate;
@property (nonatomic, assign) NSUInteger length;            // default 6
@property (nonatomic, strong) UIColor *dotColor;            // default label color
@property (nonatomic, strong) UIColor *accentColor;         // filled dots and key highlight
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

/// Number of digits entered so far.
@property (nonatomic, readonly) NSUInteger enteredCount;

/// Clears the entry. Animated shake when `rejected` is YES (wrong PIN).
- (void)clearAnimated:(BOOL)animated rejected:(BOOL)rejected;

/// Shuffles the digit layout. Defeats smudge and shoulder-surfing patterns.
- (void)shuffleKeys;

@end

NS_ASSUME_NONNULL_END
