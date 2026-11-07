#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Player/SpeedPitch.h"
#import "Player.h"
#import "Shared/Duo/SGDuo.h"

static char kGlassKey, kCloseKey, kMoreKey, kPillViewKey;

static void glassInside(UIViewController *unit, NSArray<NSString *> *identifiers, const void **findKeys) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    NSUInteger found = 0;
    for (NSUInteger i = 0; i < identifiers.count; i++) {
        UIView *button = SGRFindByIdentifier(host, identifiers[i], findKeys[i]);
        if (!button) {
            static NSMutableSet<NSString *> *missing;
            if (!missing) missing = [NSMutableSet set];
            if (![missing containsObject:identifiers[i]]) {
                [missing addObject:identifiers[i]];
                SGLog(@"redesign player: %@ not found in %@, left as Spotify's", identifiers[i], NSStringFromClass(host.class));
            }
            continue;
        }
        SGRGlassInside(button, &kGlassKey, SGRGlassCircleSize);
        if ([identifiers[i] isEqualToString:@"Context menu"]) {
            SGPlayerMenuWatchMoreButton(button);
            SGRPlayerMenuWatchMoreButton(button);
            if (SGIsDuoDevice()) {
                button.superview.clipsToBounds = NO;
                host.clipsToBounds = NO;
                if (host.superview) host.superview.clipsToBounds = NO;
                CGAffineTransform down = CGAffineTransformMakeTranslation(0, 138.0);
                if (!CGAffineTransformEqualToTransform(button.transform, down)) button.transform = down;
            } else {
                if (!CGAffineTransformIsIdentity(button.transform)) button.transform = CGAffineTransformIdentity;
            }
        }
        found++;
    }

    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *unitName = NSStringFromClass(unit.class);
    if (![logged containsObject:unitName]) {
        [logged addObject:unitName];
        SGLog(@"redesign player: glass inside %lu of %lu buttons in %@", (unsigned long)found, (unsigned long)identifiers.count, unitName);
    }
}


// The header's context line ("Playing from ...") on a glass pill of its own, so it reads over any cover, the
// sharp artwork of the fill background included. The pill is a passthrough view under the label, sized to
// the text, so Spotify's label keeps its layout and its taps.
static UILabel *contextLabelIn(UIView *host) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(host, ^(UIView *view) {
        if (![view isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)view;
        if (!label.text.length) return;
        [labels addObject:label];
    });
    if (!labels.count) return nil;
    if (labels.count == 1) return labels.firstObject;

    UILabel *titleLabel = nil;
    UILabel *subtitleLabel = nil;
    for (UILabel *l in labels) {
        CGFloat pt = l.font.pointSize;
        if (pt > 12.0) {
            titleLabel = l;
        } else {
            subtitleLabel = l;
        }
    }
    if (!titleLabel) titleLabel = labels.lastObject;
    if (subtitleLabel && subtitleLabel != titleLabel) {
        subtitleLabel.hidden = YES;
        subtitleLabel.alpha = 0.0;
    }
    return titleLabel;
}

static __weak UIViewController *sg_headerUnit;

static void pillBehindContext(UIViewController *unit);

void SGRPlayerHeaderUpdateLyrics(void) {
    if (sg_headerUnit) pillBehindContext(sg_headerUnit);
}

static void pillBehindContext(UIViewController *unit) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    UILabel *label = contextLabelIn(host);
    UIView *box = label ? objc_getAssociatedObject(label, &kPillViewKey) : nil;
    if (SGRPlayerLyricsOpen()) {
        if (box) box.hidden = YES;
        if (label) label.hidden = YES;
        return;
    }
    if (!label || !label.superview) {
        if (box) box.hidden = YES;
        return;
    }

    if (!box) {
        UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:SGGlassEffect()];
        glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        glass.userInteractionEnabled = NO;
        glass.accessibilityElementsHidden = YES;
        box = glass;
        objc_setAssociatedObject(label, &kPillViewKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *parent = label.superview;
    if (box.superview != parent) [parent insertSubview:box belowSubview:label];
    else if ([parent.subviews indexOfObject:box] > [parent.subviews indexOfObject:label]) [parent insertSubview:box belowSubview:label];

    parent.clipsToBounds = NO;
    parent.backgroundColor = UIColor.clearColor;
    parent.layer.backgroundColor = UIColor.clearColor.CGColor;
    parent.layer.cornerRadius = 17.0;
    parent.layer.cornerCurve = kCACornerCurveContinuous;
    if (parent.superview && parent.superview != host) {
        parent.superview.clipsToBounds = NO;
        parent.superview.backgroundColor = UIColor.clearColor;
        parent.superview.layer.backgroundColor = UIColor.clearColor.CGColor;
    }
    if ([parent isKindOfClass:UIButton.class]) {
        UIButton *btn = (UIButton *)parent;
        if ([btn respondsToSelector:@selector(configuration)] && btn.configuration) {
            UIButtonConfiguration *cfg = [btn.configuration copy];
            cfg.background.backgroundColor = UIColor.clearColor;
            cfg.background.visualEffect = nil;
            cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
            btn.configuration = cfg;
        }
    }
    for (UIView *sub in parent.subviews) {
        if (sub != label && sub != box) {
            if ([sub isKindOfClass:UILabel.class]) {
                sub.hidden = YES;
                sub.alpha = 0.0;
            } else if (![sub isKindOfClass:UIControl.class]) {
                sub.hidden = YES;
                sub.alpha = 0.0;
            }
        }
    }

    UIEdgeInsets insets = host.safeAreaInsets;
    CGFloat usableW = host.bounds.size.width - insets.left - insets.right;
    if (usableW <= 0) usableW = host.bounds.size.width;
    CGFloat centerX = insets.left + usableW / 2.0;
    CGFloat centerY = host.bounds.size.height / 2.0;
    CGPoint targetCenter = [host convertPoint:CGPointMake(centerX, centerY) toView:parent];

    UIFont *font = label.font ?: [UIFont boldSystemFontOfSize:14];
    CGSize attrSize = [label.text sizeWithAttributes:@{NSFontAttributeName: font}];
    CGSize fitSize = [label sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    CGFloat textW = ceil(MAX(attrSize.width, fitSize.width));

    CGFloat maxW = MAX(80.0, usableW - 120.0);
    CGFloat padX = 18.0;
    CGFloat width = MIN(textW + 2 * padX, maxW);
    CGFloat height = 34.0;
    CGFloat radius = height / 2.0;

    parent.layer.cornerRadius = radius;

    box.bounds = CGRectMake(0, 0, width, height);
    box.center = targetCenter;
    box.layer.cornerRadius = radius;
    box.layer.cornerCurve = kCACornerCurveContinuous;
    box.clipsToBounds = YES;
    box.layer.masksToBounds = YES;
    if ([box isKindOfClass:UIVisualEffectView.class]) {
        UIView *cv = ((UIVisualEffectView *)box).contentView;
        cv.layer.cornerRadius = radius;
        cv.layer.cornerCurve = kCACornerCurveContinuous;
        cv.clipsToBounds = YES;
        cv.layer.masksToBounds = YES;
    }
    SGShapeGlass(box, radius, YES);
    box.layer.cornerRadius = radius;
    box.layer.cornerCurve = kCACornerCurveContinuous;
    box.clipsToBounds = YES;
    box.layer.masksToBounds = YES;
    if ([box isKindOfClass:UIVisualEffectView.class]) {
        UIView *cv = ((UIVisualEffectView *)box).contentView;
        cv.layer.cornerRadius = radius;
        cv.layer.cornerCurve = kCACornerCurveContinuous;
        cv.clipsToBounds = YES;
        cv.layer.masksToBounds = YES;
    }
    box.hidden = NO;
    box.alpha = 1.0;

    label.bounds = CGRectMake(0, 0, width - 2 * padX, height);
    label.center = targetCenter;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.textAlignment = NSTextAlignmentCenter;
    label.hidden = NO;
    label.alpha = 1.0;
}

%hook _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    sg_headerUnit = (UIViewController *)self;
    static const void *keys[] = {&kCloseKey, &kMoreKey};
    glassInside((UIViewController *)self, @[@"now-playing-minimize-button", @"Context menu"], keys);
    pillBehindContext((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl18HeaderElementsUnit"]);
}
