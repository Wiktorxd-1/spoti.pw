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

static UIInterfaceOrientationMask sgr_supportedOrientations(id self, SEL _cmd) {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

static BOOL sgr_shouldAutorotate(id self, SEL _cmd) {
    return YES;
}

static void swizzleAllViewControllerClasses(void) {
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses <= 0) return;
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);
    Class vcClass = [UIViewController class];
    SEL suppSel = @selector(supportedInterfaceOrientations);
    SEL autoSel = @selector(shouldAutorotate);

    for (int i = 0; i < numClasses; i++) {
        Class cls = classes[i];
        if (cls && class_getSuperclass(cls) && [cls isSubclassOfClass:vcClass]) {
            unsigned int count = 0;
            Method *methods = class_copyMethodList(cls, &count);
            if (methods) {
                for (unsigned int m = 0; m < count; m++) {
                    SEL s = method_getName(methods[m]);
                    if (s == suppSel) {
                        method_setImplementation(methods[m], (IMP)sgr_supportedOrientations);
                    } else if (s == autoSel) {
                        method_setImplementation(methods[m], (IMP)sgr_shouldAutorotate);
                    }
                }
                free(methods);
            }
        }
    }
    free(classes);
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

%hook UIApplication

- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)setDelegate:(id<UIApplicationDelegate>)delegate {
    %orig;
    if (delegate) {
        Class cls = [delegate class];
        SEL sel = @selector(application:supportedInterfaceOrientationsForWindow:);
        Method m = class_getInstanceMethod(cls, sel);
        if (m) {
            method_setImplementation(m, (IMP)sgr_supportedOrientations);
        } else {
            class_addMethod(cls, sel, (IMP)sgr_supportedOrientations, "Q@:@@");
        }
    }
}

%end

%hook UIWindow

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    dispatch_async(dispatch_get_main_queue(), ^{
        swizzleAllViewControllerClasses();
        id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
        if (delegate) {
            Class cls = [delegate class];
            SEL sel = @selector(application:supportedInterfaceOrientationsForWindow:);
            Method m = class_getInstanceMethod(cls, sel);
            if (m) {
                method_setImplementation(m, (IMP)sgr_supportedOrientations);
            } else {
                class_addMethod(cls, sel, (IMP)sgr_supportedOrientations, "Q@:@@");
            }
        }
    });
    SGRequireClasses(@[
        @"_TtC19NowPlaying_ViewImpl24NowPlayingViewController",
    ]);
}
