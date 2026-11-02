#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "SGDuo.h"

BOOL SGIsDuoDevice(void) {
    UIScreen *screen = [UIScreen mainScreen];
    CGFloat scale = screen.scale ?: 1.0;
    CGSize native = screen.nativeBounds.size;
    if (scale <= 0) return NO;
    CGFloat widthPt = native.width / scale;
    CGFloat heightPt = native.height / scale;
    CGFloat minDim = MIN(widthPt, heightPt);
    // iPhone Duo outer cover: 1398x2034 @3x (~466 pt wide)
    // iPhone Duo inner display: 1878x2670 @3x (~626 pt wide)
    // Standard iPhones are 375-430 pt wide.
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        if (minDim >= 445.0) return YES;
    }
    return NO;
}
