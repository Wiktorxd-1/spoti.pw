// Player redesign: volume slider under the playback controls, the way Apple Music draws it.
// Operates on the active audio route (hardware speaker, Bluetooth, or Spotify Connect device).
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Player.h"

BOOL SGRPlayerVolumeSliderEnabled(void) {
    return SGFlag(SGRKeyPlayerVolumeSlider, YES);
}

static char kVolumeRowKey;

@interface SGRVolumeRow : UIView
@property (nonatomic, strong) MPVolumeView *volumeView;
@property (nonatomic, strong) UIImageView *minIcon;
@property (nonatomic, strong) UIImageView *maxIcon;
@end

@implementation SGRVolumeRow

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;

    _minIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"speaker.fill"]];
    _minIcon.tintColor = SGRSecondary();
    _minIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_minIcon];

    _maxIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"speaker.wave.3.fill"]];
    _maxIcon.tintColor = SGRSecondary();
    _maxIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_maxIcon];

    _volumeView = [[MPVolumeView alloc] initWithFrame:CGRectZero];
    _volumeView.showsRouteButton = NO;
    _volumeView.showsVolumeSlider = YES;
    [self addSubview:_volumeView];

    [self styleSlider];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accentChanged) name:SGRPlayerAccentDidChangeNotification object:nil];
    return self;
}

- (void)accentChanged {
    [self styleSlider];
}

- (void)styleSlider {
    for (UIView *sub in _volumeView.subviews) {
        if ([sub isKindOfClass:UISlider.class]) {
            UISlider *slider = (UISlider *)sub;
            UIColor *accent = SGRPlayerAccentColor();
            slider.minimumTrackTintColor = accent ?: UIColor.whiteColor;
            slider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.18];
            slider.thumbTintColor = UIColor.whiteColor;
        }
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w < 10) return;

    CGFloat iconSide = 14.0;
    CGFloat iconY = round((h - iconSide) / 2.0);
    CGFloat pad = 24.0;

    _minIcon.frame = CGRectMake(pad, iconY, iconSide, iconSide);
    _maxIcon.frame = CGRectMake(w - pad - iconSide, iconY, iconSide, iconSide);

    CGFloat sliderX = pad + iconSide + 12.0;
    CGFloat sliderW = (w - pad - iconSide) - sliderX - 12.0;
    _volumeView.frame = CGRectMake(sliderX, round((h - 32.0) / 2.0), sliderW, 32.0);

    [self styleSlider];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end

static void attachVolumeRow(UIViewController *unit) {
    if (!SGRPlayerVolumeSliderEnabled()) return;
    UIView *host = unit.viewIfLoaded;
    if (!host) return;

    UIView *superview = host.superview;
    if (![superview isKindOfClass:UIStackView.class]) return;
    UIStackView *stack = (UIStackView *)superview;

    SGRVolumeRow *row = objc_getAssociatedObject(stack, &kVolumeRowKey);
    if (!row) {
        row = [[SGRVolumeRow alloc] initWithFrame:CGRectMake(0, 0, stack.bounds.size.width, 36)];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [row.heightAnchor constraintEqualToConstant:36].active = YES;
        objc_setAssociatedObject(stack, &kVolumeRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (row.superview != stack) {
        NSUInteger index = [stack.arrangedSubviews indexOfObject:host];
        if (index != NSNotFound && index + 1 <= stack.arrangedSubviews.count) {
            [stack insertArrangedSubview:row atIndex:index + 1];
        } else {
            [stack addArrangedSubview:row];
        }
    }
}

%hook _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    attachVolumeRow((UIViewController *)self);
}
%end

%hook _TtC32ReinventFree_ReinventFreeNpvImpl40ReinventFreePlaybackControlsElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    attachVolumeRow((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
