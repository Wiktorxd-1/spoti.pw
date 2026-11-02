#import "Core/SGCore.h"
#import "AdBlock.h"

@interface _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation : NSObject
- (BOOL)audioCrossfade;
- (void)setAudioCrossfade:(BOOL)on;
- (NSInteger)audioCrossfadeTime;
- (void)setAudioCrossfadeTime:(NSInteger)time;
@end

%hook _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation
- (id)initWithScheduler:(id)scheduler {
    id made = %orig;
    if ([made respondsToSelector:@selector(audioCrossfadeTime)] &&
        [made respondsToSelector:@selector(setAudioCrossfade:)]) {
        NSInteger time = [made audioCrossfadeTime];
        [made setAudioCrossfade:time > 0];
    }
    return made;
}

- (BOOL)audioCrossfade {
    if ([self respondsToSelector:@selector(audioCrossfadeTime)] && [self audioCrossfadeTime] > 0) {
        return YES;
    }
    return %orig;
}

- (void)setAudioCrossfadeTime:(NSInteger)time {
    %orig;
    if ([self respondsToSelector:@selector(setAudioCrossfade:)]) {
        [self setAudioCrossfade:time > 0];
    }
}
%end

%ctor {
    if (!SGFlag(SGKeyFakePremium, YES)) return;

    SGRegisterFlagForcer(NO, ^id(NSString *key) {
        if (!key) return nil;
        if ([key hasSuffix:@"crossfade_enabled"]) return @YES;
        if ([key hasSuffix:@"use_playback_settings_crossfade"]) return @NO;
        if ([key hasSuffix:@"use_playback_settings_gapless"]) return @NO;
        if ([key hasSuffix:@"crossfade_migrated_to_ps"]) return @NO;
        if ([key hasSuffix:@"gapless_migrated_to_ps"]) return @NO;
        if ([key hasSuffix:@"supports_crossfade"]) return @YES;
        return nil;
    }, nil);

    %init;
    SGRequireClasses(@[@"_TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation"]);
}
