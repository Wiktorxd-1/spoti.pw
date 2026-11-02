#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "AnimatedBoot.h"

@interface SGAnimatedSplashView : UIView
@end

@implementation SGAnimatedSplashView {
    UIView *_glow;
    UIImageView *_icon;
    BOOL _dismissed;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = UIColor.blackColor;
        self.userInteractionEnabled = NO;

        _glow = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 180, 180)];
        _glow.center = CGPointMake(frame.size.width / 2.0, frame.size.height / 2.0);
        _glow.layer.cornerRadius = 90;
        _glow.backgroundColor = [UIColor colorWithRed:0.11 green:0.84 blue:0.38 alpha:0.25];
        _glow.layer.masksToBounds = NO;
        _glow.alpha = 0.0;
        _glow.transform = CGAffineTransformMakeScale(0.5, 0.5);
        [self addSubview:_glow];

        _icon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 96, 96)];
        _icon.center = CGPointMake(frame.size.width / 2.0, frame.size.height / 2.0);
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.tintColor = [UIColor colorWithRed:0.11 green:0.84 blue:0.38 alpha:1.0];

        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:76 weight:UIImageSymbolWeightSemibold];
        UIImage *img = [UIImage systemImageNamed:@"wave.3.forward.circle.fill" withConfiguration:config];
        if (!img) img = [UIImage systemImageNamed:@"music.note" withConfiguration:config];
        _icon.image = img;
        _icon.alpha = 0.0;
        _icon.transform = CGAffineTransformMakeScale(0.72, 0.72);
        [self addSubview:_icon];
    }
    return self;
}

- (void)startAnimation {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback prepare];

    [UIView animateWithDuration:0.55 delay:0.05 usingSpringWithDamping:0.75 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self->_icon.alpha = 1.0;
        self->_icon.transform = CGAffineTransformIdentity;
        self->_glow.alpha = 0.9;
        self->_glow.transform = CGAffineTransformMakeScale(1.2, 1.2);
    } completion:^(BOOL finished) {
        [feedback impactOccurred];
        [self pulseAndDismiss];
    }];
}

- (void)pulseAndDismiss {
    [UIView animateWithDuration:0.45 delay:0.25 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self->_glow.transform = CGAffineTransformMakeScale(1.4, 1.4);
        self->_glow.alpha = 0.4;
    } completion:^(BOOL finished) {
        [self dismiss];
    }];
}

- (void)dismiss {
    if (_dismissed) return;
    _dismissed = YES;

    [UIView animateWithDuration:0.4 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.alpha = 0.0;
        self->_icon.transform = CGAffineTransformMakeScale(1.18, 1.18);
        self->_glow.transform = CGAffineTransformMakeScale(1.8, 1.8);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

@end

static UIWindow *sg_splashWindow;

void SGShowAnimatedSplash(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!SGFlag(SGKeyAnimatedSplash, YES)) return;

        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        if (!scene) {
            for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
                if ([s isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)s; break; }
            }
        }

        CGRect bounds = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
        UIWindow *window = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:bounds];
        window.windowLevel = UIWindowLevelStatusBar + 50;
        window.backgroundColor = UIColor.clearColor;
        window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

        UIViewController *root = [UIViewController new];
        root.view.backgroundColor = UIColor.clearColor;
        window.rootViewController = root;

        SGAnimatedSplashView *splash = [[SGAnimatedSplashView alloc] initWithFrame:bounds];
        splash.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [root.view addSubview:splash];

        window.hidden = NO;
        [window makeKeyAndVisible];
        sg_splashWindow = window;

        [splash startAnimation];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [splash dismiss];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                sg_splashWindow.hidden = YES;
                sg_splashWindow = nil;
            });
        });
    });
}

%hook _TtC19Home_FunkisPageImpl20FunkisViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGShowAnimatedSplash();
        });
    });
}
%end

%ctor {
    if (!SGFlag(SGKeyAnimatedSplash, YES)) return;
    %init;
}
