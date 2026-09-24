// Player redesign: Apple Music style landscape mode for iOS.
// In landscape orientation (width > height), the player splits cleanly into two panes:
// - Left pane: Full-size album artwork with continuous rounded corners and shadow, vertically centered.
// - Right pane: Track metadata (Title, Artist), scrubber, playback controls, volume, and footer.
// When lyrics are opened in landscape, SGRKaraokeView smoothly populates the right pane next to
// the artwork, matching the Apple Music landscape layout.
//
// Autorotation is only active when Now Playing is open on screen, matching Apple Music on iPhone
// (Home, Library, Search and Playlists remain strictly in portrait).
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"

static char kLandscapeKey, kGrabberKey;
static BOOL sg_nowPlayingOpen = NO;

BOOL SGRPlayerIsLandscape(UIView *host) {
    if (!host) return NO;
    return host.bounds.size.width > host.bounds.size.height;
}

CGRect SGRPlayerLandscapeCoverFrame(UIView *host) {
    if (!host || !SGRPlayerIsLandscape(host)) return CGRectNull;
    UIEdgeInsets insets = host.safeAreaInsets;
    CGFloat W = host.bounds.size.width, H = host.bounds.size.height;
    CGFloat left = MAX(insets.left, 24);
    CGFloat top = MAX(insets.top, 16), bottom = MAX(insets.bottom, 16);
    CGFloat availH = H - top - bottom;
    CGFloat availWLeft = (W / 2) - left - 16;
    CGFloat coverSize = MIN(availH - 24, availWLeft);
    coverSize = MIN(coverSize, 340);
    CGFloat coverX = left + (availWLeft - coverSize) / 2;
    CGFloat coverY = top + (availH - coverSize) / 2;
    return CGRectMake(round(coverX), round(coverY), round(coverSize), round(coverSize));
}

CGRect SGRPlayerLandscapeRightPaneFrame(UIView *host) {
    if (!host || !SGRPlayerIsLandscape(host)) return CGRectNull;
    UIEdgeInsets insets = host.safeAreaInsets;
    CGFloat W = host.bounds.size.width, H = host.bounds.size.height;
    CGFloat right = MAX(insets.right, 24);
    CGFloat top = MAX(insets.top, 16), bottom = MAX(insets.bottom, 16);
    CGFloat availH = H - top - bottom;
    CGRect coverFrame = SGRPlayerLandscapeCoverFrame(host);
    CGFloat rightX = MAX(W / 2 + 12, CGRectGetMaxX(coverFrame) + 32);
    CGFloat rightW = (W - right) - rightX;
    return CGRectMake(round(rightX), round(top + 8), round(rightW), round(availH - 16));
}

static void updateGrabber(UIView *host, BOOL isLandscape) {
    UIView *grabber = objc_getAssociatedObject(host, &kGrabberKey);
    if (!grabber) {
        grabber = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 36, 5)];
        grabber.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.35];
        grabber.layer.cornerRadius = 2.5;
        grabber.layer.cornerCurve = kCACornerCurveContinuous;
        grabber.userInteractionEnabled = NO;
        objc_setAssociatedObject(host, &kGrabberKey, grabber, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (isLandscape) {
        if (grabber.superview != host) [host addSubview:grabber];
        UIEdgeInsets insets = host.safeAreaInsets;
        grabber.center = CGPointMake(CGRectGetMidX(host.bounds), MAX(insets.top, 8) + 6);
        grabber.hidden = NO;
    } else {
        grabber.hidden = YES;
    }
}

static void layoutLandscape(UIView *host) {
    BOOL isLandscape = SGRPlayerIsLandscape(host);
    updateGrabber(host, isLandscape);
    if (!isLandscape) return;

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
        if ([bottomStack isKindOfClass:[UIStackView class]]) {
            UIStackView *stack = (UIStackView *)bottomStack;
            stack.distribution = UIStackViewDistributionEqualSpacing;
        }
    }

    UIView *header = SGRFindByIdentifier(host, @"now-playing-minimize-button", NULL);
    if (header && header.superview) {
        header.superview.alpha = isLandscape ? 0 : 1;
    }
}

static UIInterfaceOrientationMask sgr_supportedOrientations(id self, SEL _cmd) {
    if (sg_nowPlayingOpen) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

static BOOL sgr_shouldAutorotate(id self, SEL _cmd) {
    return YES;
}

static void swizzleViewControllerOrientations(void) {
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
    return sgr_supportedOrientations(self, _cmd);
}

%end

%hook _TtC19NowPlaying_ViewImpl24NowPlayingViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    sg_nowPlayingOpen = YES;
    if (@available(iOS 16.0, *)) {
        [self setNeedsUpdateOfSupportedInterfaceOrientations];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sg_nowPlayingOpen = YES;
    if (@available(iOS 16.0, *)) {
        [self setNeedsUpdateOfSupportedInterfaceOrientations];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    sg_nowPlayingOpen = NO;
    if (@available(iOS 16.0, *)) {
        [self setNeedsUpdateOfSupportedInterfaceOrientations];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    sg_nowPlayingOpen = NO;
    if (@available(iOS 16.0, *)) {
        [self setNeedsUpdateOfSupportedInterfaceOrientations];
    }
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (host) {
        layoutLandscape(host);
    }
}

%end

%hook UIApplication

- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return sgr_supportedOrientations(self, _cmd);
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
    return sgr_supportedOrientations(self, _cmd);
}

%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    dispatch_async(dispatch_get_main_queue(), ^{
        swizzleViewControllerOrientations();
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
