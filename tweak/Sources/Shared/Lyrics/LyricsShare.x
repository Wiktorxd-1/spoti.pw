// Lyrics sharing overhaul: transforms Spotify's lyrics sharing format page into a modern
// Liquid Glass / Apple Music styled shareable card with real-time time-synced karaoke animation,
// line selector integration on the text/edit button, and Instagram Stories sharing with real audio attachment.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"

static char kShareGlassKey, kShareDisplayLinkKey;

@interface _TtC16Share_LyricsImpl31LyricsShareFormatViewController : UIViewController
- (BOOL)isLyricsEditEnabled;
- (BOOL)isEnhancedShareCardEnabled;
- (void)editButtonTapped;
@end

@interface _TtC21Share_SharingSDKSwift28InstagramStoriesShareHandler : NSObject
@end

// Recursively find the preview card container inside the format view controller
static UIView *findCardContainer(UIView *root) {
    if (!root) return nil;
    if (root.subviews.count > 0 && root.bounds.size.width > 200 && root.bounds.size.height > 250) {
        for (UIView *sub in root.subviews) {
            // Usually the card is centered with aspect ratio ~ 9:16 or 3:4
            CGFloat w = sub.bounds.size.width;
            CGFloat h = sub.bounds.size.height;
            if (w >= 180 && h >= 220 && sub.subviews.count > 0) {
                return sub;
            }
        }
    }
    for (UIView *sub in root.subviews) {
        UIView *found = findCardContainer(sub);
        if (found) return found;
    }
    return nil;
}

// Find all UILabels inside the card that represent lyric lines
static NSArray<UILabel *> *findLyricLabels(UIView *card) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(card, ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class]) {
            UILabel *lbl = (UILabel *)v;
            if (lbl.text.length > 0 && lbl.bounds.size.height > 12) {
                [labels addObject:lbl];
            }
        }
    });
    // Sort top to bottom
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGPoint ptA = [a.superview convertPoint:a.frame.origin toView:card];
        CGPoint ptB = [b.superview convertPoint:b.frame.origin toView:card];
        return ptA.y < ptB.y ? NSOrderedAscending : (ptA.y > ptB.y ? NSOrderedDescending : NSOrderedSame);
    }];
    return labels;
}

static void applyModdedCardStyle(UIViewController *vc) {
    UIView *card = findCardContainer(vc.view);
    if (!card) return;

    // Apply sleek modern Liquid Glass styling
    card.layer.cornerRadius = 28;
    card.layer.masksToBounds = YES;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;

    // Add Frosted Dark Glass pane under card content if not present
    UIVisualEffectView *glass = objc_getAssociatedObject(card, &kShareGlassKey);
    if (!glass) {
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        glass = [[UIVisualEffectView alloc] initWithEffect:blur];
        glass.frame = card.bounds;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        glass.layer.cornerRadius = 28;
        glass.layer.masksToBounds = YES;
        [card insertSubview:glass atIndex:0];
        objc_setAssociatedObject(card, &kShareGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        glass.frame = card.bounds;
        [card sendSubviewToBack:glass];
    }

    // Modernize lyric label typography (Apple Music bold rounded style)
    NSArray<UILabel *> *labels = findLyricLabels(card);
    for (UILabel *lbl in labels) {
        if ([lbl.text hasPrefix:@"♪"] || lbl.font.pointSize < 14) continue;
        UIFont *roundedFont = [UIFont systemFontOfSize:lbl.font.pointSize weight:UIFontWeightBold];
        UIFontDescriptor *desc = [roundedFont.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
        if (desc) roundedFont = [UIFont fontWithDescriptor:desc size:lbl.font.pointSize];
        lbl.font = roundedFont;
        lbl.textColor = UIColor.whiteColor;
    }
}

static NSInteger sg_lastLeadIndex = -999;

// Real-time animated lyric highlighting in sync with Spotify track playback
static void updateCardAnimation(UIViewController *vc) {
    UIView *card = findCardContainer(vc.view);
    if (!card || !card.window) return;

    NSInteger position = SGKaraokePositionMs();
    if (position < 0) return;

    NSString *trackID = SGKaraokePlayingTrack();
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(trackID);
    NSInteger leadIndex = SGKaraokeLeadLine(lines, position);
    if (leadIndex == sg_lastLeadIndex) return; // Skip work if active line hasn't changed
    sg_lastLeadIndex = leadIndex;

    NSArray<UILabel *> *labels = findLyricLabels(card);
    if (labels.count == 0) return;

    // Dim lines that are not currently active, highlight the active lead line
    for (NSUInteger i = 0; i < labels.count; i++) {
        UILabel *lbl = labels[i];
        BOOL isActive = (lines && leadIndex >= 0 && leadIndex < (NSInteger)lines.count &&
                         [lbl.text containsString:SGKaraokeLineText(lines[leadIndex])]);
        CGFloat targetAlpha = (leadIndex < 0 || isActive) ? 1.0 : 0.45;
        if (fabs(lbl.alpha - targetAlpha) > 0.05) {
            [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
                lbl.alpha = targetAlpha;
            } completion:nil];
        }
    }
}

%hook _TtC16Share_LyricsImpl31LyricsShareFormatViewController

- (BOOL)isLyricsEditEnabled {
    return YES;
}

- (BOOL)isEnhancedShareCardEnabled {
    return YES;
}

- (void)viewDidLoad {
    %orig;
    // Set up real-time display link for time-synced karaoke animation on preview card
    __weak typeof(self) weakSelf = self;
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:weakSelf selector:@selector(sg_tickAnimation:)];
    if (@available(iOS 15.0, *)) {
        link.preferredFrameRateRange = CAFrameRateRangeMake(15, 30, 30);
    }
    [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(self, &kShareDisplayLinkKey, link, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)viewDidLayoutSubviews {
    %orig;
    applyModdedCardStyle((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    CADisplayLink *link = objc_getAssociatedObject(self, &kShareDisplayLinkKey);
    link.paused = NO;
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    CADisplayLink *link = objc_getAssociatedObject(self, &kShareDisplayLinkKey);
    [link invalidate];
    objc_setAssociatedObject(self, &kShareDisplayLinkKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)sg_tickAnimation:(CADisplayLink *)link {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        return;
    }
    updateCardAnimation((UIViewController *)self);
}

// When format/text button is tapped in edit mode, present the line selection modal
- (void)textButtonTapped:(id)sender {
    if ([self respondsToSelector:@selector(editButtonTapped)]) {
        [self editButtonTapped];
    } else {
        %orig;
    }
}

%end

#pragma mark - Instagram Stories Sharing with Audio Attachment

%hook UIPasteboard

- (void)setItems:(NSArray<NSDictionary<NSString *, id> *> *)items options:(NSDictionary<UIPasteboardOption, id> *)options {
    if (!items.count) {
        %orig(items, options);
        return;
    }

    NSMutableArray *augmented = [NSMutableArray arrayWithCapacity:items.count];
    for (NSDictionary *dict in items) {
        if (dict[@"com.instagram.sharedSticker.stickerImage"] || dict[@"com.instagram.sharedSticker.backgroundImage"]) {
            NSMutableDictionary *mut = [dict mutableCopy];
            // Enable Instagram Stories audio preview and music attachments
            mut[@"com.instagram.sharedSticker.allowMusicAttachments"] = @YES;
            mut[@"com.instagram.sharedSticker.attach_audio_previews"] = @YES;

            // Ensure exact track entity URI and URL are attached for audio match
            SPTPlayerState *state = SGPlayerState();
            NSString *uri = SGURIString(state.track.URI);
            if (uri.length) {
                mut[@"com.instagram.sharedSticker.entityURI"] = uri;
                if ([uri hasPrefix:@"spotify:track:"]) {
                    NSString *trackID = [uri substringFromIndex:@"spotify:track:".length];
                    mut[@"com.instagram.sharedSticker.contentURL"] = [NSString stringWithFormat:@"https://open.spotify.com/track/%@", trackID];
                }
            }
            [augmented addObject:mut];
        } else {
            [augmented addObject:dict];
        }
    }
    %orig(augmented, options);
}

%end

%ctor {
    %init;
    SGRequireClasses(@[
        @"_TtC16Share_LyricsImpl31LyricsShareFormatViewController",
        @"UIPasteboard",
    ]);
}
