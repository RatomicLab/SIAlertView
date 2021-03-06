//
//  SIAlertView.m
//  SIAlertView
//
//  Created by Kevin Cao on 13-4-29.
//  Copyright (c) 2013年 Sumi Interactive. All rights reserved.
//

#import "SIAlertView.h"
#import "SISecondaryWindowRootViewController.h"
#import <QuartzCore/QuartzCore.h>

NSString *const SIAlertViewWillShowNotification = @"SIAlertViewWillShowNotification";
NSString *const SIAlertViewDidShowNotification = @"SIAlertViewDidShowNotification";
NSString *const SIAlertViewWillDismissNotification = @"SIAlertViewWillDismissNotification";
NSString *const SIAlertViewDidDismissNotification = @"SIAlertViewDidDismissNotification";

#define DEBUG_LAYOUT 0

#define GAP 10
#define CONTENT_PADDING_LEFT 10
#define CONTENT_PADDING_TOP 20
#define BUTTON_HEIGHT 50
#define INPUT_TEXT_HEIGHT 32
#define CONTAINER_WIDTH 270

const UIWindowLevel UIWindowLevelSIAlert = 1996.0;  // don't overlap system's alert
const UIWindowLevel UIWindowLevelSIAlertBackground = 1985.0; // below the alert window

@class SIAlertBackgroundWindow;

static NSMutableArray *__si_alert_queue;
static BOOL __si_alert_animating;
static SIAlertBackgroundWindow *__si_alert_background_window;
static SIAlertView *__si_alert_current_view;

@interface SIAlertView () <UITextFieldDelegate>

@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, strong) UIWindow *alertWindow;
@property (nonatomic, assign, getter = isVisible) BOOL visible;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UITextField *inputTextField;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIView *wrapperView;
@property (nonatomic, strong) UIScrollView *contentContainerView;
@property (nonatomic, strong) UIView *buttonContainerView;
@property (nonatomic, strong) CAShapeLayer *lineLayer;
@property (nonatomic, strong) NSMutableArray *buttons;

@property (nonatomic, assign, getter = isLayoutDirty) BOOL layoutDirty;

+ (NSMutableArray *)sharedQueue;
+ (SIAlertView *)currentAlertView;

+ (BOOL)isAnimating;
+ (void)setAnimating:(BOOL)animating;

+ (void)showBackground;
+ (void)hideBackgroundAnimated:(BOOL)animated;

- (void)setup;
- (void)invalidateLayout;
- (void)resetTransition;

@end

#pragma mark - SIBackgroundWindow

@interface SIAlertBackgroundWindow : UIWindow

@end

@interface SIAlertBackgroundWindow ()

@property (nonatomic, assign) SIAlertViewBackgroundStyle style;

@end

@implementation SIAlertBackgroundWindow

- (id)initWithFrame:(CGRect)frame andStyle:(SIAlertViewBackgroundStyle)style
{
    self = [super initWithFrame:frame];
    if (self) {
        self.style = style;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.opaque = NO;
        self.windowLevel = UIWindowLevelSIAlertBackground;
        
        UIViewController *viewController = [[SISecondaryWindowRootViewController alloc] init];
        self.rootViewController = viewController;
        viewController.view.hidden = YES;
        viewController.view.frame = self.bounds;
        viewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    return self;
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    switch (self.style) {
        case SIAlertViewBackgroundStyleGradient:
        {
            size_t locationsCount = 2;
            CGFloat locations[2] = {0.0f, 1.0f};
            CGFloat colors[8] = {0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.75f};
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, locations, locationsCount);
            CGColorSpaceRelease(colorSpace);
            
            CGPoint center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
            CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) ;
            CGContextDrawRadialGradient (context, gradient, center, 0, center, radius, kCGGradientDrawsAfterEndLocation);
            CGGradientRelease(gradient);
            break;
        }
        case SIAlertViewBackgroundStyleSolid:
        {
            [[UIColor colorWithWhite:0 alpha:0.5] set];
            CGContextFillRect(context, self.bounds);
            break;
        }
    }
}

@end

#pragma mark - SIAlertItem

@interface SIAlertItem : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSAttributedString *attributedTitle;
@property (nonatomic, assign) SIAlertViewButtonType type;
@property (nonatomic, copy) SIAlertViewHandler action;

@end

@implementation SIAlertItem

@end

#pragma mark - SIAlertViewController

@interface SIAlertViewController : SISecondaryWindowRootViewController

@property (nonatomic, strong) SIAlertView *alertView;

@end

@implementation SIAlertViewController

#pragma mark - View life cycle

- (void)loadView
{
    self.view = self.alertView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.alertView setup];
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [self.alertView resetTransition];
    [self.alertView invalidateLayout];
}

@end

#pragma mark - SIAlertView

@implementation SIAlertView

@synthesize title = _title, message = _message;
@synthesize attributedTitle = _attributedTitle, attributedMessage = _attributedMessage;

+ (void)initialize
{    
    SIAlertView *appearance = [self appearance];
    appearance.viewBackgroundColor = [UIColor whiteColor];
    appearance.seperatorColor = [UIColor colorWithWhite:0 alpha:0.1];
    appearance.cornerRadius = 2;
    
    appearance.defaultButtonBackgroundColor = [UIColor colorWithWhite:0.99 alpha:1];
    appearance.cancelButtonBackgroundColor = [UIColor colorWithWhite:0.97 alpha:1];
    appearance.destructiveButtonBackgroundColor = [UIColor colorWithWhite:0.99 alpha:1];
    
    appearance.contentViewPadding = CONTENT_PADDING_LEFT;
    
    appearance.buttonCornerRadius = 3.0f;
    appearance.buttonBorderWidth = 1.0f;
    appearance.defaultButtonBorderColor = [UIColor colorWithWhite:0.95 alpha:1];
    appearance.cancelButtonBorderColor = [UIColor colorWithWhite:0.95 alpha:1];
    appearance.destructiveButtonBorderColor = [UIColor colorWithWhite:0.95 alpha:1];
    
    UIFont *titleFont = [UIFont boldSystemFontOfSize:[UIFont labelFontSize]];
    UIFont *messageFont = [UIFont systemFontOfSize:[UIFont systemFontSize]];
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineHeightMultiple = 1.1;
    paragraphStyle.alignment = NSTextAlignmentCenter;
    appearance.titleAttributes = @{NSFontAttributeName : titleFont, NSForegroundColorAttributeName : [UIColor blackColor], NSParagraphStyleAttributeName : paragraphStyle};
    appearance.messageAttributes = @{NSFontAttributeName : messageFont, NSForegroundColorAttributeName : [UIColor darkGrayColor],  NSParagraphStyleAttributeName : paragraphStyle};
    
    UIFont *defaultButtonFont = [UIFont systemFontOfSize:[UIFont buttonFontSize]];
    UIFont *otherButtonFont = [UIFont boldSystemFontOfSize:[UIFont buttonFontSize]];
    appearance.defaultButtonAttributes = @{NSFontAttributeName : defaultButtonFont};
    appearance.cancelButtonAttributes = @{NSFontAttributeName : otherButtonFont};
    appearance.destructiveButtonAttributes = @{NSFontAttributeName : otherButtonFont, NSForegroundColorAttributeName : [UIColor colorWithRed:0.96f green:0.37f blue:0.31f alpha:1.00f]};
}

- (id) init
{
    self = [super init];
    if (self) {
        self.items = [NSMutableArray array];
        self.buttonBorderWidth = [[[self class] appearance] buttonBorderWidth];
        self.buttonCornerRadius = [[[self class] appearance] buttonCornerRadius];
        self.contentViewPadding = [[[self class] appearance] contentViewPadding];
    }
    return self;
}

- (id)initWithTitle:(NSString *)title message:(NSString *)message
{
	self = [self init];
	if (self) {
        self.title = title;
        self.message = message;
	}
	return self;
}

- (id)initWithTitle:(NSString *)title contentView:(UIView *)contentView
{
    self = [self init];
    if (self) {
        _title = title;
        _contentView = contentView;
    }
    return self;
}

- (id)initWithTitle:(NSString *)title message:(NSString *)message contentView:(UIView *)contentView
{
    self = [self init];
    if (self) {
        _title = title;
        _message = message;
        _contentView = contentView;
    }
    return self;
}

- (id)initWithTitle:(NSString *)title message:(NSString *)message cancelButton:(NSString *)canelButton handler:(SIAlertViewHandler)handler
{
    self = [self init];
	if (self) {
        self.title = title;
        self.message = message;
        
        if (canelButton) {
            [self addButtonWithTitle:canelButton type:SIAlertViewButtonTypeCancel handler:handler];
        }
	}
	return self;
}

- (id)initWithAttributedTitle:(NSAttributedString *)attributedTitle attributedMessage:(NSAttributedString *)attributedMessage
{
	self = [self init];
	if (self) {
		self.attributedTitle = attributedTitle;
        self.attributedMessage = attributedMessage;
	}
	return self;
}

#pragma mark - Class methods

+ (NSMutableArray *)sharedQueue
{
    if (!__si_alert_queue) {
        __si_alert_queue = [NSMutableArray array];
    }
    return __si_alert_queue;
}

+ (SIAlertView *)currentAlertView
{
    return __si_alert_current_view;
}

+ (void)setCurrentAlertView:(SIAlertView *)alertView
{
    __si_alert_current_view = alertView;
}

+ (BOOL)isAnimating
{
    return __si_alert_animating;
}

+ (void)setAnimating:(BOOL)animating
{
    __si_alert_animating = animating;
}

+ (void)showBackground
{
    if (!__si_alert_background_window) {
        __si_alert_background_window = [[SIAlertBackgroundWindow alloc] initWithFrame:[UIScreen mainScreen].bounds
                                                                             andStyle:[SIAlertView currentAlertView].backgroundStyle];
        [__si_alert_background_window makeKeyAndVisible];
        __si_alert_background_window.alpha = 0;
        [UIView animateWithDuration:0.3
                         animations:^{
                             __si_alert_background_window.alpha = 1;
                         }];
        
        UIWindow *mainWindow = [UIApplication sharedApplication].windows[0];
        mainWindow.tintAdjustmentMode = UIViewTintAdjustmentModeDimmed;
    }
}

+ (void)hideBackgroundAnimated:(BOOL)animated
{
    void (^completion)(void) = ^{
        UIWindow *mainWindow = [UIApplication sharedApplication].windows[0];
        mainWindow.tintAdjustmentMode = UIViewTintAdjustmentModeNormal;
        [mainWindow makeKeyWindow];
        __si_alert_background_window.hidden = YES;
        __si_alert_background_window = nil;
    };
    
    if (!animated) {
        completion();
        return;
    }
    [UIView animateWithDuration:0.3
                     animations:^{
                         __si_alert_background_window.alpha = 0;
                     }
                     completion:^(BOOL finished) {
                         completion();
                     }];
}

#pragma mark - Setters & Getters

- (void)setTitle:(NSString *)title
{
    if ([_title isEqualToString:title]) {
        return;
    }
    
    _title = [title copy];
    _attributedTitle = nil;
    if (self.isVisible) {
        [self updateTitleLabel];
    }
}

- (void)setMessage:(NSString *)message
{
    if ([_message isEqualToString:message]) {
        return;
    }
    
    _message = [message copy];
    _attributedMessage = nil;
    if (self.isVisible) {
        [self updateTitleLabel];
    }
}

- (NSString *)title
{
    if (!_title) {
        return _attributedTitle.string;
    }
    return _title;
}

- (NSString *)message
{
    if (!_message) {
        return _attributedMessage.string;
    }
    return _message;
}

- (void) setAlertViewStyle:(SIAlertViewStyle)alertViewStyle
{
    _alertViewStyle = alertViewStyle;
    
    if (alertViewStyle == SIAlertViewStyleTextInput)
    {
        self.inputTextField = [[UITextField alloc] init];
    }
}

- (void)setAttributedTitle:(NSAttributedString *)attributedTitle
{
    if (_attributedTitle == attributedTitle) {
        return;
    }
    
    _attributedTitle = [attributedTitle copy];
    _title = nil;
    if (self.isVisible) {
        [self updateTitleLabel];
    }
}

- (void)setAttributedMessage:(NSAttributedString *)attributedMessage
{
    if (_attributedMessage == attributedMessage) {
        return;
    }
    
    _attributedMessage = [attributedMessage copy];
    _message = nil;
    if (self.isVisible) {
        [self updateMessageLabel];
    }
}

- (NSAttributedString *)attributedTitle
{
    if (_attributedTitle) {
        return _attributedTitle;
    }
    if (_title) {
        return [[NSAttributedString alloc] initWithString:_title attributes:[self titleAttributes]];
    }
    return nil;
}

- (NSAttributedString *)attributedMessage
{
    if (_attributedMessage) {
        return _attributedMessage;
    }
    if (_message) {
        return [[NSAttributedString alloc] initWithString:_message attributes:[self messageAttributes]];
    }
    return nil;
}

#pragma mark - Public

- (void)addButtonWithTitle:(NSString *)title type:(SIAlertViewButtonType)type handler:(SIAlertViewHandler)handler
{
    NSAssert(title != nil, @"Title can't be nil");
    SIAlertItem *item = [[SIAlertItem alloc] init];
	item.title = title;
	item.type = type;
	item.action = handler;
	[self.items addObject:item];
}

- (void)addButtonWithTitle:(NSString *)title font:(UIFont *)font color:(UIColor *)color type:(SIAlertViewButtonType)type handler:(SIAlertViewHandler)handler
{
    NSAssert(title != nil, @"Title can't be nil");
    NSDictionary *defaults = nil;
    switch (type) {
        case SIAlertViewButtonTypeDefault:
            defaults = self.defaultButtonAttributes;
            break;
        case SIAlertViewButtonTypeCancel:
            defaults = self.cancelButtonAttributes;
            break;
        case SIAlertViewButtonTypeDestructive:
            defaults = self.destructiveButtonAttributes;
            break;
    }
    NSMutableDictionary *temp = [defaults mutableCopy];
    if (font) {
        temp[NSFontAttributeName] = font;
    }
    if (color) {
        temp[NSForegroundColorAttributeName] = color;
    }
    NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:temp];
    [self addButtonWithAttributedTitle:attributedTitle type:type handler:handler];
}

- (void)addButtonWithAttributedTitle:(NSAttributedString *)attributedTitle type:(SIAlertViewButtonType)type handler:(SIAlertViewHandler)handler
{
    NSAssert(attributedTitle != nil, @"Attributed title can't be nil");
    SIAlertItem *item = [[SIAlertItem alloc] init];
	item.attributedTitle = attributedTitle;
	item.type = type;
	item.action = handler;
	[self.items addObject:item];
}

- (void)show
{
    if (self.isVisible) {
        return;
    }
    
    if (![[SIAlertView sharedQueue] containsObject:self]) {
        [[SIAlertView sharedQueue] addObject:self];
    }
    
    if ([SIAlertView isAnimating]) {
        return; // wait for next turn
    }
    
    if ([SIAlertView currentAlertView].isVisible) {
        SIAlertView *alert = [SIAlertView currentAlertView];
        [alert dismissAnimated:YES cleanup:NO];
        return;
    }
    
    if (self.willShowHandler) {
        self.willShowHandler(self);
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:SIAlertViewWillShowNotification object:self userInfo:nil];
    
    self.visible = YES;
    
    [SIAlertView setAnimating:YES];
    [SIAlertView setCurrentAlertView:self];
    
    // transition background
    [SIAlertView showBackground];
    
    SIAlertViewController *viewController = [[SIAlertViewController alloc] initWithNibName:nil bundle:nil];
    viewController.alertView = self;
    
    if (!self.alertWindow) {
        UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        window.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        window.opaque = NO;
        window.windowLevel = UIWindowLevelSIAlert;
        window.rootViewController = viewController;
        self.alertWindow = window;
    }
    [self.alertWindow makeKeyAndVisible];
    
    [self validateLayout];
    
    [self transitionInCompletion:^{
        if (self.didShowHandler) {
            self.didShowHandler(self);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:SIAlertViewDidShowNotification object:self userInfo:nil];
        
        [self addParallaxEffect];
        
        [SIAlertView setAnimating:NO];
        
        if (self.inputTextField)
        {
            [self.inputTextField becomeFirstResponder];
        }
        
        NSInteger index = [[SIAlertView sharedQueue] indexOfObject:self];
        if (index < [SIAlertView sharedQueue].count - 1) {
            [self dismissAnimated:YES cleanup:NO]; // dismiss to show next alert view
        }
    }];
}

- (void)dismissAnimated:(BOOL)animated
{
    [self dismissAnimated:animated cleanup:YES];
}

- (void)dismissAnimated:(BOOL)animated cleanup:(BOOL)cleanup
{
    BOOL isVisible = self.isVisible;
    
    if (isVisible) {
        if (self.willDismissHandler) {
            self.willDismissHandler(self);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:SIAlertViewWillDismissNotification object:self userInfo:nil];
        #ifdef __IPHONE_7_0
                [self removeParallaxEffect];
        #endif
    }
    
    void (^dismissComplete)(void) = ^{
        [self teardown];
        
        [SIAlertView setCurrentAlertView:nil];
        
        SIAlertView *nextAlertView;
        NSInteger index = [[SIAlertView sharedQueue] indexOfObject:self];
        if (index != NSNotFound && index < [SIAlertView sharedQueue].count - 1) {
            nextAlertView = [SIAlertView sharedQueue][index + 1];
        }
        
        if (cleanup) {
            [[SIAlertView sharedQueue] removeObject:self];
        }
        
        [SIAlertView setAnimating:NO];
        
        if (isVisible) {
            if (self.didDismissHandler) {
                self.didDismissHandler(self);
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:SIAlertViewDidDismissNotification object:self userInfo:nil];
        }
        
        // check if we should show next alert
        if (!isVisible) {
            return;
        }
        
        if (nextAlertView) {
            [nextAlertView show];
        } else {
            // show last alert view
            if ([SIAlertView sharedQueue].count > 0) {
                SIAlertView *alert = [[SIAlertView sharedQueue] lastObject];
                [alert show];
            }
        }
    };
    
    if (self.inputTextField && self.inputTextField.isFirstResponder)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:NULL];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:NULL];
        
        [self.inputTextField resignFirstResponder];
    }
    
    if (animated && isVisible) {
        [SIAlertView setAnimating:YES];
        [self transitionOutCompletion:dismissComplete];
        
        if ([SIAlertView sharedQueue].count == 1) {
            [SIAlertView hideBackgroundAnimated:YES];
        }
        
    } else {
        dismissComplete();
        
        if ([SIAlertView sharedQueue].count == 0) {
            [SIAlertView hideBackgroundAnimated:YES];
        }
    }
}

#pragma mark - Transitions

- (void)transitionInCompletion:(void(^)(void))completion
{
    switch (self.transitionStyle) {
        case SIAlertViewTransitionStyleSlideFromBottom:
        {
            CGRect rect = self.containerView.frame;
            CGRect originalRect = rect;
            rect.origin.y = self.bounds.size.height;
            self.containerView.frame = rect;
            [UIView animateWithDuration:0.3
                             animations:^{
                                 self.containerView.frame = originalRect;
                             }
                             completion:^(BOOL finished) {
                                 if (completion) {
                                     completion();
                                 }
                             }];
        }
            break;
        case SIAlertViewTransitionStyleSlideFromTop:
        {
            CGRect rect = self.containerView.frame;
            CGRect originalRect = rect;
            rect.origin.y = -rect.size.height;
            self.containerView.frame = rect;
            [UIView animateWithDuration:0.3
                             animations:^{
                                 self.containerView.frame = originalRect;
                             }
                             completion:^(BOOL finished) {
                                 if (completion) {
                                     completion();
                                 }
                             }];
        }
            break;
        case SIAlertViewTransitionStyleFade:
        {
            self.containerView.alpha = 0;
            [UIView animateWithDuration:0.3
                             animations:^{
                                 self.containerView.alpha = 1;
                             }
                             completion:^(BOOL finished) {
                                 if (completion) {
                                     completion();
                                 }
                             }];
        }
            break;
        case SIAlertViewTransitionStyleBounce:
        {
            CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
            animation.values = @[@(0.01), @(1.2), @(0.9), @(1)];
            animation.keyTimes = @[@(0), @(0.4), @(0.6), @(1)];
            animation.timingFunctions = @[[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear], [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear], [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
            animation.duration = 0.5;
            animation.delegate = self;
            [animation setValue:completion forKey:@"handler"];
            [self.containerView.layer addAnimation:animation forKey:@"bouce"];
        }
            break;
        case SIAlertViewTransitionStyleDropDown:
        {
            CGFloat y = self.containerView.center.y;
            CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"position.y"];
            animation.values = @[@(y - self.bounds.size.height), @(y + 20), @(y - 10), @(y)];
            animation.keyTimes = @[@(0), @(0.5), @(0.75), @(1)];
            animation.timingFunctions = @[[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut], [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear], [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
            animation.duration = 0.4;
            animation.delegate = self;
            [animation setValue:completion forKey:@"handler"];
            [self.containerView.layer addAnimation:animation forKey:@"dropdown"];
        }
            break;
        default:
            break;
    }
}

- (void)transitionOutCompletion:(void(^)(void))completion
{
    switch (self.transitionStyle) {
        case SIAlertViewTransitionStyleSlideFromBottom:
        {
            CGRect rect = self.containerView.frame;
            rect.origin.y = self.bounds.size.height;
            [UIView animateWithDuration:0.3
                                  delay:0
                                options:UIViewAnimationOptionCurveEaseIn
                             animations:^{
                                 self.containerView.frame = rect;
                             }
                             completion:^(BOOL finished) {
                                 if (completion) {
                                     completion();
                                 }
                             }];
        }
            break;
        case SIAlertViewTransitionStyleSlideFromTop:
        {
            CGRect rect = self.containerView.frame;
            rect.origin.y = -rect.size.height;
            [UIView animateWithDuration:0.3
                                  delay:0
                                options:UIViewAnimationOptionCurveEaseIn
                             animations:^{
                                 self.containerView.frame = rect;
                             }
                             completion:^(BOOL finished) {
                                 if (completion) {
                                     completion();
                                 }
                             }];
        }
            break;
        case SIAlertViewTransitionStyleFade:
        {
            [UIView animateWithDuration:0.25
                             animations:^{
                                 self.containerView.alpha = 0;
                             }
                             completion:^(BOOL finished) {
                                 if (completion) {
                                     completion();
                                 }
                             }];
        }
            break;
        case SIAlertViewTransitionStyleBounce:
        {
            CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
            animation.values = @[@(1), @(1.2), @(0.01)];
            animation.keyTimes = @[@(0), @(0.4), @(1)];
            animation.timingFunctions = @[[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut], [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
            animation.duration = 0.35;
            animation.delegate = self;
            [animation setValue:completion forKey:@"handler"];
            [self.containerView.layer addAnimation:animation forKey:@"bounce"];
            
            self.containerView.transform = CGAffineTransformMakeScale(0.01, 0.01);
        }
            break;
        case SIAlertViewTransitionStyleDropDown:
        {
            CGPoint point = self.containerView.center;
            point.y += self.bounds.size.height;
            [UIView animateWithDuration:0.3
                                  delay:0
                                options:UIViewAnimationOptionCurveEaseIn
                             animations:^{
                                 self.containerView.center = point;
                                 CGFloat angle = ((CGFloat)arc4random_uniform(100) - 50.f) / 100.f;
                                 self.containerView.transform = CGAffineTransformMakeRotation(angle);
                             }
                             completion:^(BOOL finished) {
                                 if (completion) {
                                     completion();
                                 }
                             }];
        }
            break;
        default:
            break;
    }
}

- (void)resetTransition
{
    [self.containerView.layer removeAllAnimations];
}

#pragma mark - Layout

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self validateLayout];
}

- (void)invalidateLayout
{
    self.layoutDirty = YES;
    [self setNeedsLayout];
}

- (void)validateLayout
{
    if (!self.isLayoutDirty) {
        return;
    }
    self.layoutDirty = NO;
#if DEBUG_LAYOUT
    NSLog(@"%@, %@", self, NSStringFromSelector(_cmd));
#endif
    
    CGFloat contentContainerViewHeight = 0;
    CGFloat buttonContainerViewHeight = 0;
    
    CGFloat y = CONTENT_PADDING_TOP;
	if (self.titleLabel) {
        self.titleLabel.attributedText = self.attributedTitle;
        CGFloat height = [self heightForTitleLabel];
        self.titleLabel.frame = CGRectMake(CONTENT_PADDING_LEFT, y, CONTAINER_WIDTH - CONTENT_PADDING_LEFT * 2, height);
        y += height;
	}
    if (self.messageLabel) {
        if (y > CONTENT_PADDING_TOP) {
            y += GAP;
        }
        self.messageLabel.attributedText = self.attributedMessage;
        CGFloat height = [self heightForMessageLabel];
        self.messageLabel.frame = CGRectMake(CONTENT_PADDING_LEFT, y, CONTAINER_WIDTH - CONTENT_PADDING_LEFT * 2, height);
        y += height + GAP;
    }
    if (self.contentView) {
        if (y > CONTENT_PADDING_TOP) {
            y += GAP;
        }
        CGFloat height = self.contentView.frame.size.height;
        
        self.contentView.frame = CGRectMake(self.contentViewPadding, y, CONTAINER_WIDTH - self.contentViewPadding * 2, height);
        y += height + GAP;
    }
    if(self.inputTextField) {
        if (y > CONTENT_PADDING_TOP) {
            y += GAP;
        }
        CGFloat height = self.inputTextField.frame.size.height == 0.0 ? INPUT_TEXT_HEIGHT : self.inputTextField.frame.size.height;
        self.inputTextField.frame = CGRectMake(CONTENT_PADDING_LEFT, y, CONTAINER_WIDTH - CONTENT_PADDING_LEFT * 2, height);
        y += height;
    }
    contentContainerViewHeight = y;
    
    if (self.items.count > 0) {
        CGMutablePathRef path = CGPathCreateMutable();
        CGFloat lineWidth = 1 / [UIScreen mainScreen].scale;
        
        CGFloat y = 0;
        if (self.items.count == 2 && self.buttonsListStyle == SIAlertViewButtonsListStyleNormal) {
            if (self.buttonsStyle == SIAlertViewButtonsStyleRounded)
            {
                CGFloat width = (CONTAINER_WIDTH - (CONTENT_PADDING_LEFT * 2.0) - 10.0f) * 0.5f;
                CGFloat height = BUTTON_HEIGHT - 10.0f;
                UIButton *button = self.buttons[0];
                button.frame = CGRectMake(0 + CONTENT_PADDING_LEFT, y + 5.0f, width, height);
                button = self.buttons[1];
                button.frame = CGRectMake(CONTENT_PADDING_LEFT + width + 10.0f, y + 5.0f, width, height);
                y += BUTTON_HEIGHT;
            }
            else
            {
                CGFloat width = CONTAINER_WIDTH * 0.5;
                UIButton *button = self.buttons[0];
                button.frame = CGRectMake(0, y, width, BUTTON_HEIGHT);
                button = self.buttons[1];
                button.frame = CGRectMake(0 + width, y, width, BUTTON_HEIGHT);
                CGPathAddRect(path, NULL, CGRectMake(0, y, CONTAINER_WIDTH, lineWidth));
                CGPathAddRect(path, NULL, CGRectMake(width, y, lineWidth, BUTTON_HEIGHT));
                y += BUTTON_HEIGHT;
            }
        } else {
            
            if (self.buttonsStyle == SIAlertViewButtonsStyleRounded)
            {
                for (NSUInteger i = 0; i < self.buttons.count; i++) {
                    CGFloat width = CONTAINER_WIDTH - (CONTENT_PADDING_LEFT * 2.0);
                    CGFloat height = BUTTON_HEIGHT - 10.0f;
                    UIButton *button = self.buttons[i];
                    button.frame = CGRectMake(0 + CONTENT_PADDING_LEFT, y + 5.0f, width, height);
                    y += BUTTON_HEIGHT;
                }
            }
            else
            {
                for (NSUInteger i = 0; i < self.buttons.count; i++) {
                    UIButton *button = self.buttons[i];
                    button.frame = CGRectMake(0, y, CONTAINER_WIDTH, BUTTON_HEIGHT);
                    CGPathAddRect(path, NULL, CGRectMake(0, y, CONTAINER_WIDTH, lineWidth));
                    y += BUTTON_HEIGHT;
                }
            }
        }
        self.lineLayer.path = path;
        CGPathRelease(path);
        
        buttonContainerViewHeight = y;
    }
    
    self.contentContainerView.contentSize = CGSizeMake(CONTAINER_WIDTH, contentContainerViewHeight);
    
    CGFloat availableContentContainerViewHeight = self.bounds.size.height - buttonContainerViewHeight - 10;
    if (buttonContainerViewHeight > 0) {
        availableContentContainerViewHeight -= GAP;
    }
    contentContainerViewHeight = MIN(contentContainerViewHeight, MAX(availableContentContainerViewHeight, 0));
    self.contentContainerView.frame = CGRectMake(0, 0, CONTAINER_WIDTH, contentContainerViewHeight);
    
    CGFloat finalHeight = contentContainerViewHeight;
    
    if (buttonContainerViewHeight > 0) {
        self.buttonContainerView.frame = CGRectMake(0, contentContainerViewHeight + GAP, CONTAINER_WIDTH, buttonContainerViewHeight);
        finalHeight += GAP + buttonContainerViewHeight;
    }
    
    CGFloat left = (self.bounds.size.width - CONTAINER_WIDTH) * 0.5;
    CGFloat top = (self.bounds.size.height - finalHeight) * 0.5;
    self.containerView.transform = CGAffineTransformIdentity;
    self.containerView.frame = CGRectMake(left, top, CONTAINER_WIDTH, finalHeight);
    self.containerView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.containerView.bounds cornerRadius:self.containerView.layer.cornerRadius].CGPath;
}

- (CGFloat)heightForTitleLabel
{
    if (self.titleLabel) {
        CGRect rect = [self.attributedTitle boundingRectWithSize:CGSizeMake(CONTAINER_WIDTH - CONTENT_PADDING_LEFT * 2, CGFLOAT_MAX)
                                                         options:NSStringDrawingUsesLineFragmentOrigin
                                                         context:nil];
        return ceil(rect.size.height);
    }
    return 0;
}

- (CGFloat)heightForMessageLabel
{
    if (self.messageLabel) {
        CGRect rect = [self.attributedMessage boundingRectWithSize:CGSizeMake(CONTAINER_WIDTH - CONTENT_PADDING_LEFT * 2, CGFLOAT_MAX)
                                                           options:NSStringDrawingUsesLineFragmentOrigin
                                                           context:nil];
        return ceil(rect.size.height);
    }
    return 0;
}

#pragma mark - Setup

- (void)setup
{
    [self setupViewHierarchy];
    [self updateTitleLabel];
    [self setupCustomView];
    [self setupInputTextField];
    [self updateMessageLabel];
    [self setupButtons];
    [self setupLineLayer];
}

- (void)teardown
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.containerView removeFromSuperview];
    self.containerView = nil;
    self.titleLabel = nil;
    self.messageLabel = nil;
    
    [self.contentView removeFromSuperview];
    self.contentView = nil;
    
    [self.buttons removeAllObjects];
    self.alertWindow.hidden = YES;
    self.alertWindow = nil;
    self.layoutDirty = NO;
}

- (void)setupViewHierarchy
{
    self.containerView = [[UIView alloc] initWithFrame:self.bounds];
    self.containerView.layer.shadowOffset = CGSizeZero;
    self.containerView.layer.shadowRadius = self.shadowRadius;
    self.containerView.layer.shadowOpacity = self.shadowRadius > 0 ? 0.5 : 0;
    [self addSubview:self.containerView];
    
    self.wrapperView = [[UIView alloc] initWithFrame:self.bounds];
    self.wrapperView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.wrapperView.autoresizesSubviews = NO;
    self.wrapperView.backgroundColor = self.viewBackgroundColor;
    self.wrapperView.layer.cornerRadius = self.cornerRadius;
    self.wrapperView.clipsToBounds = YES;
    //self.wrapperView.backgroundColor = [UIColor redColor];
    [self.containerView addSubview:self.wrapperView];
    
    self.contentContainerView = [[UIScrollView alloc] initWithFrame:self.bounds];
    self.contentContainerView.autoresizesSubviews = NO;
    [self.wrapperView addSubview:self.contentContainerView];
    
    self.buttonContainerView = [[UIView alloc] initWithFrame:self.bounds];
    self.buttonContainerView.autoresizesSubviews = NO;
    [self.wrapperView addSubview:self.buttonContainerView];
}

- (void)setupLineLayer
{
    self.lineLayer = [CAShapeLayer layer];
    self.lineLayer.fillColor = self.seperatorColor.CGColor;

    [self.buttonContainerView.layer addSublayer:self.lineLayer];
}

- (void)updateTitleLabel
{
	if (self.title) {
		if (!self.titleLabel) {
			self.titleLabel = [[UILabel alloc] initWithFrame:self.bounds];
            self.titleLabel.backgroundColor = [UIColor clearColor];
            self.titleLabel.numberOfLines = 0;
			[self.contentContainerView addSubview:self.titleLabel];
#if DEBUG_LAYOUT
            self.titleLabel.backgroundColor = [UIColor redColor];
#endif
		}
		self.titleLabel.attributedText = self.attributedTitle;
	} else {
		[self.titleLabel removeFromSuperview];
		self.titleLabel = nil;
	}
    [self invalidateLayout];
}
- (void)setupCustomView{
    if (self.contentView) {
        
        //self.customView.frame = self.bounds;
        
        [self.contentContainerView addSubview:self.contentView];
#if DEBUG_LAYOUT
        self.customView.backgroundColor = [UIColor redColor];
#endif
    }
    [self invalidateLayout];
}

- (void)setupInputTextField
{
    if (self.alertViewStyle == SIAlertViewStyleTextInput)
    {
        self.inputTextField.delegate = self;
        [self.containerView addSubview:self.inputTextField];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
        
#if DEBUG_LAYOUT
        self.textField.backgroundColor = [UIColor redColor];
#endif
        [self invalidateLayout];
    }
}

- (void)updateMessageLabel
{
    if (self.message) {
        if (!self.messageLabel) {
            self.messageLabel = [[UILabel alloc] initWithFrame:self.bounds];
            self.messageLabel.backgroundColor = [UIColor clearColor];
            self.messageLabel.numberOfLines = 0;
            [self.contentContainerView addSubview:self.messageLabel];
#if DEBUG_LAYOUT
            self.messageLabel.backgroundColor = [UIColor redColor];
#endif
        }
        self.messageLabel.attributedText = self.attributedMessage;
    } else {
        [self.messageLabel removeFromSuperview];
        self.messageLabel = nil;
    }
    [self invalidateLayout];
}

- (void)setupButtons
{
    self.buttons = [[NSMutableArray alloc] initWithCapacity:self.items.count];
    for (NSUInteger i = 0; i < self.items.count; i++) {
        UIButton *button = [self buttonForItemIndex:i];
        [self.buttons addObject:button];
        [self.buttonContainerView addSubview:button];
    }
}

- (UIButton *)buttonForItemIndex:(NSUInteger)index
{
    SIAlertItem *item = self.items[index];
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.tag = index;
	button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    NSDictionary *defaults = nil;
	UIImage *normalImage = nil;
	UIImage *highlightedImage = nil;
    UIColor *borderColor = nil;
	switch (item.type) {
		case SIAlertViewButtonTypeCancel:
            if (self.cancelButtonBackgroundColor) {
                normalImage = [self imageWithUIColor:self.cancelButtonBackgroundColor];
                highlightedImage = [self imageWithUIColor:[self highlightedColorWithColor:self.cancelButtonBackgroundColor]];
                defaults = self.cancelButtonAttributes;
                borderColor = self.cancelButtonBorderColor;
            }
			break;
		case SIAlertViewButtonTypeDestructive:
			if (self.destructiveButtonBackgroundColor) {
                normalImage = [self imageWithUIColor:self.destructiveButtonBackgroundColor];
                highlightedImage = [self imageWithUIColor:[self highlightedColorWithColor:self.destructiveButtonBackgroundColor]];
                defaults = self.destructiveButtonAttributes;
                borderColor = self.destructiveButtonBorderColor;
            }
			break;
		case SIAlertViewButtonTypeDefault:
		default:
			if (self.defaultButtonBackgroundColor) {
                normalImage = [self imageWithUIColor:self.defaultButtonBackgroundColor];
                highlightedImage = [self imageWithUIColor:[self highlightedColorWithColor:self.defaultButtonBackgroundColor]];
                defaults = self.defaultButtonAttributes;
                borderColor = self.defaultButtonBorderColor;
            }
			break;
	}
	[button setBackgroundImage:normalImage forState:UIControlStateNormal];
	[button setBackgroundImage:highlightedImage forState:UIControlStateHighlighted];
	[button addTarget:self action:@selector(buttonAction:) forControlEvents:UIControlEventTouchUpInside];
    
    if (self.buttonsStyle == SIAlertViewButtonsStyleRounded)
    {
        button.layer.masksToBounds = true;
        button.layer.cornerRadius = self.buttonCornerRadius;
        
        if (borderColor)
        {
            button.layer.borderColor = [borderColor CGColor];
            button.layer.borderWidth = self.buttonBorderWidth;
        }
    }
    
    NSAttributedString *title = item.attributedTitle ? item.attributedTitle : [[NSAttributedString alloc] initWithString:item.title attributes:[self tintedAttributes:defaults]];
    [button setAttributedTitle:title forState:UIControlStateNormal];
    
    return button;
}

#pragma mark - Actions

- (void)buttonAction:(UIButton *)button
{
	[SIAlertView setAnimating:YES]; // set this flag to YES in order to prevent showing another alert in action block
    SIAlertItem *item = self.items[button.tag];
	if (item.action) {
		item.action(self);
	}
	[self dismissAnimated:YES];
}

#pragma mark - CAAnimation delegate

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
    void(^completion)(void) = [anim valueForKey:@"handler"];
    if (completion) {
        completion();
    }
}

#pragma mark - Helpers

// auto detected darken or lighten
- (UIColor *)highlightedColorWithColor:(UIColor *)color
{
    CGFloat hue;
    CGFloat saturation;
    CGFloat brightness;
    CGFloat alpha;
    CGFloat adjustment = 0.1;
    
    int numComponents = CGColorGetNumberOfComponents([color CGColor]);
    
    // grayscale
    if (numComponents == 2) {
        [color getWhite:&brightness alpha:&alpha];
        brightness += brightness > 0.5 ? -adjustment : adjustment * 2; // emphasize lighten adjustment value by two
        if (alpha < 0.5) {
            alpha += adjustment;
        }
        return [UIColor colorWithWhite:brightness alpha:alpha];
    }
    
    // RGBA
    [color getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
    brightness += brightness > 0.5 ? -adjustment : adjustment * 2;
    if (alpha < 0.5) {
        alpha += adjustment;
    }
    
    return [UIColor colorWithHue:hue saturation:saturation brightness:brightness alpha:alpha];
}

- (UIImage *)imageWithUIColor:(UIColor *)color
{
    CGRect rect = CGRectMake(0, 0, 1, 1);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0);
    [color set];
    UIRectFill(rect);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (NSDictionary *)tintedAttributes:(NSDictionary *)attributes
{
    if (!attributes[NSForegroundColorAttributeName]) {
        NSMutableDictionary *temp = [attributes mutableCopy];
        temp[NSForegroundColorAttributeName] = self.tintColor;
        attributes = [temp copy];
    }
    return attributes;
}

#pragma mark - UITextField delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    
    bool buttonAction = false;
    if ([self.items count] == 1)
    {
        [self buttonAction:self.buttons[0]];
        buttonAction = true;
    }
    
    if (!buttonAction)
    {
        for (NSUInteger i = 0; i < self.buttons.count; i++)
        {
            if (((SIAlertItem *)self.items[i]).type == SIAlertViewButtonTypeDefault)
            {
                [self buttonAction:self.buttons[i]];
                buttonAction = true;
            }
        }
    }
    
    return YES;
}

#pragma mark - Keyboard actions

- (void)keyboardWillShow:(NSNotification*) notification
{
    NSDictionary* info = [notification userInfo];
    
    CGRect kbFrame = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    kbFrame = [[self.containerView superview] convertRect:kbFrame fromView:nil];
    CGSize kbSize = kbFrame.size;
    
    CGFloat height = self.containerView.frame.size.height;
    CGFloat top = (self.bounds.size.height - kbSize.height - height) * 0.5;
    top = MAX(top, 0.0f);
    
    [UIView animateWithDuration:0.25f animations:^{
        CGRect frame = self.containerView.frame;
        frame.origin.y = top;
        self.containerView.frame = frame;
    }];
}

- (void)keyboardWillHide:(NSNotification*) notification
{
    CGFloat height = self.containerView.frame.size.height;
    CGFloat top = (self.bounds.size.height - height) * 0.5;
    
    [UIView animateWithDuration:0.25f animations:^{
        CGRect frame = self.containerView.frame;
        frame.origin.y = top;
        self.containerView.frame = frame;
    }];
}

#pragma mark - UIAppearance setters

- (void)setViewBackgroundColor:(UIColor *)viewBackgroundColor
{
    if (_viewBackgroundColor == viewBackgroundColor) {
        return;
    }
    _viewBackgroundColor = viewBackgroundColor;
    self.wrapperView.backgroundColor = viewBackgroundColor;
}

- (void)setSeperatorColor:(UIColor *)seperatorColor
{
    if (_seperatorColor == seperatorColor) {
        return;
    }
    _seperatorColor = seperatorColor;
    self.lineLayer.fillColor = seperatorColor.CGColor;
}

- (void)setCornerRadius:(CGFloat)cornerRadius
{
    if (_cornerRadius == cornerRadius) {
        return;
    }
    _cornerRadius = cornerRadius;
    self.wrapperView.layer.cornerRadius = cornerRadius;
}

- (void)setShadowRadius:(CGFloat)shadowRadius
{
    if (_shadowRadius == shadowRadius) {
        return;
    }
    _shadowRadius = shadowRadius;
    self.containerView.layer.shadowRadius = shadowRadius;
    self.containerView.layer.shadowOpacity = shadowRadius > 0 ? 0.5 : 0;
}

- (UIColor *)defaultButtonBackgroundColor
{
    if (!_defaultButtonBackgroundColor) {
        return [[[self class] appearance] defaultButtonBackgroundColor];
    }
    return _defaultButtonBackgroundColor;
}

- (UIColor *)cancelButtonBackgroundColor
{
    if (!_cancelButtonBackgroundColor) {
        return [[[self class] appearance] cancelButtonBackgroundColor];
    }
    return _cancelButtonBackgroundColor;
}

- (CGFloat) contentViewPadding
{
    if (_contentViewPadding != [[[self class] appearance] contentViewPadding])
    {
        return _contentViewPadding;
    }
    
    return [[[self class] appearance] contentViewPadding];
}

- (UIColor *)destructiveButtonBackgroundColor
{
    if (!_destructiveButtonBackgroundColor) {
        return [[[self class] appearance] destructiveButtonBackgroundColor];
    }
    return _destructiveButtonBackgroundColor;
}

- (CGFloat) buttonCornerRadius
{
    if (_buttonCornerRadius != [[[self class] appearance] buttonCornerRadius])
    {
        return _buttonCornerRadius;
    }
    
    return [[[self class] appearance] buttonCornerRadius];
}

- (CGFloat) buttonBorderWidth
{
    if (_buttonBorderWidth != [[[self class] appearance] buttonBorderWidth])
    {
        return _buttonBorderWidth;
    }
    
    return [[[self class] appearance] buttonBorderWidth];
}

- (UIColor *)defaultButtonBorderColor
{
    if (!_defaultButtonBorderColor) {
        return [[[self class] appearance] defaultButtonBorderColor];
    }
    return _defaultButtonBorderColor;
}

- (UIColor *)cancelButtonBorderColor
{
    if (!_cancelButtonBorderColor) {
        return [[[self class] appearance] cancelButtonBorderColor];
    }
    return _cancelButtonBorderColor;
}

- (UIColor *)destructiveButtonBorderColor
{
    if (!_destructiveButtonBorderColor) {
        return [[[self class] appearance] destructiveButtonBorderColor];
    }
    return _destructiveButtonBorderColor;
}

- (NSDictionary *)titleAttributes
{
    if (!_titleAttributes) {
        return [[[self class] appearance] titleAttributes];
    }
    return _titleAttributes;
}

- (NSDictionary *)messageAttributes
{
    if (!_messageAttributes) {
        return [[[self class] appearance] messageAttributes];
    }
    return _messageAttributes;
}

- (NSDictionary *)defaultButtonAttributes
{
    NSDictionary *attributes = _defaultButtonAttributes;
    if (!attributes) {
        attributes = [[[self class] appearance] defaultButtonAttributes];
    }
    return attributes;
}

- (NSDictionary *)cancelButtonAttributes
{
    NSDictionary *attributes = _cancelButtonAttributes;
    if (!attributes) {
        attributes = [[[self class] appearance] cancelButtonAttributes];
    }
    return attributes;
}

- (NSDictionary *)destructiveButtonAttributes
{
    NSDictionary *attributes = _destructiveButtonAttributes;
    if (!attributes) {
        attributes = [[[self class] appearance] destructiveButtonAttributes];
    }
    return attributes;
}

# pragma mark -
# pragma mark Enable parallax effect (iOS7 only)

#ifdef __IPHONE_7_0
- (void)addParallaxEffect
{
    if (self.parallaxEffectEnabled && NSClassFromString(@"UIInterpolatingMotionEffect"))
    {
        UIInterpolatingMotionEffect *effectHorizontal = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"position.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
        UIInterpolatingMotionEffect *effectVertical = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"position.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
        [effectHorizontal setMaximumRelativeValue:@(20.0f)];
        [effectHorizontal setMinimumRelativeValue:@(-20.0f)];
        [effectVertical setMaximumRelativeValue:@(50.0f)];
        [effectVertical setMinimumRelativeValue:@(-50.0f)];
        [self.containerView addMotionEffect:effectHorizontal];
        [self.containerView addMotionEffect:effectVertical];
    }
}

- (void)removeParallaxEffect
{
    if (self.parallaxEffectEnabled && NSClassFromString(@"UIInterpolatingMotionEffect"))
    {
        [self.containerView.motionEffects enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [self.containerView removeMotionEffect:obj];
        }];
    }
}
#endif

@end
