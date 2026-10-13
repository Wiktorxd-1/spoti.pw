// Lyrics sharing overhaul: transforms Spotify's lyrics sharing format page into a modern
// Liquid Glass / Apple Music styled shareable card with real-time time-synced karaoke animation,
// interactive multi-line selection modal (up to 6 lines), and Instagram Stories sharing with real audio attachment.
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"
#import "Shared/Navigation/Links.h"
#import "Shared/Haptics/Haptics.h"

static char kShareGlassKey, kShareGlowKey, kShareDisplayLinkKey, kShareEditPillKey, kShareVideoPillKey, kShareTapGestureKey;

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
static void exportStoryVideoFromVC(UIViewController *vc, NSArray<NSString *> *lines, void (^onDone)(void));
static UIView *findCardContainer(UIView *root);
static NSArray<UILabel *> *findLyricLabels(UIView *card);

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

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 14, self.view.bounds.size.width - 180, 26)];
    title.text = @"Select Lyrics";
    title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    UIFontDescriptor *desc = [title.font.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    if (desc) title.font = [UIFont fontWithDescriptor:desc size:20];
    title.textColor = UIColor.whiteColor;
    [header addSubview:title];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, self.view.bounds.size.width - 180, 18)];
    sub.text = @"Choose up to 6 lines to share";
    sub.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    sub.textColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    [header addSubview:sub];

    UIButton *storyBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    storyBtn.frame = CGRectMake(self.view.bounds.size.width - 156, 18, 76, 32);
    storyBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [storyBtn setTitle:@"Story 📹" forState:UIControlStateNormal];
    [storyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    storyBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    storyBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    storyBtn.layer.cornerRadius = 16;
    storyBtn.layer.masksToBounds = YES;
    storyBtn.layer.borderWidth = 1.0;
    storyBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    [storyBtn addTarget:self action:@selector(storyTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:storyBtn];

    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    doneBtn.frame = CGRectMake(self.view.bounds.size.width - 72, 18, 58, 32);
    doneBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [doneBtn setTitle:@"Card" forState:UIControlStateNormal];
    [doneBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
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

- (void)storyTapped {
    NSMutableArray<NSString *> *chosen = [NSMutableArray array];
    NSArray<NSNumber *> *sorted = [self.selectedIndices.allObjects sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *idx in sorted) {
        NSInteger i = idx.integerValue;
        if (i >= 0 && i < (NSInteger)self.lines.count) {
            NSString *txt = SGKaraokeLineText(self.lines[i]);
            if (txt.length) [chosen addObject:txt];
        }
    }
    if (!chosen.count && self.lines.count > 0) {
        NSString *txt = SGKaraokeLineText(self.lines[0]);
        if (txt.length) [chosen addObject:txt];
    }
    if (!chosen.count) return;

    SGPlayFeedback(SGFeedbackToggle);
    exportStoryVideoFromVC(self, chosen, nil);
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

#pragma mark - Animated Video Story Export

static UIImage *findCardArtwork(UIView *card) {
    if (!card) return nil;
    __block UIImage *found = nil;
    SGForEachView(card, ^(UIView *v) {
        if (found) return;
        if ([v isKindOfClass:UIImageView.class]) {
            UIImageView *iv = (UIImageView *)v;
            if (iv.image && iv.bounds.size.width >= 20 && iv.bounds.size.width < 250) {
                found = iv.image;
            }
        }
    });
    return found;
}

static UIImage *resolveArtworkForTrack(UIView *card) {
    UIImage *img = findCardArtwork(card);
    if (img) return img;
    SPTPlayerState *state = SGPlayerState();
    NSDictionary *meta = state.track.metadata;
    if ([meta isKindOfClass:NSDictionary.class]) {
        for (NSString *k in @[@"image_xlarge_url", @"image_large_url", @"image_url"]) {
            NSString *val = meta[k];
            if (!val.length) continue;
            NSString *urlStr = val;
            if ([val hasPrefix:@"spotify:image:"]) {
                urlStr = [@"https://i.scdn.co/image/" stringByAppendingString:[val substringFromIndex:@"spotify:image:".length]];
            }
            if ([urlStr hasPrefix:@"http"]) {
                NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlStr]];
                if (data.length) {
                    UIImage *downloaded = [UIImage imageWithData:data];
                    if (downloaded) return downloaded;
                }
            }
        }
    }
    return nil;
}

static CVPixelBufferRef createPixelBuffer(CGSize size, CVPixelBufferPoolRef pool) {
    CVPixelBufferRef pixelBuffer = NULL;
    if (pool) {
        CVReturn status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer);
        if (status == kCVReturnSuccess && pixelBuffer) return pixelBuffer;
    }
    NSDictionary *options = @{
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, (size_t)size.width, (size_t)size.height,
                                          kCVPixelFormatType_32BGRA,
                                          (__bridge CFDictionaryRef)options,
                                          &pixelBuffer);
    return (status == kCVReturnSuccess) ? pixelBuffer : NULL;
}

static void copyImageToPixelBuffer(UIImage *image, CVPixelBufferRef buffer) {
    CVPixelBufferLockBaseAddress(buffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(buffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pxdata, (size_t)image.size.width, (size_t)image.size.height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    if (ctx) {
        CGContextTranslateCTM(ctx, 0, image.size.height);
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGContextDrawImage(ctx, CGRectMake(0, 0, image.size.width, image.size.height), image.CGImage);
        CGContextRelease(ctx);
    }
    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(buffer, 0);
}

static void drawStoryFrameInContext(CGContextRef ctx, CGSize size, CGFloat progress, UIImage *artwork, NSString *title, NSString *artist, NSArray<NSString *> *lines) {
    CGRect bounds = CGRectMake(0, 0, size.width, size.height);

    // 1. Deep Midnight Gradient Background
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat gradColors[] = {
        0.08, 0.08, 0.14, 1.0,
        0.02, 0.02, 0.04, 1.0
    };
    CGFloat gradLocations[] = { 0.0, 1.0 };
    CGGradientRef bgGrad = CGGradientCreateWithColorComponents(colorSpace, gradColors, gradLocations, 2);
    CGContextDrawLinearGradient(ctx, bgGrad, CGPointMake(0, 0), CGPointMake(0, size.height), 0);
    CGGradientRelease(bgGrad);
    CGColorSpaceRelease(colorSpace);

    // 2. Ambient Blurred Artwork Glow
    if (artwork) {
        CGContextSaveGState(ctx);
        [artwork drawInRect:CGRectMake(-120, -120, size.width + 240, size.height + 240) blendMode:kCGBlendModeNormal alpha:0.32];
        [[UIColor colorWithWhite:0.0 alpha:0.48] setFill];
        UIRectFillUsingBlendMode(bounds, kCGBlendModeNormal);
        CGContextRestoreGState(ctx);
    }

    // 3. Album Artwork Thumbnail (Floating with subtle breathe animation)
    CGFloat breathe = sin(progress * M_PI * 2.0) * 3.0;
    CGFloat artSize = 240.0 + breathe;
    CGFloat artX = (size.width - artSize) / 2.0;
    CGFloat artY = 130.0;
    CGRect artRect = CGRectMake(artX, artY, artSize, artSize);

    if (artwork) {
        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, 16), 36.0, [UIColor colorWithWhite:0 alpha:0.55].CGColor);
        UIBezierPath *artPath = [UIBezierPath bezierPathWithRoundedRect:artRect cornerRadius:26.0];
        [[UIColor colorWithWhite:0.1 alpha:1.0] setFill];
        [artPath fill];

        CGContextSaveGState(ctx);
        [artPath addClip];
        [artwork drawInRect:artRect];
        CGContextRestoreGState(ctx);

        [[UIColor colorWithWhite:1.0 alpha:0.25] setStroke];
        artPath.lineWidth = 1.5;
        [artPath stroke];
        CGContextRestoreGState(ctx);
    }

    // 4. Song Title & Artist
    NSMutableParagraphStyle *centerStyle = [[NSMutableParagraphStyle alloc] init];
    centerStyle.alignment = NSTextAlignmentCenter;
    centerStyle.lineBreakMode = NSLineBreakByTruncatingTail;

    CGFloat currentY = artY + artSize + 32.0;

    if (title.length) {
        UIFont *titleFont = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
        UIFontDescriptor *tDesc = [titleFont.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
        if (tDesc) titleFont = [UIFont fontWithDescriptor:tDesc size:28];

        NSDictionary *titleAttrs = @{
            NSFontAttributeName: titleFont,
            NSForegroundColorAttributeName: UIColor.whiteColor,
            NSParagraphStyleAttributeName: centerStyle
        };
        CGRect titleRect = CGRectMake(36, currentY, size.width - 72, 38);
        [title drawInRect:titleRect withAttributes:titleAttrs];
        currentY += 40.0;
    }

    if (artist.length) {
        UIFont *artistFont = [UIFont systemFontOfSize:19 weight:UIFontWeightMedium];
        UIFontDescriptor *aDesc = [artistFont.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
        if (aDesc) artistFont = [UIFont fontWithDescriptor:aDesc size:19];

        NSDictionary *artistAttrs = @{
            NSFontAttributeName: artistFont,
            NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.68],
            NSParagraphStyleAttributeName: centerStyle
        };
        CGRect artistRect = CGRectMake(36, currentY, size.width - 72, 28);
        [artist drawInRect:artistRect withAttributes:artistAttrs];
        currentY += 40.0;
    }

    // 5. Liquid Glass Lyrics Container Card
    CGFloat cardX = 36.0;
    CGFloat cardY = currentY + 14.0;
    CGFloat cardW = size.width - 72.0;
    CGFloat cardH = size.height - cardY - 110.0;
    CGRect glassCardRect = CGRectMake(cardX, cardY, cardW, cardH);

    CGContextSaveGState(ctx);
    UIBezierPath *cardPath = [UIBezierPath bezierPathWithRoundedRect:glassCardRect cornerRadius:28.0];
    [[UIColor colorWithWhite:0.12 alpha:0.80] setFill];
    [cardPath fill];

    [[UIColor colorWithWhite:1.0 alpha:0.20] setStroke];
    cardPath.lineWidth = 1.5;
    [cardPath stroke];
    CGContextRestoreGState(ctx);

    // 6. Selected Lyrics Lines with Dynamic Karaoke Progress Highlighting
    NSUInteger lineCount = lines.count;
    if (lineCount > 0) {
        NSInteger activeIndex = (NSInteger)(progress * lineCount);
        if (activeIndex >= (NSInteger)lineCount) activeIndex = (NSInteger)lineCount - 1;

        CGFloat paddingY = 24.0;
        CGFloat availableH = cardH - (paddingY * 2.0);
        CGFloat lineBlockH = availableH / lineCount;
        CGFloat lyricY = cardY + paddingY;

        for (NSUInteger i = 0; i < lineCount; i++) {
            NSString *lineText = lines[i];
            BOOL isActive = (i == (NSUInteger)activeIndex);
            BOOL isPast = (i < (NSUInteger)activeIndex);

            CGFloat lineAlpha = isActive ? 1.0 : (isPast ? 0.65 : 0.35);
            CGFloat fontSize = isActive ? 24.0 : 21.0;
            UIFontWeight weight = isActive ? UIFontWeightBold : UIFontWeightMedium;

            UIFont *lFont = [UIFont systemFontOfSize:fontSize weight:weight];
            UIFontDescriptor *lDesc = [lFont.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
            if (lDesc) lFont = [UIFont fontWithDescriptor:lDesc size:fontSize];

            NSMutableParagraphStyle *pStyle = [[NSMutableParagraphStyle alloc] init];
            pStyle.alignment = NSTextAlignmentCenter;
            pStyle.lineBreakMode = NSLineBreakByWordWrapping;

            NSDictionary *lineAttrs = @{
                NSFontAttributeName: lFont,
                NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:lineAlpha],
                NSParagraphStyleAttributeName: pStyle
            };

            CGRect textRect = CGRectMake(cardX + 24.0, lyricY + (lineBlockH - fontSize * 1.5) / 2.0, cardW - 48.0, lineBlockH);
            if (isActive) {
                CGContextSaveGState(ctx);
                CGContextSetShadowWithColor(ctx, CGSizeZero, 12.0, [UIColor colorWithWhite:1.0 alpha:0.6].CGColor);
                [lineText drawInRect:textRect withAttributes:lineAttrs];
                CGContextRestoreGState(ctx);
            } else {
                [lineText drawInRect:textRect withAttributes:lineAttrs];
            }

            lyricY += lineBlockH;
        }
    }

    // 7. Watermark / Branding at Bottom
    NSString *watermark = @"spoti.pw • Liquid Glass";
    UIFont *wmFont = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    UIFontDescriptor *wmDesc = [wmFont.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    if (wmDesc) wmFont = [UIFont fontWithDescriptor:wmDesc size:14];

    NSDictionary *wmAttrs = @{
        NSFontAttributeName: wmFont,
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.42],
        NSParagraphStyleAttributeName: centerStyle
    };
    CGRect wmRect = CGRectMake(36, size.height - 68.0, size.width - 72, 24);
    [watermark drawInRect:wmRect withAttributes:wmAttrs];
}

static void renderStoryVideo(NSArray<NSString *> *lines, UIImage *artwork, NSString *title, NSString *artist, void (^completion)(BOOL success, NSURL *videoURL)) {
    if (!lines.count) {
        if (completion) completion(NO, nil);
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CGSize videoSize = CGSizeMake(720, 1280);
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"spoti_lyrics_story.mp4"];
        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
        NSURL *videoURL = [NSURL fileURLWithPath:tempPath];

        NSError *error = nil;
        AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:videoURL fileType:AVFileTypeMPEG4 error:&error];
        if (error || !writer) {
            SGLog(@"lyrics share: failed to create asset writer %@", error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, nil);
                });
            }
            return;
        }

        NSDictionary *videoSettings = @{
            AVVideoCodecKey: AVVideoCodecTypeH264,
            AVVideoWidthKey: @((int)videoSize.width),
            AVVideoHeightKey: @((int)videoSize.height),
            AVVideoCompressionPropertiesKey: @{
                AVVideoAverageBitRateKey: @(2500000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            }
        };

        AVAssetWriterInput *writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
        writerInput.expectsMediaDataInRealTime = NO;

        NSDictionary *sourcePixelBufferAttributes = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferWidthKey: @((int)videoSize.width),
            (id)kCVPixelBufferHeightKey: @((int)videoSize.height),
            (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
            (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
        };

        AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:writerInput sourcePixelBufferAttributes:sourcePixelBufferAttributes];

        if (![writer canAddInput:writerInput]) {
            SGLog(@"lyrics share: cannot add writer input");
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, nil);
                });
            }
            return;
        }

        [writer addInput:writerInput];
        if (![writer startWriting]) {
            SGLog(@"lyrics share: failed to start writing: %@", writer.error);
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, nil);
                });
            }
            return;
        }

        [writer startSessionAtSourceTime:kCMTimeZero];

        NSInteger fps = 30;
        NSInteger totalFrames = 120; // 4.0 seconds duration
        NSInteger frameIndex = 0;
        NSInteger waitAttempts = 0;

        UIGraphicsImageRendererFormat *rendererFormat = [[UIGraphicsImageRendererFormat alloc] init];
        rendererFormat.scale = 1.0;
        rendererFormat.opaque = YES;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:videoSize format:rendererFormat];

        while (frameIndex < totalFrames) {
            if ([writerInput isReadyForMoreMediaData]) {
                @autoreleasepool {
                    CGFloat progress = (CGFloat)frameIndex / (CGFloat)totalFrames;
                    UIImage *frameImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
                        drawStoryFrameInContext(rendererContext.CGContext, videoSize, progress, artwork, title, artist, lines);
                    }];

                    CVPixelBufferRef pixelBuffer = createPixelBuffer(videoSize, adaptor.pixelBufferPool);
                    if (pixelBuffer) {
                        copyImageToPixelBuffer(frameImage, pixelBuffer);
                        CMTime presentTime = CMTimeMake(frameIndex, (int32_t)fps);
                        [adaptor appendPixelBuffer:pixelBuffer withPresentationTime:presentTime];
                        CVPixelBufferRelease(pixelBuffer);
                    }
                }
                frameIndex++;
                waitAttempts = 0;
            } else {
                [NSThread sleepForTimeInterval:0.005];
                waitAttempts++;
                if (waitAttempts > 1000) break;
            }
        }

        [writerInput markAsFinished];
        [writer finishWritingWithCompletionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (writer.status == AVAssetWriterStatusCompleted) {
                    if (completion) completion(YES, videoURL);
                } else {
                    SGLog(@"lyrics share: asset writer failed with status %ld, error %@", (long)writer.status, writer.error);
                    if (completion) completion(NO, nil);
                }
            });
        }];
    });
}

static void exportStoryVideoFromVC(UIViewController *vc, NSArray<NSString *> *lines, void (^onDone)(void)) {
    UIViewController *targetVC = [vc isKindOfClass:NSClassFromString(@"SGLyricsSelectionModal")] ? ((SGLyricsSelectionModal *)vc).formatVC : vc;
    UIView *card = findCardContainer(targetVC ? targetVC.view : vc.view);
    UIImage *artwork = resolveArtworkForTrack(card);
    SPTPlayerState *state = SGPlayerState();
    NSString *title = state.track.trackTitle ?: @"";
    NSString *artist = state.track.artistName ?: @"";

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.color = UIColor.whiteColor;
    spinner.center = CGPointMake(vc.view.bounds.size.width / 2.0, vc.view.bounds.size.height / 2.0);
    [spinner startAnimating];
    [vc.view addSubview:spinner];

    renderStoryVideo(lines, artwork, title, artist, ^(BOOL success, NSURL *videoURL) {
        [spinner removeFromSuperview];
        if (onDone) onDone();

        if (!success || !videoURL) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Export Failed" message:@"Could not generate animated story video." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [vc presentViewController:alert animated:YES completion:nil];
            return;
        }

        SGPlayFeedback(SGFeedbackToggle);

        UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[videoURL] applicationActivities:nil];
        if (@available(iOS 15.0, *)) {
            activity.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        }
        if (activity.popoverPresentationController) {
            activity.popoverPresentationController.sourceView = vc.view;
            activity.popoverPresentationController.sourceRect = CGRectMake(vc.view.bounds.size.width / 2.0, vc.view.bounds.size.height / 2.0, 1, 1);
        }
        [vc presentViewController:activity animated:YES completion:nil];
    });
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

    // Add sleek "Edit Lines" and "📹 Story" floating glass pill buttons
    CGRect cardInVC = card.superview ? [card.superview convertRect:card.frame toView:vc.view] : card.frame;
    CGFloat pillH = 36;
    CGFloat pillY = (cardInVC.origin.y >= 54) ? (cardInVC.origin.y - 46) : (CGRectGetMaxY(cardInVC) + 12);
    if (pillY < 40) pillY = 50;

    CGFloat totalW = 114 + 10 + 104;
    CGFloat startX = (vc.view.bounds.size.width - totalW) / 2.0;

    UIButton *pill = objc_getAssociatedObject(vc, &kShareEditPillKey);
    if (!pill) {
        pill = [UIButton buttonWithType:UIButtonTypeCustom];
        pill.tag = 999;
        pill.frame = CGRectMake(startX, pillY, 114, pillH);
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
        pill.frame = CGRectMake(startX, pillY, 114, pillH);
        [vc.view bringSubviewToFront:pill];
    }

    UIButton *videoPill = objc_getAssociatedObject(vc, &kShareVideoPillKey);
    if (!videoPill) {
        videoPill = [UIButton buttonWithType:UIButtonTypeCustom];
        videoPill.tag = 998;
        videoPill.frame = CGRectMake(startX + 114 + 10, pillY, 104, pillH);
        videoPill.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
        videoPill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
        videoPill.layer.cornerRadius = 18;
        if (@available(iOS 13.0, *)) {
            videoPill.layer.cornerCurve = kCACornerCurveContinuous;
        }
        videoPill.layer.borderWidth = 1.0;
        videoPill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
        videoPill.layer.masksToBounds = YES;

        [videoPill setTitle:@"📹 Story" forState:UIControlStateNormal];
        [videoPill setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        UIFont *vpFont = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        UIFontDescriptor *vpDesc = [vpFont.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
        if (vpDesc) vpFont = [UIFont fontWithDescriptor:vpDesc size:14];
        videoPill.titleLabel.font = vpFont;

        [videoPill addTarget:vc action:@selector(sg_exportVideoStoryAction) forControlEvents:UIControlEventTouchUpInside];
        [vc.view addSubview:videoPill];
        objc_setAssociatedObject(vc, &kShareVideoPillKey, videoPill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        videoPill.frame = CGRectMake(startX + 114 + 10, pillY, 104, pillH);
        [vc.view bringSubviewToFront:videoPill];
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

void SGOpenLyricsShare(UIViewController *presenter, NSInteger initialLineIndex) {
    // 1. Try finding and triggering Spotify's built-in Share button in the now playing view
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        __block BOOL triggered = NO;
        SGForEachView(w, ^(UIView *v) {
            if (triggered) return;
            if ([v.accessibilityIdentifier isEqualToString:@"ShareButtonNowPlayingView"]) {
                if ([v isKindOfClass:UIControl.class]) {
                    [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
                    triggered = YES;
                } else {
                    for (UIView *sub in v.subviews) {
                        if ([sub isKindOfClass:UIControl.class]) {
                            [(UIControl *)sub sendActionsForControlEvents:UIControlEventTouchUpInside];
                            triggered = YES;
                            break;
                        }
                    }
                }
            }
        });
        if (triggered) return;
    }
#pragma clang diagnostic pop

    // 2. Fallback: URI dispatcher to open Spotify's native share flow
    SPTPlayerState *state = SGPlayerState();
    NSString *uri = SGURIString(state.track.URI);
    if (uri.length) {
        if (![uri hasPrefix:@"spotify:"]) uri = [@"spotify:track:" stringByAppendingString:uri];
        NSURL *shareURL = [NSURL URLWithString:[NSString stringWithFormat:@"spotify:share:%@", uri]];
        if (SGOpenSpotifyURI(shareURL)) return;
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

%new
- (void)sg_openLineSelectorAction {
    openLineSelector((UIViewController *)self);
}

%new
- (void)sg_exportVideoStoryAction {
    UIView *card = findCardContainer(self.view);
    NSArray<UILabel *> *labels = findLyricLabels(card);
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (UILabel *lbl in labels) {
        if (!lbl.hidden && lbl.text.length > 0) {
            [lines addObject:lbl.text];
        }
    }
    if (!lines.count) {
        NSString *trackID = SGKaraokePlayingTrack();
        NSArray<SGKaraokeLine *> *kLines = SGKaraokeLinesForTrack(trackID);
        for (NSUInteger i = 0; i < MIN(kLines.count, 4); i++) {
            NSString *t = SGKaraokeLineText(kLines[i]);
            if (t.length) [lines addObject:t];
        }
    }
    exportStoryVideoFromVC((UIViewController *)self, lines, nil);
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

