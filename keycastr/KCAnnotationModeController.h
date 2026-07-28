//	KCAnnotationModeController.h
//
//	Owns "is annotation mode on," "are placed annotations persistent," and clearing them --
//	the single source of truth all triggers (hotkeys, menu items) call into, so any UI
//	(e.g. menu item checkmarks) stays in sync regardless of which trigger changed state.
//	Drives a dedicated KCAnnotationOverlayWindow (full-screen, independent of
//	KCDefaultVisualizerWindow, the keystroke bezel) via two hardcoded global hotkeys:
//	Control+Option+A toggles annotation mode (click-catching), Control+Option+C clears all
//	currently-placed annotations.

#import <Cocoa/Cocoa.h>

@class KCKeystroke;

@interface KCAnnotationModeController : NSObject

@property (nonatomic, readonly, getter=isAnnotationModeEnabled) BOOL annotationModeEnabled;
@property (nonatomic, readonly, getter=isPersistentAnnotationsEnabled) BOOL persistentAnnotationsEnabled;

// Checks whether `keystroke` matches one of the annotation hotkeys; if so, performs the
// matching action and returns YES so the caller can stop further processing of this
// keystroke.
- (BOOL)handleKeystroke:(KCKeystroke *)keystroke;

// Toggles whether the overlay window is currently catching clicks to place new shapes.
// Independent of shape visibility: turning this off hands control back to whatever's
// underneath without removing or hiding shapes already placed.
- (void)toggleAnnotationMode;

// Toggles whether newly placed shapes auto-fade (off) or persist until manually cleared
// (on). Every trigger (hotkey, menu item, anything added later) for either of these
// toggles should call the methods here directly rather than duplicating the logic.
- (void)togglePersistentAnnotations;

// Immediately removes every annotation shape currently on screen.
- (void)clearAnnotations;

@end
