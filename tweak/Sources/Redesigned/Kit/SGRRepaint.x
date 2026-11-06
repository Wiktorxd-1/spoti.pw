#import "Core/SGCore.h"
#import "SGRRepaint.h"

__weak UIView *sgr_nowPlayingRoot = nil;
__weak UIView *sgr_nowPlayingCard = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;
__weak UIView *sgr_albumRoot = nil;
__weak UIView *sgr_artistRoot = nil;
__weak UIView *sgr_homeRoot = nil;
__weak UIView *sgr_playerRoot = nil;
__weak UIView *sgr_landscapeRoot = nil;

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (color && (sgr_nowPlayingRoot || sgr_lyricsPageRoot || sgr_playlistRoot || sgr_albumRoot || sgr_artistRoot || sgr_homeRoot || sgr_playerRoot || sgr_landscapeRoot)) {
        UIView *view = (UIView *)self.delegate;
        if ([view isKindOfClass:UIView.class] && view.layer == self && !SGKeepsColor(view)) {
            if (SGIsInside(view, sgr_nowPlayingRoot)) {
                if (SGLooksLikeCard(view, color) && sgr_nowPlayingCard != view) {
                    sgr_nowPlayingCard = view;
                    UIView *bar = sgr_nowPlayingRoot;
                    dispatch_async(dispatch_get_main_queue(), ^{ [bar.superview setNeedsLayout]; });
                }
                color = NULL;
            } else if (SGIsInside(view, sgr_lyricsPageRoot)) {
                color = NULL;
            } else if (SGIsBaseSurface(color) && (SGIsInside(view, sgr_playlistRoot) || SGIsInside(view, sgr_albumRoot) || SGIsInside(view, sgr_artistRoot) || SGIsInside(view, sgr_playerRoot) || SGIsInside(view, sgr_landscapeRoot))) {
                color = NULL;
            } else if (SGIsBaseSurface(color) && sgr_homeRoot && SGIsInside(view, sgr_homeRoot)) {
                // Only strip base-surface backgrounds from views within the aura gradient band
                // (~650 pt from the top of the page list), so cells further down keep their
                // own backgrounds and the entire home page doesn't turn transparent.
                CGRect frameInHome = [view convertRect:view.bounds toView:sgr_homeRoot];
                if (CGRectGetMinY(frameInHome) < 650.0) color = NULL;
            }
        }
    }
    %orig(color);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
