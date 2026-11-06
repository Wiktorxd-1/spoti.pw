// Home redesign: the header the way the Music app has it. The filter pills (All, Music, Podcasts) go and
// a large title takes their place beside the avatar, which keeps the leading edge the way the Library
// header has it; the scrim Spotify lays behind the header goes too, the soft scroll edge (Kit/SGREdgeEffect.x)
// being what keeps the title clear of the page scrolling under it, as on every other redesigned page.
//
// Tree (9.1.90, recorded 2026-10-26): FunkisViewController's view holds a 402x112 UIView around
// Reprise_LiquidGlassKit LiquidGlass.GradientView (the scrim) and, at {0, 62}, an
// ElementView<HomeHeaderElement> 402x50 holding HomeHeaderView > UIStackView {0, 8} 402x34 of two arranged
// views and the avatar's button: from 9.1.90 the side drawer button (id=Components.UI.SideDrawerButton,
// a11y "Your profile and settings") is a LegacyUI_ECMCoreKit EncoreButton 32x34 that carries the pulse,
// the photo and the badge inside it, all its own; Spotify renamed its class from AdaptiveFaceContainer,
// so the avatar is found by its identifier. The second arranged view is
// LiquidGlass.LeadingFadeMaskView {48, 1} 354x32 around Home_PillUIKit.PillScrollView.
//
// The avatar sits at the leading edge by the stack's layout direction rather than by a frame of ours. Left
// to right, the stack lays its first view out at the leading edge itself on every pass, whatever width the
// button takes when friends listening show inside it; its margin, 16pt, is the one Spotify gives the header
// in a left to right language. The pills stay in the stack with no alpha rather than hidden, the way the
// redesign takes any view out of a stack Spotify arranges (Kit/SGRRestyle.h).
//
// The title is Spotify's own name for the tab, read off its tab bar item (id=TabBar.Item.Home, 10.txt:3100),
// so it follows the app's language.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Shared/Duo/SGDuo.h"
#import "Home.h"

// Tries at finding the tab's name before settling for the English one: a miss walks the window.
static const NSUInteger kTitleTries = 8;

static char kTitleKey, kTabKey, kStackWatchedKey, kLayoutKey;
static __weak UILabel *sg_title;
static __weak UIView *sg_face;
static UIVisualEffectView *sg_bar;
static CAGradientLayer *sg_barMask, *sg_barTint;
static CGFloat sg_scrollProgress;
// How far the page scrolls before the big title and the avatar are gone and the bar is fully in.
static const CGFloat kFadeDistance = 48;
static NSString *sg_tabName;

static void vanish(UIView *view) {
    if (!view) return;
    if (view.alpha != 0) view.alpha = 0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static UIView *childNamed(UIView *host, NSString *marker) {
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) containsString:marker]) return sub;
    }
    return nil;
}

static NSString *tabName(UIWindow *window) {
    if (sg_tabName || !window) return sg_tabName ?: @"Home";
    static NSUInteger tries;
    if (tries >= kTitleTries) return @"Home";
    tries++;
    UIView *item = SGRFindByIdentifier(window, @"TabBar.Item.Home", &kTabKey);
    __block NSString *name = nil;
    if (item) SGForEachView(item, ^(UIView *v) {
        if (!name && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) name = ((UILabel *)v).text;
    });
    if (!name) {
        if (tries == kTitleTries) SGLog(@"redesign home: the Home tab's name not found, the title stays English");
        return @"Home";
    }
    sg_tabName = [name copy];
    SGLog(@"redesign home: title \"%@\" from the tab bar", sg_tabName);
    return sg_tabName;
}

static UILabel *titleIn(UIView *header) {
    UILabel *title = objc_getAssociatedObject(header, &kTitleKey);
    if (!title) {
        title = [UILabel new];
        title.textColor = SGRPrimary();
        title.accessibilityTraits = UIAccessibilityTraitHeader;
        title.adjustsFontSizeToFitWidth = YES;
        title.minimumScaleFactor = 0.6;
        title.userInteractionEnabled = NO;
        objc_setAssociatedObject(header, &kTitleKey, title, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (title.superview != header) [header addSubview:title];
    return title;
}

// The header's views, found once: the page lays out again as it appears, and the walk names classes.
static __weak UIView *sg_header;
static __weak UIStackView *sg_stack;
static __weak UIView *sg_scrim;

static BOOL findHeader(UIView *view) {
    if (sg_stack && [sg_stack isDescendantOfView:view]) return YES;
    sg_stack = nil;
    sg_scrim = nil;
    sg_header = nil;
    for (UIView *wrapper in view.subviews) {
        UIView *scrim = childNamed(wrapper, @"GradientView");
        if (scrim) sg_scrim = scrim;
    }
    SGForEachView(view, ^(UIView *v) {
        if (!sg_header && [NSStringFromClass(v.class) containsString:@"HomeHeaderView"]) {
            sg_header = v;
            for (UIView *sub in v.subviews) {
                if ([sub isKindOfClass:UIStackView.class]) {
                    sg_stack = (UIStackView *)sub;
                    break;
                }
            }
        }
    });
    if (!sg_header) {
        UIView *header = childNamed(childNamed(view, @"HomeHeaderElement"), @"HomeHeaderView");
        for (UIView *sub in header.subviews) {
            if ([sub isKindOfClass:UIStackView.class]) sg_stack = (UIStackView *)sub;
        }
        sg_header = header;
    }
    if (sg_stack) return YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign home: header stack not found, header left as Spotify's"); });
    return NO;
}

static UIVisualEffectView *barIn(UIView *wrapper) {
    if (!sg_bar) {
        sg_bar = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
        sg_bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        sg_bar.userInteractionEnabled = NO;
        sg_bar.accessibilityElementsHidden = YES;
        sg_bar.alpha = 0;
        sg_barMask = [CAGradientLayer layer];
        sg_barMask.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
        sg_barMask.locations = @[@0, @0.45, @1];
        sg_bar.layer.mask = sg_barMask;
        sg_barTint = [CAGradientLayer layer];
        sg_barTint.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.92].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.55].CGColor,
                              (id)[UIColor colorWithWhite:0 alpha:0].CGColor];
        sg_barTint.locations = @[@0, @0.5, @1];
        [sg_bar.contentView.layer addSublayer:sg_barTint];
    }
    return sg_bar;
}

// Scrolled down: the big title and the avatar fade away and a dark glass gradient takes the top of the screen.
static void applyScroll(UIScrollView *list) {
    CGFloat p = (list.contentOffset.y + list.adjustedContentInset.top) / kFadeDistance;
    p = MAX(0, MIN(1, p));
    sg_scrollProgress = p;
    if (sg_bar && sg_bar.alpha != p) sg_bar.alpha = p;
    if (sg_title && sg_title.alpha != 1 - p) sg_title.alpha = 1 - p;
    if (sg_face) {
        BOOL visible = SGFlag(SGRKeyNavbarProfilePhoto, YES);
        CGFloat alpha = visible ? 1 - p : 0;
        if (sg_face.alpha != alpha) sg_face.alpha = alpha;
        sg_face.userInteractionEnabled = visible && p < 0.5;
        sg_face.accessibilityElementsHidden = !visible;
    }
}

void SGRHomeProfilePhotoPreferenceChanged(void) {
    if (!sg_face) return;
    BOOL visible = SGFlag(SGRKeyNavbarProfilePhoto, YES);
    sg_face.alpha = visible ? 1 - sg_scrollProgress : 0;
    sg_face.userInteractionEnabled = visible && sg_scrollProgress < 0.5;
    sg_face.accessibilityElementsHidden = !visible;
}

static BOOL isPillView(UIView *view) {
    if (!view) return NO;
    if ([view isKindOfClass:UIScrollView.class]) return YES;
    NSString *className = NSStringFromClass(view.class);
    if ([className containsString:@"Pill"] || [className containsString:@"FadeMask"]) return YES;
    NSString *ident = view.accessibilityIdentifier;
    if ([ident containsString:@"Pill"] || [ident containsString:@"Filter"]) return YES;
    return NO;
}

static BOOL isAvatarView(UIView *view) {
    if (!view) return NO;
    static Class faceClass;
    if (!faceClass) faceClass = NSClassFromString(@"_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer");
    if (faceClass && [view isKindOfClass:faceClass]) return YES;
    NSString *className = NSStringFromClass(view.class);
    if ([className containsString:@"AdaptiveFace"] || [className containsString:@"SideDrawer"] || [className containsString:@"Profile"] || [className containsString:@"Avatar"]) return YES;
    NSString *ident = view.accessibilityIdentifier;
    if ([ident containsString:@"SideDrawerButton"] || [ident containsString:@"AdaptiveFace"] || [ident containsString:@"Profile"] || [ident containsString:@"Avatar"] || [ident containsString:@"Account"]) return YES;
    NSString *label = [view.accessibilityLabel lowercaseString];
    if ([label containsString:@"profile"] || [label containsString:@"settings"] || [label containsString:@"account"] || [label containsString:@"your profile"]) return YES;
    return NO;
}

static UIView *avatarIn(UIStackView *stack) {
    __block UIView *face = SGRFindByIdentifier(stack, @"Components.UI.SideDrawerButton*", nil);
    if (face) return face;
    SGForEachView(stack, ^(UIView *v) {
        if (!face && isAvatarView(v)) face = v;
    });
    if (face) return face;
    for (UIView *part in stack.arrangedSubviews) {
        if (!isPillView(part) && (part.bounds.size.width <= 60 || [part isKindOfClass:UIControl.class])) {
            return part;
        }
    }
    return stack.arrangedSubviews.firstObject;
}

static void layoutHeader(UIViewController *page) {
    UIView *view = page.viewIfLoaded;
    if (!view || !findHeader(view)) return;
    if ([objc_getAssociatedObject(page, &kLayoutKey) boolValue]) return;
    objc_setAssociatedObject(page, &kLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *header = sg_header;
    UIStackView *stack = sg_stack;
    __weak UIViewController *weakPage = page;
    if (!objc_getAssociatedObject(stack, &kStackWatchedKey)) {
        objc_setAssociatedObject(stack, &kStackWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRObserveLayout(stack, ^(UIView *laidOut) {
            UIViewController *owner = weakPage;
            if (owner && [laidOut isDescendantOfView:owner.viewIfLoaded]) layoutHeader(owner);
        });
    }
    vanish(sg_scrim);

    UIView *face = avatarIn(stack);
    for (UIView *part in stack.arrangedSubviews) {
        if (face && (face == part || [face isDescendantOfView:part])) {
            part.alpha = 1;
            part.hidden = NO;
            part.userInteractionEnabled = YES;
            part.accessibilityElementsHidden = NO;
            continue;
        }
        if (isPillView(part)) {
            vanish(part);
        } else {
            part.alpha = 1;
            part.hidden = NO;
            part.userInteractionEnabled = YES;
            part.accessibilityElementsHidden = NO;
        }
    }
    if (face) {
        face.alpha = 1;
        face.hidden = NO;
        face.userInteractionEnabled = YES;
        face.accessibilityElementsHidden = NO;
    }
    SGRNavbarSetProfilePhotoVisible(face);
    if (stack.semanticContentAttribute != UISemanticContentAttributeForceLeftToRight) {
        stack.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
        [stack setNeedsLayout];
    }
    [stack layoutIfNeeded];

    UILabel *title = titleIn(header);
    NSString *text = tabName(header.window);
    if (![title.text isEqualToString:text]) {
        title.text = text;
        title.accessibilityLabel = text;
    }
    UIFont *font = SGRFont(UIFontTextStyleLargeTitle, UIFontWeightBold, UIContentSizeCategoryLarge);
    if (![title.font isEqual:font]) title.font = font;

    // The avatar keeps the leading edge, as in the Library header; the title starts after it.
    BOOL faceVisible = SGFlag(SGRKeyNavbarProfilePhoto, YES);
    CGFloat leading = (face && faceVisible) ? MAX(SGRSideMargin + 40, CGRectGetMaxX(SGFrameIn(face, header)) + SGRGrid) : SGRSideMargin;
    CGFloat height = ceil(font.lineHeight);
    CGRect frame = CGRectMake(leading, round(CGRectGetMidY(stack.frame) - height / 2), MAX(0, header.bounds.size.width - leading - SGRSideMargin), height);
    if (!CGRectEqualToRect(title.frame, frame)) title.frame = frame;

    sg_title = title;
    sg_face = face;
    UIView *wrapper = header.superview;
    if (wrapper && SGRHomeGlassStyle()) {
        UIVisualEffectView *bar = barIn(wrapper);
        CGFloat bottom = CGRectGetMaxY([header convertRect:header.bounds toView:view]) + 28;
        CGFloat rightMargin = (SGIsDuoUnfolded() || (view.window && view.window.safeAreaInsets.right > 20))
            ? MAX(view.window ? view.window.safeAreaInsets.right : 0, 92.0)
            : 0;
        CGFloat barWidth = MAX(0, view.bounds.size.width - rightMargin);
        CGRect barFrame = [view convertRect:CGRectMake(0, 0, barWidth, bottom) toView:wrapper];
        if (bar.superview != wrapper) [wrapper insertSubview:bar belowSubview:header];
        if (!CGRectEqualToRect(bar.frame, barFrame)) bar.frame = barFrame;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        sg_barMask.frame = bar.bounds;
        sg_barTint.frame = bar.bounds;
        [CATransaction commit];
    }

    static BOOL logged;
    if (!logged && header.window && frame.size.width > 0 && header.bounds.size.height > 0) {
        logged = YES;
        SGLog(@"redesign home: header %@, avatar %@ in the stack %@, title %@, scrim %@", NSStringFromCGRect(header.frame),
              face ? NSStringFromCGRect(face.frame) : @"not found", NSStringFromCGRect(stack.frame), NSStringFromCGRect(frame),
              sg_scrim ? @"found" : @"not found");
    }
    objc_setAssociatedObject(page, &kLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The page's own list is the one collection view with no other inside which it sits: the shelves are nested in it.
%hook _TtC16Home_CarouselKit29TouchCancellingCollectionView
- (void)layoutSubviews {
    %orig;
    UIScrollView *list = (UIScrollView *)self;
    if (list.bounds.size.height < 300 || !sg_bar) return;
    for (UIView *v = list.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class]) return;
    }
    applyScroll(list);
}
%end

%hook _TtC19Home_FunkisPageImpl20FunkisViewController
- (void)viewDidLoad {
    %orig;
    ((UIViewController *)self).view.backgroundColor = UIColor.blackColor;
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    ((UIViewController *)self).view.backgroundColor = UIColor.blackColor;
    layoutHeader((UIViewController *)self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    CFTimeInterval began = SGRHomeProbeBegin();
    layoutHeader((UIViewController *)self);
    SGRHomeProbeEnd(SGRHomeProbeHeader, began);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    %orig;
    [((UIViewController *)self).viewIfLoaded setNeedsLayout];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC19Home_FunkisPageImpl20FunkisViewController",
        @"_TtC16Home_CarouselKit29TouchCancellingCollectionView",
    ]);
}
