#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "SGDuo.h"

BOOL SGIsDuoDevice(void) {
    UIScreen *screen = [UIScreen mainScreen];
    CGFloat scale = screen.scale ?: 1.0;
    CGSize native = screen.nativeBounds.size;
    if (scale <= 0) return NO;
    CGFloat widthPt = native.width / scale;
    CGFloat heightPt = native.height / scale;
    CGFloat minDim = MIN(widthPt, heightPt);
    // iPhone Duo outer cover: 1398x2034 @3x (~466 pt wide)
    // iPhone Duo inner display: 1878x2670 @3x (~626 pt wide)
    // Standard iPhones are 375-430 pt wide.
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        if (minDim >= 445.0) return YES;
    }
    return NO;
}

static CGFloat trueNativeWidth(UIScreen *screen) {
    if (!screen) screen = [UIScreen mainScreen];
    CGFloat scale = screen.scale ?: 1.0;
    if (scale <= 0) return 0;
    return screen.nativeBounds.size.width / scale;
}

static CGFloat trueNativeHeight(UIScreen *screen) {
    if (!screen) screen = [UIScreen mainScreen];
    CGFloat scale = screen.scale ?: 1.0;
    if (scale <= 0) return 0;
    return screen.nativeBounds.size.height / scale;
}

%hook UIScreen
- (CGRect)bounds {
    CGRect b = %orig;
    CGFloat trueW = trueNativeWidth(self);
    CGFloat trueH = trueNativeHeight(self);
    if (trueW > b.size.width + 5.0) {
        b.size.width = trueW;
    }
    if (trueH > b.size.height + 5.0 && b.size.height < trueH - 20.0) {
        b.size.height = trueH;
    }
    return b;
}

- (CGRect)_screenBounds {
    CGRect b = %orig;
    CGFloat trueW = trueNativeWidth(self);
    if (trueW > b.size.width + 5.0) {
        b.size.width = trueW;
    }
    return b;
}

- (CGRect)_referenceBounds {
    CGRect b = %orig;
    CGFloat trueW = trueNativeWidth(self);
    if (trueW > b.size.width + 5.0) {
        b.size.width = trueW;
    }
    return b;
}
%end

%hook UIWindow
- (void)setFrame:(CGRect)frame {
    UIScreen *screen = self.screen ?: [UIScreen mainScreen];
    CGFloat trueW = trueNativeWidth(screen);
    if (trueW > frame.size.width + 5.0 && frame.origin.x <= 0) {
        frame.size.width = trueW;
    }
    %orig(frame);
}

- (void)setBounds:(CGRect)bounds {
    UIScreen *screen = self.screen ?: [UIScreen mainScreen];
    CGFloat trueW = trueNativeWidth(screen);
    if (trueW > bounds.size.width + 5.0 && bounds.origin.x <= 0) {
        bounds.size.width = trueW;
    }
    %orig(bounds);
}

- (void)layoutSubviews {
    %orig;
    UIScreen *screen = self.screen ?: [UIScreen mainScreen];
    CGFloat trueW = trueNativeWidth(screen);
    if (trueW > 0 && self.bounds.size.width < trueW - 5.0 && self.frame.origin.x <= 0) {
        CGRect f = self.frame;
        f.size.width = trueW;
        [self setFrame:f];
    }
}
%end

%hook UIViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIWindow *w = self.view.window;
    if (w && self.parentViewController == nil) {
        if (self.view.bounds.size.width < w.bounds.size.width) {
            CGRect f = self.view.frame;
            f.size.width = w.bounds.size.width;
            self.view.frame = f;
        }
    }
}
%end

%ctor {
    %init;
}
