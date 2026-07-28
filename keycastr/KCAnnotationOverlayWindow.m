//	KCAnnotationOverlayWindow.m

#if !__has_feature(objc_arc)
#error "ARC is required for this file -- enable with -fobjc-arc"
#endif

#import "KCAnnotationOverlayWindow.h"
#import "KCAnnotationShapeView.h"
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>

// How long a shape sits at full opacity before it starts fading, and how long the fade
// itself takes. Kept separate so the "hold" can change independently of the "fade".
// Only consulted when persistentAnnotationsEnabled is NO.
static const NSTimeInterval kKCAnnotationShapeHoldDuration = 0.5;
static const NSTimeInterval kKCAnnotationShapeFadeDuration = 1.5;

// Unions every screen's full frame, then caps the top edge so it never covers a menu bar.
// Deliberately NOT screen.visibleFrame for the union itself -- visibleFrame also excludes
// the Dock, which would needlessly shrink the annotatable area on whichever edge the Dock
// occupies. Only the top (menu bar) needs excluding.
//
// Each screen in extended-desktop mode gets its OWN menu bar at its own top edge (macOS
// default since "Displays have separate Spaces" in Mavericks) -- not just the primary
// screen -- so this is computed per screen, not once for screens[0]. NSMaxY(visibleFrame)
// is exactly screen.frame's top edge minus that screen's own menu bar height: the Dock can
// only occupy the bottom/left/right edges, never the top, so it never affects this value.
//
// Because the overlay is a single rectangle, it can't perfectly exclude two different
// per-screen strips if screens have mismatched heights/positions -- capping the union's
// top at the LOWEST safe ceiling across all screens guarantees no menu bar is ever
// covered, at the cost of possibly excluding a bit more canvas than strictly necessary on
// a mismatched multi-monitor layout.
static NSRect KCAnnotationOverlayFrame(void) {
    NSArray<NSScreen *> *screens = NSScreen.screens;
    if (screens.count == 0) {
        return NSZeroRect;
    }

    NSRect unionFrame = screens.firstObject.frame;
    CGFloat safeTop = CGFLOAT_MAX;
    for (NSScreen *screen in screens) {
        unionFrame = NSUnionRect(unionFrame, screen.frame);
        safeTop = MIN(safeTop, NSMaxY(screen.visibleFrame));
    }

    if (NSMaxY(unionFrame) > safeTop) {
        unionFrame.size.height = safeTop - NSMinY(unionFrame);
    }

    return unionFrame;
}

// Whether any on-screen window, owned by a process other than this one, is currently
// sitting at the popup-menu window level -- i.e. another application's open menu bar
// dropdown or context menu. NSMenuDidBeginTrackingNotification only covers menus within
// this process (NSNotificationCenter's default center is process-local), so this is the
// supplementary check for everyone else's menus, driven by the global mouse monitor below.
static BOOL KCAnyForeignMenuIsOpen(void) {
    CGWindowLevel popUpMenuLevel = CGWindowLevelForKey(kCGPopUpMenuWindowLevelKey);
    pid_t ourPID = NSProcessInfo.processInfo.processIdentifier;

    NSArray<NSDictionary *> *windowInfoList = (__bridge_transfer NSArray *)CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    for (NSDictionary *info in windowInfoList) {
        NSNumber *layer = info[(__bridge NSString *)kCGWindowLayer];
        NSNumber *ownerPID = info[(__bridge NSString *)kCGWindowOwnerPID];
        if (layer.integerValue == popUpMenuLevel && ownerPID.intValue != ourPID) {
            return YES;
        }
    }
    return NO;
}

@implementation KCAnnotationOverlayWindow {
    NSInteger _menuTrackingCount;
    BOOL _foreignMenuDetected;
    id _foreignMenuGlobalMonitor;
}

- (instancetype)init
{
    return [self initWithContentRect:KCAnnotationOverlayFrame()
                            styleMask:NSWindowStyleMaskBorderless
                              backing:NSBackingStoreBuffered
                                defer:NO];
}

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)styleMask backing:(NSBackingStoreType)backing defer:(BOOL)defer
{
    if (!(self = [super initWithContentRect:contentRect styleMask:styleMask backing:backing defer:defer]))
        return nil;

    // One level above the keystroke bezel (KCDefaultVisualizerWindow, also
    // NSScreenSaverWindowLevel) so annotation shapes are unambiguously always on top of
    // it, rather than relying on which window happened to be ordered front more recently.
    // Both are still free to be visible at the same time without either hiding the other,
    // since both have fully transparent backgrounds outside their actual painted content.
    self.level = NSScreenSaverWindowLevel + 1;
    self.opaque = NO;
    self.backgroundColor = NSColor.clearColor;
    self.hasShadow = NO;
    self.ignoresMouseEvents = YES;
    self.movableByWindowBackground = NO;

    // Follows the user across Spaces/full-screen apps like the bezel window; Stationary
    // and IgnoresCycle keep it out of Mission Control's window-shuffle and app-switcher
    // handling, since it has no real content to show there.
    self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
        | NSWindowCollectionBehaviorStationary
        | NSWindowCollectionBehaviorIgnoresCycle;

    // A menu's dropdown/context-menu rendering is a separate, transient window at a much
    // lower level than this one (nowhere near NSScreenSaverWindowLevel), positioned
    // wherever it was invoked -- not confined to the menu bar strip KCAnnotationOverlayFrame
    // already excludes. Without this, this window would still win the hit-test over any
    // open menu's items and swallow clicks meant for them. object:nil observes any menu
    // tracking, not just a specific one (e.g. our own status menu specifically).
    //
    // Registered once here since this window is created lazily on first use and lives for
    // the rest of the app's life afterward -- same lifetime pattern as the observers
    // KCDefaultVisualizerWindow registers in its own init, never removed.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(menuDidBeginTracking:)
                                                 name:NSMenuDidBeginTrackingNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(menuDidEndTracking:)
                                                 name:NSMenuDidEndTrackingNotification
                                               object:nil];

    // Handles displays being connected/disconnected/resized while the app is already running
    // -- plugging in or unplugging a projector mid-session, or a display waking from sleep.
    // -updateFrameForCurrentScreens is otherwise only called when click-catching is switched
    // ON, so without this a projector connected while annotation mode was already active
    // wouldn't be covered by the overlay at all (clicks there would place nothing) until the
    // mode was toggled off and back on. KCDefaultVisualizerWindow observes the same
    // notification for the equivalent reason; this window needs it just as much.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenParametersDidChange:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];

    return self;
}

- (void)screenParametersDidChange:(NSNotification *)notification
{
    [self updateFrameForCurrentScreens];
}

// NSNotificationCenter's default center is process-local: this reliably catches KeyCastr's
// own menus (e.g. the status bar menu, the concrete bug this exists for), but NOT other
// applications' menu bars or context menus, which post to their own process's notification
// center, unreachable from here. A true system-wide fix would need something heavier (e.g.
// Accessibility API observation of menu-opened notifications) -- not built speculatively
// here unless testing confirms the gap actually matters in practice.
//
// A counter rather than a plain bool, so nested tracking sessions (e.g. hovering into a
// submenu and back out while its parent stays open) resolve correctly: only fully
// un-suspended once every currently-tracking menu this process knows about has ended.
- (void)menuDidBeginTracking:(NSNotification *)notification
{
    _menuTrackingCount++;
    [self updateIgnoresMouseEvents];
}

- (void)menuDidEndTracking:(NSNotification *)notification
{
    _menuTrackingCount = MAX(0, _menuTrackingCount - 1);
    [self updateIgnoresMouseEvents];
}

// ignoresMouseEvents is computed from three independent factors: whether annotation mode
// is on (_catchesClicks), whether one of THIS process's own menus is currently tracking
// (_menuTrackingCount), and whether a menu belonging to some OTHER process was last seen
// open (_foreignMenuDetected). Keeping these orthogonal means suspending for a menu never
// changes what _catchesClicks itself reports, so click-catching always resumes to exactly
// the state it was in before the menu opened (back on if annotation mode was on, still off
// if it wasn't).
- (void)updateIgnoresMouseEvents
{
    self.ignoresMouseEvents = !_catchesClicks || _menuTrackingCount > 0 || _foreignMenuDetected;
}

// Only active while annotation mode is on, so there's no added overhead the rest of the
// time. NSMenuDidBeginTrackingNotification can't see other processes' menus, so this is
// the supplementary path: a global monitor observes clicks happening anywhere on screen
// (this app already holds the Accessibility/Input Monitoring trust that makes that
// possible, via the same permission KCEventTap's own system-wide capture relies on) and
// re-checks KCAnyForeignMenuIsOpen() on each one. This works because opening a menu and
// clicking an item within it are two separate clicks -- the check triggered by the
// *opening* click has time to run and update _foreignMenuDetected before the *selecting*
// click happens moments later.
- (void)startObservingForeignMenus
{
    if (_foreignMenuGlobalMonitor != nil) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    _foreignMenuGlobalMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:(NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp | NSEventMaskRightMouseDown | NSEventMaskRightMouseUp)
                                                                        handler:^(NSEvent *event) {
        [weakSelf refreshForeignMenuDetection];
    }];
    [self refreshForeignMenuDetection];
}

- (void)stopObservingForeignMenus
{
    if (_foreignMenuGlobalMonitor != nil) {
        [NSEvent removeMonitor:_foreignMenuGlobalMonitor];
        _foreignMenuGlobalMonitor = nil;
    }
    _foreignMenuDetected = NO;
}

- (void)refreshForeignMenuDetection
{
    BOOL detected = KCAnyForeignMenuIsOpen();
    if (detected == _foreignMenuDetected) {
        return;
    }
    _foreignMenuDetected = detected;
    [self updateIgnoresMouseEvents];
}

- (void)updateFrameForCurrentScreens
{
    [self setFrame:KCAnnotationOverlayFrame() display:NO];
}

- (void)setCatchesClicks:(BOOL)catchesClicks
{
    if (_catchesClicks == catchesClicks) {
        return;
    }

    _catchesClicks = catchesClicks;

    if (catchesClicks) {
        [self startObservingForeignMenus];
    } else {
        [self stopObservingForeignMenus];
    }
    [self updateIgnoresMouseEvents];

    if (catchesClicks) {
        [self updateFrameForCurrentScreens];
    }

    [self updateVisibility];
}

// The window stays visible as long as it's either catching clicks or still showing at
// least one shape, and only orders out once neither is true -- this is what lets
// "annotation mode off" stop catching clicks without hiding shapes already placed.
- (void)updateVisibility
{
    BOOL shouldBeVisible = _catchesClicks || self.contentView.subviews.count > 0;
    if (shouldBeVisible) {
        [self orderFront:nil];
    } else {
        [self orderOut:nil];
    }
}

// This window (not a custom content view) is the right hook for clicks: our content view
// is the window's plain, unmodified default NSView, which doesn't override mouseDown:, so
// NSResponder's default behavior bubbles the event up the responder chain to the window
// itself. KCDefaultVisualizerWindow already relies on this exact same mechanism for its
// drag-to-reposition mouseDown:/mouseUp: overrides, so it's a proven pattern in this
// codebase. A custom content view subclass would only be needed if we wanted to intercept
// the click before it reaches the window (e.g. to inspect/consume it differently per
// subview), which isn't the case here -- every click within the window's frame should
// spawn a shape, unless it lands on the keystroke bezel window (see below).
- (void)mouseDown:(NSEvent *)event
{
    NSPoint screenPoint = [self convertPointToScreen:event.locationInWindow];
    NSWindow *bezelWindow = [self currentBezelWindow];

    if (bezelWindow != nil && NSPointInRect(screenPoint, bezelWindow.frame)) {
        [self forwardEvent:event ofType:NSEventTypeLeftMouseDown atScreenPoint:screenPoint toWindow:bezelWindow];
        return;
    }

    [self spawnShapeAtPoint:event.locationInWindow];
    [super mouseDown:event];
}

// Locates the keystroke bezel window (KCDefaultVisualizerWindow) among the app's windows
// at runtime. This target has no compile-time visibility into that class -- it lives in
// the KCDefaultVisualizer plugin bundle, loaded dynamically, not linked here -- so it's
// identified by class name via NSApp.windows rather than a typed reference.
- (NSWindow *)currentBezelWindow
{
    for (NSWindow *window in NSApp.windows) {
        if ([NSStringFromClass(window.class) isEqualToString:@"KCDefaultVisualizerWindow"]) {
            return window;
        }
    }
    return nil;
}

// Relays a click that landed on the bezel window's frame to the bezel window itself,
// reusing its existing mouseDown:/drag-handling wholesale (including side effects like
// suspending its fade animations during the drag, and marking itself for a post-drag width
// recalculation) rather than reimplementing a parallel version of "drag to reposition"
// here, which would silently drop those side effects and drift out of sync over time.
//
// -[NSWindow mouseDown:]'s default implementation, via movableByWindowBackground, runs its
// own internal event-tracking loop that pulls subsequent mouseDragged:/mouseUp: events
// directly from the event queue rather than waiting for normal per-window dispatch -- the
// same pattern used by control tracking and split-view divider dragging. So forwarding
// just this one mouseDown: is expected to be sufficient for the whole drag gesture. If
// dragging turns out janky or doesn't track the mouse correctly in practice, the fallback
// is to also explicitly forward mouseDragged:/mouseUp: here, tracking our own "currently
// forwarding to the bezel" state across the gesture -- a more verbose variant of this same
// forwarding approach, not a different one.
- (void)forwardEvent:(NSEvent *)event ofType:(NSEventType)type atScreenPoint:(NSPoint)screenPoint toWindow:(NSWindow *)window
{
    NSPoint windowPoint = NSMakePoint(screenPoint.x - NSMinX(window.frame),
                                       screenPoint.y - NSMinY(window.frame));

    NSEvent *forwardedEvent = [NSEvent mouseEventWithType:type
                                                  location:windowPoint
                                             modifierFlags:event.modifierFlags
                                                 timestamp:event.timestamp
                                              windowNumber:window.windowNumber
                                                   context:nil
                                               eventNumber:event.eventNumber
                                                clickCount:event.clickCount
                                                  pressure:event.pressure];

    [window sendEvent:forwardedEvent];
}

- (void)spawnShapeAtPoint:(NSPoint)point
{
    KCAnnotationShapeView *shapeView = [[KCAnnotationShapeView alloc] initWithCenter:point];
    [self.contentView addSubview:shapeView];

    if (_persistentAnnotationsEnabled) {
        return;
    }

    // Scheduled per-shapeView (via the `withObject:` argument), so concurrent shapes from
    // multiple clicks fade independently -- this doesn't cancel or interfere with any
    // other shape's pending fade.
    [self performSelector:@selector(beginFadeForShapeView:)
                withObject:shapeView
                afterDelay:kKCAnnotationShapeHoldDuration];
}

- (void)beginFadeForShapeView:(KCAnnotationShapeView *)shapeView
{
    __weak typeof(self) weakSelf = self;
    [CATransaction begin];
    [CATransaction setAnimationDuration:kKCAnnotationShapeFadeDuration];
    [CATransaction setDisableActions:NO];
    [CATransaction setCompletionBlock:^{
        [shapeView removeFromSuperview];
        [weakSelf updateVisibility];
    }];
    shapeView.layer.opacity = 0.0;
    [CATransaction commit];
}

- (void)clearAllShapes
{
    // Copy first -- removeFromSuperview mutates contentView.subviews, so iterating the
    // live array directly would crash ("mutated while being enumerated").
    for (KCAnnotationShapeView *shapeView in [self.contentView.subviews copy]) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                  selector:@selector(beginFadeForShapeView:)
                                                    object:shapeView];
        [shapeView removeFromSuperview];
    }
    [self updateVisibility];
}

- (BOOL)canBecomeKeyWindow
{
    return NO;
}

- (BOOL)canBecomeMainWindow
{
    return NO;
}

@end
