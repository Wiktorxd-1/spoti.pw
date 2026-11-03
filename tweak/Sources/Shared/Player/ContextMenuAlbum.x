#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "ContextMenuAlbum.h"

static NSMutableDictionary<NSString *, NSString *> *sg_albumCache;
static char kAlbumDecoratedKey;

void SGCacheTrackAlbum(NSString *title, NSString *album) {
    if (!title.length || !album.length) return;
    if (!sg_albumCache) sg_albumCache = [NSMutableDictionary dictionary];
    sg_albumCache[title] = album;
}

static void updateCacheFromState(SPTPlayerState *state) {
    if (!state) return;
    SPTPlayerTrack *curr = state.track;
    if (curr) {
        NSString *title = curr.trackTitle;
        NSString *album = curr.metadata[@"album_title"];
        if (title.length && album.length) SGCacheTrackAlbum(title, album);
    }
    if ([state.future isKindOfClass:NSArray.class]) {
        for (id item in state.future) {
            if ([item isKindOfClass:NSClassFromString(@"SPTPlayerTrack")]) {
                SPTPlayerTrack *t = (SPTPlayerTrack *)item;
                NSString *title = t.trackTitle;
                NSString *album = t.metadata[@"album_title"];
                if (title.length && album.length) SGCacheTrackAlbum(title, album);
            }
        }
    }
    if ([state.reverse isKindOfClass:NSArray.class]) {
        for (id item in state.reverse) {
            if ([item isKindOfClass:NSClassFromString(@"SPTPlayerTrack")]) {
                SPTPlayerTrack *t = (SPTPlayerTrack *)item;
                NSString *title = t.trackTitle;
                NSString *album = t.metadata[@"album_title"];
                if (title.length && album.length) SGCacheTrackAlbum(title, album);
            }
        }
    }
}

static NSString *findAlbumInObject(id obj, int depth) {
    if (!obj || depth > 2) return nil;

    for (NSString *key in @[@"albumTitle", @"albumName", @"album"]) {
        @try {
            id val = [obj valueForKey:key];
            if ([val isKindOfClass:NSString.class] && [val length] > 0) return val;
        } @catch (NSException *e) {}
    }

    if ([obj isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = (NSDictionary *)obj;
        for (NSString *k in @[@"album_title", @"album_name", @"albumTitle", @"albumName", @"album"]) {
            id v = dict[k];
            if ([v isKindOfClass:NSString.class] && [v length] > 0) return v;
            if ([v isKindOfClass:NSDictionary.class]) {
                NSString *n = v[@"name"] ?: v[@"title"];
                if ([n isKindOfClass:NSString.class] && n.length > 0) return n;
            }
        }
    }
    return nil;
}

static NSString *findAlbumFromTable(UITableView *table) {
    if (!table) return nil;
    for (NSInteger s = 0; s < table.numberOfSections; s++) {
        for (NSInteger r = 0; r < [table numberOfRowsInSection:s]; r++) {
            UITableViewCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:r inSection:s]];
            if (!cell) continue;
            __block NSString *album = nil;
            SGForEachView(cell, ^(UIView *v) {
                if ([v.accessibilityIdentifier containsString:@"album"] ||
                    [v.accessibilityLabel.lowercaseString containsString:@"album"]) {
                    if ([v isKindOfClass:UILabel.class]) {
                        NSString *text = ((UILabel *)v).text;
                        if (text.length && ![text.lowercaseString containsString:@"go to"]) {
                            album = text;
                        }
                    }
                }
            });
            if (album.length) return album;
        }
    }
    return nil;
}

static void decorateContextMenuHeader(UIViewController *menu) {
    if (!SGFlag(SGKeyContextMenuAlbum, YES)) return;
    UIView *root = menu.viewIfLoaded;
    if (!root) return;

    UITableView *table = nil;
    UIView *header = nil;
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:UITableView.class]) table = (UITableView *)sub;
        else if (sub.bounds.size.height > 20 && !header) header = sub;
    }
    if (!header) return;

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(header, ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class] && !v.hidden && ((UILabel *)v).text.length) {
            [labels addObject:(UILabel *)v];
        }
    });
    if (labels.count < 2) return;

    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGFloat ya = [a convertPoint:CGPointZero toView:header].y;
        CGFloat yb = [b convertPoint:CGPointZero toView:header].y;
        if (fabs(ya - yb) > 4) return ya < yb ? NSOrderedAscending : NSOrderedDescending;
        CGFloat xa = [a convertPoint:CGPointZero toView:header].x;
        CGFloat xb = [b convertPoint:CGPointZero toView:header].x;
        return xa < xb ? NSOrderedAscending : (xa > xb ? NSOrderedDescending : NSOrderedSame);
    }];

    UILabel *titleLabel = labels[0];
    UILabel *subtitleLabel = labels[1];
    NSString *currentSub = subtitleLabel.text;
    if (!currentSub.length || [currentSub containsString:@" • "]) return;

    NSString *trackTitle = titleLabel.text;
    NSString *album = findAlbumInObject(menu, 0)
                   ?: findAlbumInObject(header, 0)
                   ?: (table ? findAlbumFromTable(table) : nil)
                   ?: sg_albumCache[trackTitle];

    if (!album.length) {
        SPTPlayerTrack *track = SGPlayerState().track;
        if (track && [track.trackTitle isEqualToString:trackTitle]) {
            album = track.metadata[@"album_title"];
        }
    }

    if (album.length && ![album isEqualToString:currentSub]) {
        NSString *newSub = [NSString stringWithFormat:@"%@ • %@", currentSub, album];
        subtitleLabel.text = newSub;
        subtitleLabel.accessibilityLabel = newSub;
        subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        objc_setAssociatedObject(subtitleLabel, &kAlbumDecoratedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [header setNeedsLayout];
    }
}

@interface SGPlayerStateMenuAlbumObserver : NSObject <SGPlayerStateObserver>
@end

@implementation SGPlayerStateMenuAlbumObserver
- (void)playerStateDidChange:(SPTPlayerState *)state {
    updateCacheFromState(state);
}
@end

static SGPlayerStateMenuAlbumObserver *sg_stateObserver;

%hook _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLayoutSubviews {
    %orig;
    decorateContextMenuHeader((UIViewController *)self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    decorateContextMenuHeader((UIViewController *)self);
}
%end

%ctor {
    sg_stateObserver = [SGPlayerStateMenuAlbumObserver new];
    SGAddPlayerStateObserver(sg_stateObserver);
    %init;
    SGRequireClasses(@[@"_TtC24ContextMenu_InternalImpl25ContextMenuViewController"]);
}
