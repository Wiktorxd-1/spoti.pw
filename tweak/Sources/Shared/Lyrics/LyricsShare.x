// Lyrics sharing overhaul: transforms Spotify's lyrics sharing format page into a modern
// Liquid Glass / Apple Music styled shareable card with real-time time-synced karaoke animation,
// interactive multi-line selection modal (up to 6 lines), and Instagram Stories sharing with real audio attachment.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"
#import "Shared/Haptics/Haptics.h"

static char kShareGlassKey, kShareGlowKey, kShareDisplayLinkKey, kShareEditPillKey, kShareTapGestureKey;

@interface _TtC16Share_LyricsImpl31LyricsShareFormatViewController : UIViewController
- (BOOL)isLyricsEditEnabled;
- (BOOL)isEnhancedShareCardEnabled;
- (void)editButtonTapped;
@end

@interface _TtC16Share_LyricsImpl34LyricsShareSelectionViewController : UIViewController
@end

// Forward declarations
static void applyModdedCardStyle(UIViewController *vc);
static void openLineSelector(UIViewController *presenter);

#pragma mark - Line Selection Modal

@interface SGLyricsSelectionModal : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, weak) UIViewController *formatVC;
@property (nonatomic, copy) NSArray<SGKaraokeLine *> *lines;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *selectedIndices;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) void (^onDone)(NSArray<NSString *> *selectedTexts);
@end

@implementation SGLyricsSelectionModal

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.95];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    // Header view
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 68)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 16, self.view.bounds.size.width - 120, 26)];
    title.text = @"Select Lyrics";
    title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    UIFontDescriptor *desc = [title.font.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    if (desc) title.font = [UIFont fontWithDescriptor:desc size:20];
    title.textColor = UIColor.whiteColor;
    [header addSubview:title];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(20, 42, self.view.bounds.size.width - 120, 18)];
    sub.text = @"Choose up to 6 lines to share";
    sub.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    sub.textColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    [header addSubview:sub];

    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    doneBtn.frame = CGRectMake(self.view.bounds.size.width - 80, 18, 64, 32);
    doneBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [doneBtn setTitle:@"Done" forState:UIControlStateNormal];
    [doneBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    doneBtn.backgroundColor = UIColor.whiteColor;
    doneBtn.layer.cornerRadius = 16;
    doneBtn.layer.masksToBounds = YES;
    [doneBtn addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:doneBtn];

    [self.view addSubview:header];

    // Table view
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 68, self.view.bounds.size.width, self.view.bounds.size.height - 68) style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 54;
    self.tableView.contentInset = UIEdgeInsetsMake(8, 0, 32, 0);
    [self.view addSubview:self.tableView];
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
    if (self.onDone) {
        NSMutableArray<NSString *> *chosen = [NSMutableArray array];
        NSArray<NSNumber *> *sorted = [self.selectedIndices.allObjects sortedArrayUsingSelector:@selector(compare:)];
        for (NSNumber *idx in sorted) {
            NSInteger i = idx.integerValue;
            if (i >= 0 && i < (NSInteger)self.lines.count) {
                NSString *txt = SGKaraokeLineText(self.lines[i]);
                if (txt.length) [chosen addObject:txt];
            }
        }
        self.onDone(chosen);
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.lines.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LyricCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"LyricCell"];
        cell.backgroundColor = UIColor.clearColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(20, 10, self.view.bounds.size.width - 40, 34)];
        lbl.tag = 101;
        lbl.numberOfLines = 0;
        lbl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [cell.contentView addSubview:lbl];
    }

    UILabel *lbl = [cell.contentView viewWithTag:101];
    BOOL isSelected = [self.selectedIndices containsObject:@(indexPath.row)];
    SGKaraokeLine *line = self.lines[indexPath.row];
    lbl.text = SGKaraokeLineText(line);

    UIFont *font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    UIFontDescriptor *desc = [font.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    if (desc) font = [UIFont fontWithDescriptor:desc size:18];
    lbl.font = font;

    if (isSelected) {
        lbl.textColor = UIColor.whiteColor;
        lbl.alpha = 1.0;
        cell.contentView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        cell.contentView.layer.cornerRadius = 14;
        cell.contentView.layer.masksToBounds = YES;
    } else {
        lbl.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
        lbl.alpha = 0.6;
        cell.contentView.backgroundColor = UIColor.clearColor;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSNumber *num = @(indexPath.row);
    if ([self.selectedIndices containsObject:num]) {
        [self.selectedIndices removeObject:num];
    } else {
        if (self.selectedIndices.count >= 6) {
            SGPlayFeedback(SGFeedbackEdge);
            return;
        }
        [self.selectedIndices addObject:num];
    }
    SGPlayFeedback(SGFeedbackToggle);
    [tableView reloadData];
}

@end

#pragma mark - Card Hierarchy & Styling

// Recursively find the preview card container inside the format view controller
static UIView *findCardContainer(UIView *root) {
    if (!root) return nil;
    if (root.subviews.count > 0 && root.bounds.size.width > 200 && root.bounds.size.height > 250) {
        for (UIView *sub in root.subviews) {
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
    SPTPlayerState *state = SGPlayerState();
    NSString *trackName = state.track.trackTitle ?: @"";
    NSString *artistName = state.track.artistName ?: @"";

    SGForEachView(card, ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class]) {
            UILabel *lbl = (UILabel *)v;
            if (lbl.text.length > 0 && lbl.bounds.size.height > 12) {
                // Ignore track title, artist name, and spotify watermark labels
                if ([lbl.text isEqualToString:trackName] || [lbl.text isEqualToString:artistName] ||
                    [lbl.text hasPrefix:@"Spotify"] || [lbl.text hasPrefix:@"♪"]) {
                    return;
                }
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

    // Strip solid and opaque backgrounds from card and its intermediate container views
    card.backgroundColor = UIColor.clearColor;
    for (UIView *sub in card.subviews) {
        if ([sub isKindOfClass:UIImageView.class] && sub.bounds.size.width >= card.bounds.size.width - 10) {
            sub.hidden = YES; // Hide solid background image
        } else if (![sub isKindOfClass:UIVisualEffectView.class] && sub.tag != 999) {
            sub.backgroundColor = UIColor.clearColor;
        }
    }

    // Apply sleek modern Liquid Glass styling (28pt continuous corner radius + 1pt glass border)
    card.layer.cornerRadius = 28;
    if (@available(iOS 13.0, *)) {
        card.layer.cornerCurve = kCACornerCurveContinuous;
    }
    card.layer.masksToBounds = YES;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;

    // Ambient background glow layer matching modern dark glass
    CAGradientLayer *glow = objc_getAssociatedObject(card, &kShareGlowKey);
    if (!glow) {
        glow = [CAGradientLayer layer];
        glow.frame = card.bounds;
        glow.colors = @[
            (id)[UIColor colorWithWhite:0.15 alpha:0.8].CGColor,
            (id)[UIColor colorWithWhite:0.05 alpha:0.9].CGColor
        ];
        glow.startPoint = CGPointMake(0.2, 0.0);
        glow.endPoint = CGPointMake(0.8, 1.0);
        glow.cornerRadius = 28;
        [card.layer insertSublayer:glow atIndex:0];
        objc_setAssociatedObject(card, &kShareGlowKey, glow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        glow.frame = card.bounds;
    }

    // Frosted Dark Glass pane
    UIVisualEffectView *glass = objc_getAssociatedObject(card, &kShareGlassKey);
    if (!glass) {
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        glass = [[UIVisualEffectView alloc] initWithEffect:blur];
        glass.frame = card.bounds;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        glass.layer.cornerRadius = 28;
        if (@available(iOS 13.0, *)) {
            glass.layer.cornerCurve = kCACornerCurveContinuous;
        }
        glass.layer.masksToBounds = YES;
        [card insertSubview:glass atIndex:0];
        objc_setAssociatedObject(card, &kShareGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        glass.frame = card.bounds;
        [card sendSubviewToBack:glass];
    }

    // Modernize lyric label typography (Apple Music bold rounded style with crisp text)
    NSArray<UILabel *> *labels = findLyricLabels(card);
    for (UILabel *lbl in labels) {
        UIFont *roundedFont = [UIFont systemFontOfSize:21 weight:UIFontWeightBold];
        UIFontDescriptor *desc = [roundedFont.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
        if (desc) roundedFont = [UIFont fontWithDescriptor:desc size:21];
        lbl.font = roundedFont;
        lbl.textColor = UIColor.whiteColor;
        lbl.numberOfLines = 0;
        lbl.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.4].CGColor;
        lbl.layer.shadowOffset = CGSizeMake(0, 1);
        lbl.layer.shadowRadius = 4;
        lbl.layer.shadowOpacity = 0.6;
    }

    // Style album artwork thumbnail with continuous rounded corners
    SGForEachView(card, ^(UIView *v) {
        if ([v isKindOfClass:UIImageView.class] && v.bounds.size.width < 100 && v.bounds.size.width > 20) {
            v.layer.cornerRadius = 12;
            if (@available(iOS 13.0, *)) {
                v.layer.cornerCurve = kCACornerCurveContinuous;
            }
            v.layer.masksToBounds = YES;
        }
    });

    // Make the entire card tappable to open the line selection sheet
    if (!objc_getAssociatedObject(card, &kShareTapGestureKey)) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:vc action:@selector(sg_handleCardTap:)];
        tap.cancelsTouchesInView = NO;
        card.userInteractionEnabled = YES;
        [card addGestureRecognizer:tap];
        objc_setAssociatedObject(card, &kShareTapGestureKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // Add navigation bar Edit button if available
    if (vc.navigationItem && !vc.navigationItem.rightBarButtonItem) {
        UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithTitle:@"Edit Lines" style:UIBarButtonItemStylePlain target:vc action:@selector(sg_openLineSelectorAction)];
        vc.navigationItem.rightBarButtonItem = item;
    }

    // Add sleek "Edit Lines" floating glass pill button
    UIButton *pill = objc_getAssociatedObject(vc, &kShareEditPillKey);
    CGRect cardInVC = card.superview ? [card.superview convertRect:card.frame toView:vc.view] : card.frame;
    CGFloat pillW = 132;
    CGFloat pillH = 36;
    CGFloat pillY = (cardInVC.origin.y >= 54) ? (cardInVC.origin.y - 46) : (CGRectGetMaxY(cardInVC) + 12);
    if (pillY < 40) pillY = 50;

    if (!pill) {
        pill = [UIButton buttonWithType:UIButtonTypeCustom];
        pill.tag = 999;
        pill.frame = CGRectMake((vc.view.bounds.size.width - pillW) / 2.0, pillY, pillW, pillH);
        pill.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
        pill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
        pill.layer.cornerRadius = 18;
        if (@available(iOS 13.0, *)) {
            pill.layer.cornerCurve = kCACornerCurveContinuous;
        }
        pill.layer.borderWidth = 1.0;
        pill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
        pill.layer.masksToBounds = YES;

        [pill setTitle:@"✏️ Edit Lines" forState:UIControlStateNormal];
        [pill setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        UIFont *pFont = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        UIFontDescriptor *pDesc = [pFont.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
        if (pDesc) pFont = [UIFont fontWithDescriptor:pDesc size:14];
        pill.titleLabel.font = pFont;

        [pill addTarget:vc action:@selector(sg_openLineSelectorAction) forControlEvents:UIControlEventTouchUpInside];
        [vc.view addSubview:pill];
        objc_setAssociatedObject(vc, &kShareEditPillKey, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        pill.frame = CGRectMake((vc.view.bounds.size.width - pillW) / 2.0, pillY, pillW, pillH);
        [vc.view bringSubviewToFront:pill];
    }
}

static void openLineSelector(UIViewController *presenter) {
    NSString *trackID = SGKaraokePlayingTrack();
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(trackID);
    if (!lines.count) {
        SPTPlayerState *state = SGPlayerState();
        NSString *uri = SGURIString(state.track.URI);
        if ([uri hasPrefix:@"spotify:track:"]) {
            trackID = [uri substringFromIndex:@"spotify:track:".length];
            lines = SGKaraokeLinesForTrack(trackID);
        }
    }
    if (!lines.count) return;

    SGLyricsSelectionModal *modal = [[SGLyricsSelectionModal alloc] init];
    modal.formatVC = presenter;
    modal.lines = lines;
    modal.selectedIndices = [NSMutableSet set];

    // Pre-select current lead line + next line
    NSInteger pos = SGKaraokePositionMs();
    NSInteger lead = SGKaraokeLeadLine(lines, pos);
    if (lead >= 0 && lead < (NSInteger)lines.count) {
        [modal.selectedIndices addObject:@(lead)];
        if (lead + 1 < (NSInteger)lines.count) [modal.selectedIndices addObject:@(lead + 1)];
    } else if (lines.count > 0) {
        [modal.selectedIndices addObject:@0];
        if (lines.count > 1) [modal.selectedIndices addObject:@1];
    }

    modal.onDone = ^(NSArray<NSString *> *selectedTexts) {
        if (!selectedTexts.count) return;
        UIView *card = findCardContainer(presenter.view);
        if (!card) return;

        NSArray<UILabel *> *labels = findLyricLabels(card);
        // If we have matching count of labels or can update them
        for (NSUInteger i = 0; i < labels.count; i++) {
            if (i < selectedTexts.count) {
                labels[i].text = selectedTexts[i];
                labels[i].hidden = NO;
            } else {
                labels[i].text = @"";
                labels[i].hidden = YES;
            }
        }
        applyModdedCardStyle(presenter);
    };

    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = modal.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 24;
    }
    [presenter presentViewController:modal animated:YES completion:nil];
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

%new
- (void)sg_openLineSelectorAction {
    openLineSelector((UIViewController *)self);
}

%new
- (void)sg_handleCardTap:(UITapGestureRecognizer *)gesture {
    openLineSelector((UIViewController *)self);
}

// When format/text button is tapped in edit mode, present the line selection modal
- (void)textButtonTapped:(id)sender {
    openLineSelector((UIViewController *)self);
}

- (void)editButtonTapped {
    openLineSelector((UIViewController *)self);
}

%end

%hook _TtC16Share_LyricsImpl34LyricsShareSelectionViewController

- (NSInteger)maxSelectedLines {
    return 6;
}

- (NSInteger)selectionLimit {
    return 6;
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

