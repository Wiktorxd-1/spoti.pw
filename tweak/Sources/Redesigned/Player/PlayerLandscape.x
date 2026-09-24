// Player redesign: Apple Music style landscape mode for iOS.
// In landscape orientation (width > height), the player splits cleanly into two panes:
// - Left pane: Full-size album artwork with continuous rounded corners and shadow, vertically centered.
// - Right pane: Track metadata (Title, Artist), scrubber, playback controls, volume, and footer.
// When lyrics are opened in landscape, SGRKaraokeView smoothly populates the right pane next to
// the artwork, matching the Apple Music landscape layout.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"

static char kLandscapeKey;

BOOL SGRPlayerIsLandscape(UIView *host) {
    if (!host) return NO;
    return host.bounds.size.width > host.bounds.size.height;
}

CGRect SGRPlayerLandscapeCoverFrame(UIView *host) {
    if (!host || !SGRPlayerIsLandscape(host)) return CGRectNull;
    UIEdgeInsets insets = host.safeAreaInsets;
    CGFloat W = host.bounds.size.width, H = host.bounds.size.height;
    CGFloat left = MAX(insets.left, 24), right = MAX(insets.right, 24);
    CGFloat top = MAX(insets.top, 16), bottom = MAX(insets.bottom, 16);
    CGFloat availH = H - top - bottom;
    CGFloat coverSize = MIN(availH - 16, (W - left - right) * 0.44);
    return CGRectMake(left + 12, top + (availH - coverSize) / 2, coverSize, coverSize);
}

CGRect SGRPlayerLandscapeRightPaneFrame(UIView *host) {
    if (!host || !SGRPlayerIsLandscape(host)) return CGRectNull;
    UIEdgeInsets insets = host.safeAreaInsets;
    CGFloat W = host.bounds.size.width, H = host.bounds.size.height;
    CGFloat right = MAX(insets.right, 24);
    CGFloat top = MAX(insets.top, 16), bottom = MAX(insets.bottom, 16);
    CGFloat availH = H - top - bottom;
    CGRect coverFrame = SGRPlayerLandscapeCoverFrame(host);
    CGFloat rightX = CGRectGetMaxX(coverFrame) + 32;
    CGFloat rightW = (W - right) - rightX;
    return CGRectMake(rightX, top, rightW, availH);
}

static void layoutLandscape(UIView *host) {
    if (!host || !SGRPlayerIsLandscape(host)) return;
    CGRect coverFrame = SGRPlayerLandscapeCoverFrame(host);
    CGRect rightPane = SGRPlayerLandscapeRightPaneFrame(host);
    if (CGRectIsEmpty(coverFrame) || CGRectIsEmpty(rightPane)) return;

    UIView *coverList = SGRPlayerCoverList();
    if (coverList) {
        coverList.frame = coverFrame;
    }

    UIView *bottomStack = SGRFindByIdentifier(host, @"npv.bottomStackView", &kLandscapeKey);
    if (bottomStack) {
        bottomStack.frame = rightPane;
    }
}

%hook UIViewController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

%end

%hook _TtC19NowPlaying_ViewImpl24NowPlayingViewController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (host && SGRPlayerIsLandscape(host)) {
        layoutLandscape(host);
    }
}

%end

static UIInterfaceOrientationMask custom_supportedOrientations(id self, SEL _cmd, UIApplication *app, UIWindow *win) {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

static void swizzleAppDelegate(id<UIApplicationDelegate> delegate) {
    if (!delegate) return;
    Class cls = [delegate class];
    SEL sel = @selector(application:supportedInterfaceOrientationsForWindow:);
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        method_setImplementation(m, (IMP)custom_supportedOrientations);
    } else {
        class_addMethod(cls, sel, (IMP)custom_supportedOrientations, "Q@:@@");
    }
}

%hook UIApplication

- (void)setDelegate:(id<UIApplicationDelegate>)delegate {
    %orig;
    swizzleAppDelegate(delegate);
}

%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    if (UIApplication.sharedApplication.delegate) {
        swizzleAppDelegate(UIApplication.sharedApplication.delegate);
    }
    SGRequireClasses(@[
        @"_TtC19NowPlaying_ViewImpl24NowPlayingViewController",
    ]);
}
