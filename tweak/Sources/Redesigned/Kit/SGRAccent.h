// The redesign's accent colour in place of Spotify's green (SGRAccent.x), chosen apart from the native
// look's and stored under its own key; unset is #37F200, negative keeps Spotify's own green.
#import <UIKit/UIKit.h>

#define SGRKeyAccent @"spotifyglass.redesign.accent"   // 0xRRGGBB
#define SGRKeyPlainCheckmark @"spotifyglass.redesign.plainCheckmark"
#define SGRKeyPlayerAccentFollowsArtwork @"spotifyglass.redesign.player.accentFollowsArtwork"

extern NSNotificationName const SGRPlayerAccentDidChangeNotification;

UIColor *SGRAccentColor(void);   // nil while Spotify's own green is kept
NSString *SGRAccentLabel(void);  // "#RRGGBB", or the name of Spotify's own
void SGRPickAccent(void);        // the system colour picker over the top of the app, stored on the way out

BOOL SGRPlainCheckmark(void);
BOOL SGRPlayerAccentFollowsArtwork(void);
UIColor *SGRPlayerAccentColor(void);
void SGRSetArtworkPaletteAccent(UIColor *color);

@class SGModRow;
NSArray<SGModRow *> *SGRAppearanceRows(void);   // the accent colour, for the Appearance card
