#import "NGPinPadView.h"

static const CGFloat NGDotSize = 14.0;
static const CGFloat NGDotSpacing = 18.0;
static const CGFloat NGKeyHeight = 64.0;

@interface NGPinPadView ()
@property (nonatomic, strong) NSMutableString *entry;
@property (nonatomic, strong) NSMutableArray<CAShapeLayer *> *dots;
@property (nonatomic, strong) UIStackView *keypad;
@property (nonatomic, strong) NSArray<NSNumber *> *keyOrder;
@end

@implementation NGPinPadView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) { [self commonInit]; }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) { [self commonInit]; }
    return self;
}

- (void)commonInit {
    _length = 6;
    _enabled = YES;
    _entry = [NSMutableString string];
    _dots = [NSMutableArray array];
    _dotColor = UIColor.labelColor;
    _accentColor = UIColor.systemGreenColor;
    _keyOrder = @[@1, @2, @3, @4, @5, @6, @7, @8, @9, @0];
    self.isAccessibilityElement = NO;
    [self buildDots];
    [self buildKeypad];
}

#pragma mark - Dots

- (void)buildDots {
    for (CAShapeLayer *dot in self.dots) { [dot removeFromSuperlayer]; }
    [self.dots removeAllObjects];
    for (NSUInteger i = 0; i < self.length; i++) {
        CAShapeLayer *dot = [CAShapeLayer layer];
        dot.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, NGDotSize, NGDotSize)].CGPath;
        dot.fillColor = UIColor.clearColor.CGColor;
        dot.strokeColor = self.dotColor.CGColor;
        dot.lineWidth = 1.5;
        [self.layer addSublayer:dot];
        [self.dots addObject:dot];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat totalWidth = self.length * NGDotSize + (self.length - 1) * NGDotSpacing;
    CGFloat x = (CGRectGetWidth(self.bounds) - totalWidth) / 2.0;
    for (CAShapeLayer *dot in self.dots) {
        dot.frame = CGRectMake(x, 8, NGDotSize, NGDotSize);
        x += NGDotSize + NGDotSpacing;
    }
    CGFloat keypadTop = 8 + NGDotSize + 32;
    self.keypad.frame = CGRectMake(0, keypadTop, CGRectGetWidth(self.bounds), 4 * NGKeyHeight + 3 * 8);
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, 8 + NGDotSize + 32 + 4 * NGKeyHeight + 3 * 8);
}

- (void)refreshDots {
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.12];
    for (NSUInteger i = 0; i < self.dots.count; i++) {
        CAShapeLayer *dot = self.dots[i];
        BOOL filled = i < self.entry.length;
        dot.fillColor = filled ? self.accentColor.CGColor : UIColor.clearColor.CGColor;
        dot.strokeColor = filled ? self.accentColor.CGColor : self.dotColor.CGColor;
        if (filled && i == self.entry.length - 1) {
            CABasicAnimation *pop = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
            pop.fromValue = @1.4;
            pop.toValue = @1.0;
            pop.duration = 0.18;
            pop.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [dot addAnimation:pop forKey:@"pop"];
        }
    }
    [CATransaction commit];
}

#pragma mark - Keypad

- (void)buildKeypad {
    [self.keypad removeFromSuperview];
    UIStackView *rows = [[UIStackView alloc] init];
    rows.axis = UILayoutConstraintAxisVertical;
    rows.distribution = UIStackViewDistributionFillEqually;
    rows.spacing = 8;

    NSArray<NSArray *> *layout = @[
        @[self.keyOrder[0], self.keyOrder[1], self.keyOrder[2]],
        @[self.keyOrder[3], self.keyOrder[4], self.keyOrder[5]],
        @[self.keyOrder[6], self.keyOrder[7], self.keyOrder[8]],
        @[@"", self.keyOrder[9], @"⌫"],
    ];
    for (NSArray *rowKeys in layout) {
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.distribution = UIStackViewDistributionFillEqually;
        row.spacing = 8;
        for (id key in rowKeys) {
            UIButton *button = [self keyButtonFor:key];
            [row addArrangedSubview:button];
        }
        [rows addArrangedSubview:row];
    }
    [self addSubview:rows];
    self.keypad = rows;
}

- (UIButton *)keyButtonFor:(id)key {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    NSString *title = [key isKindOfClass:NSNumber.class] ? [(NSNumber *)key stringValue] : key;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:28 weight:UIFontWeightRegular];
    [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius = 12;
    button.hidden = title.length == 0;
    button.accessibilityIdentifier = [title isEqualToString:@"⌫"] ? @"pin-key-delete" : [@"pin-key-" stringByAppendingString:title];
    button.accessibilityLabel = [title isEqualToString:@"⌫"] ? @"Delete" : title;
    [button addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(keyDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(keyUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return button;
}

- (void)keyDown:(UIButton *)sender {
    [UIView animateWithDuration:0.08 animations:^{
        sender.backgroundColor = [self.accentColor colorWithAlphaComponent:0.25];
    }];
}

- (void)keyUp:(UIButton *)sender {
    [UIView animateWithDuration:0.15 animations:^{
        sender.backgroundColor = UIColor.secondarySystemBackgroundColor;
    }];
}

- (void)keyTapped:(UIButton *)sender {
    if (!self.enabled) { return; }
    NSString *title = [sender titleForState:UIControlStateNormal];
    if ([title isEqualToString:@"⌫"]) {
        if (self.entry.length > 0) {
            [self.entry deleteCharactersInRange:NSMakeRange(self.entry.length - 1, 1)];
        }
    } else if (self.entry.length < self.length) {
        [self.entry appendString:title];
    }
    [self refreshDots];
    if (self.entry.length == self.length) {
        NSString *pin = [self.entry copy];
        self.enabled = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.delegate pinPadView:self didCompletePIN:pin];
        });
    }
}

#pragma mark - Public

- (NSUInteger)enteredCount { return self.entry.length; }

- (void)setLength:(NSUInteger)length {
    _length = length;
    [self.entry setString:@""];
    [self buildDots];
    [self setNeedsLayout];
}

- (void)clearAnimated:(BOOL)animated rejected:(BOOL)rejected {
    [self.entry setString:@""];
    self.enabled = YES;
    if (!animated) { [self refreshDots]; return; }
    if (rejected) {
        CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        shake.values = @[@0, @-12, @10, @-8, @6, @-3, @0];
        shake.duration = 0.4;
        shake.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        for (CAShapeLayer *dot in self.dots) {
            dot.fillColor = UIColor.systemRedColor.CGColor;
            dot.strokeColor = UIColor.systemRedColor.CGColor;
            [dot addAnimation:shake forKey:@"shake"];
        }
        UINotificationFeedbackGenerator *haptic = [[UINotificationFeedbackGenerator alloc] init];
        [haptic notificationOccurred:UINotificationFeedbackTypeError];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self refreshDots];
        });
    } else {
        [self refreshDots];
    }
}

- (void)shuffleKeys {
    NSMutableArray *digits = [@[@0, @1, @2, @3, @4, @5, @6, @7, @8, @9] mutableCopy];
    for (NSUInteger i = digits.count - 1; i > 0; i--) {
        [digits exchangeObjectAtIndex:i withObjectAtIndex:arc4random_uniform((uint32_t)(i + 1))];
    }
    self.keyOrder = [digits copy];
    [self buildKeypad];
    [self setNeedsLayout];
}

@end
