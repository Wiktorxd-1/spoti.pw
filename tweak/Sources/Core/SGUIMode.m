#import "SGUIMode.h"
#import "SGLog.h"
#import "SGPrefs.h"

BOOL SGRedesignAvailable(void) {
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

BOOL SGRedesignedUI(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        on = SGRedesignedUIStored();
        SGLog(@"ui: %@%@", on ? @"redesigned" : @"native", SGRedesignAvailable() ? @"" : @" (the redesign needs iOS 26)");
    });
    return on;
}

BOOL SGNativeUI(void) {
    return !SGRedesignedUI();
}

BOOL SGRedesignedUIStored(void) {
    return SGRedesignAvailable() && SGFlag(SGKeyRedesign, YES);
}

BOOL SGLiquidGlassEnabled(void) {
    static BOOL enabled;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        enabled = @available(iOS 26.0, *) ? (SGRedesignedUI() && SGFlag(SGRKeyLiquidGlass, YES)) : NO;
    });
    return enabled;
}
