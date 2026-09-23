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
static BOOL sg_playerPresented = NO;

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

    // Reposition cover list / tilt view in the left pane
    UIView *coverList = SGRPlayerCoverList();
    if (coverList) {
        coverList.frame = coverFrame;
    }

    // Locate the bottom stack view and arrange its views in the right pane
    UIView *bottomStack = SGRFindByIdentifier(host, @"npv.bottomStackView", &kLandscapeKey);
    if (bottomStack) {
        bottomStack.frame = rightPane;
    }
}

%hook _TtC19NowPlaying_ViewImpl24NowPlayingViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    sg_playerPresented = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    sg_playerPresented = NO;
    %orig;
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
    if (host && SGRPlayerIsLandscape(host)) {
        layoutLandscape(host);
    }
}

%end

%hook UIApplication

- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    if (sg_playerPresented) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return %orig;
}

%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC19NowPlaying_ViewImpl24NowPlayingViewController",
    ]);
}
