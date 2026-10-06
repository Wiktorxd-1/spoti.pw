// Crossfade under Spoof Premium: the fade engine reads the stored crossfade switch,
// but the duration slider only writes the duration, so the fade stayed off at any length.
#import "Core/SGCore.h"
#import "AdBlock.h"

@interface _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation : NSObject
- (BOOL)audioCrossfade;
- (NSInteger)audioCrossfadeTime;
- (void)setAudioCrossfade:(BOOL)on;
- (void)setAudioCrossfadeTime:(NSInteger)time;
@end

%hook _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation

- (BOOL)audioCrossfade {
    BOOL orig = %orig;
    if (orig) return YES;
    if ([self respondsToSelector:@selector(audioCrossfadeTime)]) {
        return [self audioCrossfadeTime] > 0;
    }
    return NO;
}

- (void)setAudioCrossfadeTime:(NSInteger)time {
    %orig(time);
    if ([self respondsToSelector:@selector(setAudioCrossfade:)]) {
        [self setAudioCrossfade:time > 0];
    }
}

%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation"]);
}

