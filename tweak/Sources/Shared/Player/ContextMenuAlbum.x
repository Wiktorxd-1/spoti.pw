#import <objc/message.h>
#import <objc/runtime.h>
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
    if (state.track) {
        NSString *title = state.track.trackTitle;
        NSString *album = state.track.metadata[@"album_title"];
        if (title.length && album.length) SGCacheTrackAlbum(title, album);
    }
    if ([state.future isKindOfClass:NSArray.class]) {
        for (id item in state.future) {
            if ([item respondsToSelector:@selector(trackTitle)] && [item respondsToSelector:@selector(metadata)]) {
                NSString *title = [item trackTitle];
                NSString *album = [item metadata][@"album_title"];
                if (title.length && album.length) SGCacheTrackAlbum(title, album);
            }
        }
    }
    if ([state.reverse isKindOfClass:NSArray.class]) {
        for (id item in state.reverse) {
            if ([item respondsToSelector:@selector(trackTitle)] && [item respondsToSelector:@selector(metadata)]) {
                NSString *title = [item trackTitle];
                NSString *album = [item metadata][@"album_title"];
                if (title.length && album.length) SGCacheTrackAlbum(title, album);
            }
        }
    }
}

static NSString *findAlbumInObject(id obj, int depth) {
    if (!obj || depth > 4) return nil;

    for (NSString *selName in @[@"albumTitle", @"albumName", @"album", @"name", @"title"]) {
        SEL sel = NSSelectorFromString(selName);
        if ([obj respondsToSelector:sel]) {
            @try {
                id res = ((id (*)(id, SEL))objc_msgSend)(obj, sel);
                if ([res isKindOfClass:NSString.class] && [res length] > 0) {
                    if (![selName isEqualToString:@"name"] && ![selName isEqualToString:@"title"]) {
                        return res;
                    }
                }
            } @catch (__unused NSException *e) {}
        }
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

    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList([obj class], &count);
    if (ivars) {
        for (unsigned int i = 0; i < count; i++) {
            const char *ivarName = ivar_getName(ivars[i]);
            if (!ivarName) continue;
            NSString *name = @(ivarName);
            if ([name containsString:@"album"] || [name containsString:@"model"] || [name containsString:@"props"] || [name containsString:@"metadata"] || [name containsString:@"item"]) {
                id val = object_getIvar(obj, ivars[i]);
                if ([val isKindOfClass:NSString.class] && [val length] > 0 && [name containsString:@"album"]) {
                    free(ivars);
                    return val;
                }
                NSString *found = findAlbumInObject(val, depth + 1);
                if (found.length) {
                    free(ivars);
                    return found;
                }
            }
        }
        free(ivars);
    }
    return nil;
}

static NSString *findAlbumFromTable(UITableView *table) {
    if (!table) return nil;
    for (NSInteger s = 0; s < table.numberOfSections; s++) {
        for (NSInteger r = 0; r < [table numberOfRowsInSection:s]; r++) {
            UITableViewCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:r inSection:s]];
            if (!cell) continue;
            __block BOOL isAlbumRow = NO;
            SGForEachView(cell, ^(UIView *v) {
                if ([v.accessibilityIdentifier containsString:@"album"] ||
                    [v.accessibilityLabel.lowercaseString containsString:@"album"]) {
                    isAlbumRow = YES;
                }
            });
            if (isAlbumRow) {
                NSString *album = findAlbumInObject(cell, 0);
                if (album.length && ![album.lowercaseString containsString:@"go to"]) return album;
            }
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
