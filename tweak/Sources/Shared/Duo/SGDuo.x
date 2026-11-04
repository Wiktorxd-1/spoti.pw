#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "SGDuo.h"

BOOL SGIsDuoDevice(void) {
    UIScreen *screen = [UIScreen mainScreen];
    CGFloat scale = screen.scale ?: 1.0;
    if (scale <= 0) return NO;
    CGSize native = screen.nativeBounds.size;
    CGFloat widthPt = native.width / scale;
    CGFloat heightPt = native.height / scale;
    CGFloat minDim = MIN(widthPt, heightPt);
    // iPhone Duo inner display is ~626 pt, outer cover is ~466 pt.
    // Standard iPhones are <= 440 pt; iPads are >= 744 pt.
    return (minDim >= 445.0 && minDim <= 700.0);
}

BOOL SGIsDuoUnfolded(void) {
    if (!SGIsDuoDevice()) return NO;
    UIScreen *screen = [UIScreen mainScreen];
    CGFloat scale = screen.scale ?: 1.0;
    if (scale <= 0) return NO;
    CGSize native = screen.nativeBounds.size;
    CGFloat widthPt = native.width / scale;
    CGFloat heightPt = native.height / scale;
    CGFloat minDim = MIN(widthPt, heightPt);
    return minDim >= 550.0;
}
