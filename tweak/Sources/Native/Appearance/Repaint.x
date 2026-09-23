// Keeps the areas the native look's tweaks stripped transparent when Spotify repaints them.
#import "Core/SGCore.h"
#import "Repaint.h"

__weak UIView *sg_lyricsCardRoot = nil;
__weak UIView *sg_lyricsPageRoot = nil;
__weak UIView *sg_homeRoot = nil;
__weak UIView *sg_npvBackdropRoot = nil;

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (color && (sg_lyricsCardRoot || sg_lyricsPageRoot || sg_homeRoot || sg_npvBackdropRoot)) {
        UIView *view = (UIView *)self.delegate;
        if ([view isKindOfClass:UIView.class] && view.layer == self && !SGKeepsColor(view)) {
            UIView *match = nil;
            for (UIView *v = view; v; v = v.superview) {
                if ([v isKindOfClass:UIVisualEffectView.class]) break;
                if (v == sg_lyricsCardRoot || v == sg_lyricsPageRoot || v == sg_npvBackdropRoot || v == sg_homeRoot) {
                    match = v;
                    break;
                }
            }
            if (match == sg_lyricsCardRoot || match == sg_lyricsPageRoot || match == sg_npvBackdropRoot) {
                color = NULL;
            } else if (match == sg_homeRoot && SGIsBaseSurface(color)) {
                color = NULL;
            }
        }
    }
    %orig(color);
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
}
