//	KCAnnotationOverlayWindow.h
//
//	A full-screen (all connected displays), borderless, transparent overlay window
//	independent of KCDefaultVisualizerWindow, used to place annotation shapes.
//	`catchesClicks` and shape visibility are decoupled: turning click-catching off hands
//	control back to whatever's underneath without removing shapes already placed -- the
//	window stays visible/ordered front as long as either clicks are being caught or at
//	least one shape is still on screen, and only orders out once both are false.

#import <Cocoa/Cocoa.h>

@interface KCAnnotationOverlayWindow : NSWindow

- (instancetype)init;

// Resizes/repositions the window to cover the current union of NSScreen.screens.
// Called before showing the window so a screen added/removed since last activation
// (e.g. a monitor connected or disconnected) is picked up.
- (void)updateFrameForCurrentScreens;

// Whether clicks on this window place new shapes (YES) or pass through to whatever's
// underneath (NO). Setting this also updates ignoresMouseEvents and the window's
// visibility (it's ordered front while catching clicks, or while any shapes remain, and
// ordered out only once neither is true).
@property (nonatomic, assign, getter=isCatchingClicks) BOOL catchesClicks;

// When YES, newly placed shapes stay on screen until -clearAllShapes is called instead of
// auto-fading after the usual hold+fade delay. Checked once per shape at creation time --
// toggling this doesn't retroactively change shapes already placed.
@property (nonatomic, assign) BOOL persistentAnnotationsEnabled;

// Immediately removes every shape currently on screen, persisting or mid-fade, and cancels
// any pending fades so a stale delayed call can't try to act on an already-removed shape.
- (void)clearAllShapes;

@end
