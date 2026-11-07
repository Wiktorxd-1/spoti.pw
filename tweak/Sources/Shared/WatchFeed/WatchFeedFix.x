#import <UIKit/UIKit.h>
#import "Core/SGCore.h"

static BOOL sg_watchFeedActive = NO;
static NSTimeInterval sg_watchFeedActivatedAt = 0;

static BOOL isWatchFeedName(NSString *name) {
    return [name containsString:@"WatchFeed"] || [name containsString:@"EntityExplorer"];
}

static BOOL isWatchFeedOnScreen(void) {
    UIViewController *top = SGTopController();
    for (UIViewController *vc = top; vc; vc = vc.presentingViewController) {
        if (isWatchFeedName(NSStringFromClass(vc.class))) return YES;
    }
    return NO;
}

%hook UIControl
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    if ([self.accessibilityIdentifier containsString:@"WatchFeedEntityExplorerButton"]) {
        sg_watchFeedActive = YES;
        sg_watchFeedActivatedAt = [NSDate timeIntervalSinceReferenceDate];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!isWatchFeedOnScreen()) {
                sg_watchFeedActive = NO;
            }
        });
    }
    %orig;
}
%end

%hook UIViewController
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
    if (viewControllerToPresent && isWatchFeedName(NSStringFromClass(viewControllerToPresent.class))) {
        sg_watchFeedActive = YES;
        sg_watchFeedActivatedAt = [NSDate timeIntervalSinceReferenceDate];
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            viewControllerToPresent.modalPresentationStyle = UIModalPresentationFullScreen;
        }
    }
    %orig(viewControllerToPresent, flag, completion);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (isWatchFeedName(NSStringFromClass(self.class))) {
        sg_watchFeedActive = YES;
        sg_watchFeedActivatedAt = [NSDate timeIntervalSinceReferenceDate];
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            self.modalPresentationStyle = UIModalPresentationFullScreen;
            UITraitCollection *compact = [UITraitCollection traitCollectionWithHorizontalSizeClass:UIUserInterfaceSizeClassCompact];
            UITraitCollection *phone = [UITraitCollection traitCollectionWithUserInterfaceIdiom:UIUserInterfaceIdiomPhone];
            self.overrideTraitCollection = [UITraitCollection traitCollectionWithTraitsFromCollections:@[self.traitCollection ?: [UITraitCollection currentTraitCollection], compact, phone]];
        }
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (isWatchFeedName(NSStringFromClass(self.class))) {
        if (!isWatchFeedOnScreen()) {
            sg_watchFeedActive = NO;
        }
    }
}
%end

%hook UIDevice
- (UIUserInterfaceIdiom)userInterfaceIdiom {
    if (sg_watchFeedActive) {
        if ([NSDate timeIntervalSinceReferenceDate] - sg_watchFeedActivatedAt < 10.0 || isWatchFeedOnScreen()) {
            return UIUserInterfaceIdiomPhone;
        } else {
            sg_watchFeedActive = NO;
        }
    }
    return %orig;
}
%end

%ctor {
    %init;
}
