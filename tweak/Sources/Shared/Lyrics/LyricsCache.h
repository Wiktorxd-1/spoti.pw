#import <Foundation/Foundation.h>
#import "Lyrics.h"

// 50 MB max persistent disk cache with LRU eviction for offline lyrics.
void SGLyricsCacheStore(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *credit);
NSArray<SGKaraokeLine *> *SGLyricsCacheGet(NSString *trackID);
NSString *SGLyricsCacheCredit(NSString *trackID);
BOOL SGLyricsCacheHas(NSString *trackID);
void SGLyricsCacheClear(void);
