#import "Core/SGCore.h"
#import "LyricsCache.h"

static const NSUInteger kMaxCacheBytes = 50 * 1024 * 1024;   // 50 MB max
static const NSUInteger kPruneTargetBytes = 45 * 1024 * 1024; // prune down to 45 MB
static NSString *sg_cacheDir;
static dispatch_queue_t sg_cacheQueue;
static NSMutableDictionary<NSString *, NSString *> *sg_cachedCredits;
static NSMutableDictionary<NSString *, NSNumber *> *sg_accessTimes;

static NSString *cacheDirectory(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *base = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        sg_cacheDir = [[base stringByAppendingPathComponent:@"spotifyglass_lyrics"] copy];
        [NSFileManager.defaultManager createDirectoryAtPath:sg_cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
        sg_cacheQueue = dispatch_queue_create("spotifyglass.lyrics_cache", DISPATCH_QUEUE_SERIAL);
        sg_cachedCredits = [NSMutableDictionary dictionary];
        sg_accessTimes = [NSMutableDictionary dictionary];
    });
    return sg_cacheDir;
}

static NSString *filePathForTrack(NSString *trackID) {
    if (!trackID.length) return nil;
    NSString *safeID = [trackID stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [cacheDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", safeID]];
}

static NSDictionary *encodeWord(SGKaraokeWord *w) {
    return @{
        @"t": w.text ?: @"",
        @"s": @(w.start),
        @"e": @(w.end),
        @"j": @(w.joined)
    };
}

static SGKaraokeWord *decodeWord(NSDictionary *d) {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    SGKaraokeWord *w = [SGKaraokeWord new];
    w.text = d[@"t"] ?: @"";
    w.start = [d[@"s"] integerValue];
    w.end = [d[@"e"] integerValue];
    w.joined = [d[@"j"] boolValue];
    return w;
}

static NSDictionary *encodeLine(SGKaraokeLine *line) {
    if (!line) return nil;
    NSMutableArray *words = [NSMutableArray arrayWithCapacity:line.words.count];
    for (SGKaraokeWord *w in line.words) {
        [words addObject:encodeWord(w)];
    }
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:@{
        @"s": @(line.start),
        @"e": @(line.end),
        @"tm": @(line.timing),
        @"al": @(line.align),
        @"w": words
    }];
    if (line.voice.length) d[@"vc"] = line.voice;
    if (line.translation.length) d[@"tr"] = line.translation;
    if (line.backing) {
        NSDictionary *bk = encodeLine(line.backing);
        if (bk) d[@"bk"] = bk;
    }
    if (line.pronunciation) {
        NSDictionary *pr = encodeLine(line.pronunciation);
        if (pr) d[@"pr"] = pr;
    }
    return d;
}

static SGKaraokeLine *decodeLine(NSDictionary *d) {
    if (![d isKindOfClass:NSDictionary.class]) return nil;
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.start = [d[@"s"] integerValue];
    line.end = [d[@"e"] integerValue];
    line.timing = (SGKaraokeTiming)[d[@"tm"] unsignedIntegerValue];
    line.align = (SGKaraokeAlign)[d[@"al"] unsignedIntegerValue];
    line.voice = d[@"vc"];
    line.translation = d[@"tr"];
    NSArray *rawWords = d[@"w"];
    if ([rawWords isKindOfClass:NSArray.class]) {
        NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray arrayWithCapacity:rawWords.count];
        for (NSDictionary *wd in rawWords) {
            SGKaraokeWord *w = decodeWord(wd);
            if (w) [words addObject:w];
        }
        line.words = words;
    }
    if (d[@"bk"]) line.backing = decodeLine(d[@"bk"]);
    if (d[@"pr"]) line.pronunciation = decodeLine(d[@"pr"]);
    return line;
}

static void pruneLRUIfNeeded(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dir = cacheDirectory();
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:dir error:nil];
    if (!files.count) return;

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:files.count];
    NSUInteger totalBytes = 0;

    for (NSString *file in files) {
        if (![file hasSuffix:@".plist"]) continue;
        NSString *path = [dir stringByAppendingPathComponent:file];
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        if (!attrs) continue;
        NSUInteger size = attrs.fileSize;
        totalBytes += size;
        NSDate *date = attrs.fileModificationDate ?: [NSDate dateWithTimeIntervalSince1970:0];
        [entries addObject:@{ @"path": path, @"size": @(size), @"date": date }];
    }

    if (totalBytes <= kMaxCacheBytes) return;

    // Sort ascending by access date (oldest first)
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [(NSDate *)a[@"date"] compare:(NSDate *)b[@"date"]];
    }];

    for (NSDictionary *entry in entries) {
        if (totalBytes <= kPruneTargetBytes) break;
        NSString *path = entry[@"path"];
        NSUInteger size = [entry[@"size"] unsignedIntegerValue];
        if ([fm removeItemAtPath:path error:nil]) {
            totalBytes = (totalBytes > size) ? (totalBytes - size) : 0;
            SGLog(@"lyrics cache: pruned oldest cache file %@", path.lastPathComponent);
        }
    }
}

void SGLyricsCacheStore(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *credit) {
    if (!trackID.length || !lines.count) return;
    cacheDirectory();
    NSString *path = filePathForTrack(trackID);
    if (!path) return;

    if (credit.length) {
        @synchronized (sg_cachedCredits) { sg_cachedCredits[trackID] = credit; }
    }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    @synchronized (sg_accessTimes) { sg_accessTimes[trackID] = @(now); }

    NSMutableArray *lineDicts = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) {
        NSDictionary *enc = encodeLine(line);
        if (enc) [lineDicts addObject:enc];
    }

    NSDictionary *payload = @{
        @"id": trackID,
        @"credit": credit ?: @"",
        @"time": @(now),
        @"lines": lineDicts
    };

    dispatch_async(sg_cacheQueue, ^{
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:payload format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        if (data.length) {
            [data writeToFile:path atomically:YES];
            pruneLRUIfNeeded();
        }
    });
}

NSArray<SGKaraokeLine *> *SGLyricsCacheGet(NSString *trackID) {
    if (!trackID.length) return nil;
    cacheDirectory();
    NSString *path = filePathForTrack(trackID);
    if (!path || ![NSFileManager.defaultManager fileExistsAtPath:path]) return nil;

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;

    NSDictionary *payload = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
    if (![payload isKindOfClass:NSDictionary.class]) return nil;

    NSString *credit = payload[@"credit"];
    if (credit.length) {
        @synchronized (sg_cachedCredits) { sg_cachedCredits[trackID] = credit; }
    }

    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    @synchronized (sg_accessTimes) { sg_accessTimes[trackID] = @(now); }
    // Touch file modification date in background for LRU
    dispatch_async(sg_cacheQueue, ^{
        [NSFileManager.defaultManager setAttributes:@{ NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970:now] } ofItemAtPath:path error:nil];
    });

    NSArray *lineDicts = payload[@"lines"];
    if (![lineDicts isKindOfClass:NSArray.class] || !lineDicts.count) return nil;

    NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray arrayWithCapacity:lineDicts.count];
    for (NSDictionary *ld in lineDicts) {
        SGKaraokeLine *line = decodeLine(ld);
        if (line) [lines addObject:line];
    }
    return lines.count ? lines : nil;
}

NSString *SGLyricsCacheCredit(NSString *trackID) {
    if (!trackID.length) return nil;
    @synchronized (sg_cachedCredits) {
        NSString *c = sg_cachedCredits[trackID];
        if (c) return c;
    }
    // Try reading from cache file
    cacheDirectory();
    NSString *path = filePathForTrack(trackID);
    if (!path || ![NSFileManager.defaultManager fileExistsAtPath:path]) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    NSDictionary *payload = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
    return [payload isKindOfClass:NSDictionary.class] ? payload[@"credit"] : nil;
}

BOOL SGLyricsCacheHas(NSString *trackID) {
    if (!trackID.length) return NO;
    NSString *path = filePathForTrack(trackID);
    return path && [NSFileManager.defaultManager fileExistsAtPath:path];
}

void SGLyricsCacheClear(void) {
    cacheDirectory();
    dispatch_async(sg_cacheQueue, ^{
        [NSFileManager.defaultManager removeItemAtPath:sg_cacheDir error:nil];
        [NSFileManager.defaultManager createDirectoryAtPath:sg_cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
    });
}
