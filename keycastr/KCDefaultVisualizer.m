//	Copyright (c) 2009 Stephen Deken
//	Copyright (c) 2014-2024 Andrew Kitchen
//
//	All rights reserved.
//
//	Redistribution and use in source and binary forms, with or without modification,
//	are permitted provided that the following conditions are met:
//
//	*	Redistributions of source code must retain the above copyright notice, this
//		list of conditions and the following disclaimer.
//	*	Redistributions in binary form must reproduce the above copyright notice,
//		this list of conditions and the following disclaimer in the documentation
//		and/or other materials provided with the distribution.
//	*	Neither the name KeyCastr nor the names of its contributors may be used to
//		endorse or promote products derived from this software without specific
//		prior written permission.
//
//	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//	AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//	WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//	IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//	INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//	BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//	DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
//	LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
//	OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
//	ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#if !__has_feature(objc_arc)
#error "ARC is required for this file -- enable with -fobjc-arc"
#endif

#import "KCDefaultVisualizer.h"
#import "KCKeystroke.h"
#import "KCMouseEvent.h"
#import "NSBezierPath+RoundedRect.h"
#import "NSUserDefaults+Utility.h"


// TODO: seems this should be based on the font height, or shouldn't be needed at all
static const CGFloat kKCDefaultBezelHeight = 32.0;
static const CGFloat kKCDefaultBezelPadding = 10.0;


@implementation KCDefaultVisualizerFactory

-(NSString*) visualizerNibName
{
	return @"KCDefaultVisualizer";
}

-(Class) visualizerClass
{
	return [KCDefaultVisualizer class];
}

-(NSString*) visualizerName
{
	return @"Default";
}

@end


@implementation KCDefaultVisualizerPreferencesView

@synthesize commandKeysOnlyButton, allModifiedKeysButton, allKeysButton;
@synthesize collapseRepeatedShortcutsButton, collapseLongTypingButton, showHeldModifiersButton;

@end


@implementation KCDefaultVisualizer

@dynamic preferencesView;

- (instancetype)init
{
    if (!(self = [super init]))
        return nil;

    visualizerWindow = [[KCDefaultVisualizerWindow alloc] init];

    return self;
}

-(NSString*) visualizerName
{
	return @"Default";
}

-(void) awakeFromNib
{
    [super awakeFromNib];
    [self configureDisplayModeWithDefaults:NSUserDefaults.standardUserDefaults];

    NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
    self.preferencesView.collapseRepeatedShortcutsButton.state = [userDefaults boolForKey:@"default.collapseRepeatedShortcuts"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.preferencesView.collapseLongTypingButton.state = [userDefaults boolForKey:@"default.collapseLongTyping"] ? NSControlStateValueOn : NSControlStateValueOff;
    self.preferencesView.showHeldModifiersButton.state = [userDefaults boolForKey:@"default.showHeldModifiers"] ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)configureDisplayModeWithDefaults:(NSUserDefaults *)userDefaults
{
    if ([userDefaults boolForKey:@"default.commandKeysOnly"]) {
        _displayMode = KCDefaultVisualizerDisplayOptionCommandKeysOnly;
    } else if ([userDefaults boolForKey:@"default.allModifiedKeys"]) {
        _displayMode = KCDefaultVisualizerDisplayOptionAllModifiedKeys;
    } else {
        _displayMode = KCDefaultVisualizerDisplayOptionAllKeys;
    }
}

- (IBAction)preferencesViewDidSelectDisplayOption:(id)sender
{
    KCDefaultVisualizerDisplayOption mode = KCDefaultVisualizerDisplayOptionDefault;
    if (sender == self.preferencesView.commandKeysOnlyButton) {
        mode = KCDefaultVisualizerDisplayOptionCommandKeysOnly;
    }
    else if (sender == self.preferencesView.allModifiedKeysButton) {
        mode = KCDefaultVisualizerDisplayOptionAllModifiedKeys;
    }
    else if (sender == self.preferencesView.allKeysButton) {
        mode = KCDefaultVisualizerDisplayOptionAllKeys;
    }
    
    [self setDisplayMode:mode];
}

- (void)setDisplayMode:(KCDefaultVisualizerDisplayOption)mode
{
    _displayMode = mode;

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:(mode == KCDefaultVisualizerDisplayOptionCommandKeysOnly) forKey:@"default.commandKeysOnly"];
    [userDefaults setBool:(mode == KCDefaultVisualizerDisplayOptionAllModifiedKeys) forKey:@"default.allModifiedKeys"];
    [userDefaults setBool:(mode == KCDefaultVisualizerDisplayOptionAllKeys) forKey:@"default.allKeys"];
}

- (IBAction)preferencesViewDidToggleCheckbox:(id)sender
{
    NSButton *button = (NSButton *)sender;
    BOOL isOn = button.state == NSControlStateValueOn;
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

    if (sender == self.preferencesView.collapseRepeatedShortcutsButton) {
        [userDefaults setBool:isOn forKey:@"default.collapseRepeatedShortcuts"];
    }
    else if (sender == self.preferencesView.collapseLongTypingButton) {
        [userDefaults setBool:isOn forKey:@"default.collapseLongTyping"];
    }
    else if (sender == self.preferencesView.showHeldModifiersButton) {
        [userDefaults setBool:isOn forKey:@"default.showHeldModifiers"];
    }
}

-(void) showVisualizer:(id)sender
{
	[visualizerWindow orderFront:self];
}

-(void) hideVisualizer:(id)sender
{
	[visualizerWindow orderOut:self];
}

-(void) deactivateVisualizer:(id)sender
{
	[visualizerWindow orderOut:self];
}

- (BOOL)shouldOnlyDisplayCommandKeys
{
    return _displayMode == KCDefaultVisualizerDisplayOptionCommandKeysOnly;
}

- (BOOL)shouldOnlyDisplayModifiedKeys
{
    return _displayMode == KCDefaultVisualizerDisplayOptionAllModifiedKeys;
}

- (void)noteKeyEvent:(KCKeystroke *)keystroke
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_showHeldModifierGlyphs) object:nil];

    if (![keystroke isCommand] && [self shouldOnlyDisplayCommandKeys]) {
        return;
    }

    if (![keystroke isModified] && [self shouldOnlyDisplayModifiedKeys]) {
        return;
    }

    [visualizerWindow addKeystroke:keystroke];
}

- (void)noteMouseEvent:(KCMouseEvent *)mouseEvent
{
    [visualizerWindow addMouseEvent:mouseEvent];
}

- (void)noteFlagsChanged:(NSEventModifierFlags)flags
{
    // Independent of the "show held modifiers" preference: keeps track of when a
    // displayed shortcut's modifiers have been released, so the bezel knows when
    // it's allowed to start its fade-out countdown.
    [visualizerWindow noteModifierFlagsChanged:flags];

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"default.showHeldModifiers"]) {
        return;
    }

    NSEventModifierFlags previousFlags = _pendingModifierFlags;

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_showHeldModifierGlyphs) object:nil];

    if (flags == 0) {
        _pendingModifierFlags = 0;
        [visualizerWindow dismissModifierGlyphsIfNeeded];
        return;
    }

    _pendingModifierFlags = flags;

    // Multiple held modifiers don't release atomically at the OS level -- they arrive as
    // separate flagsChanged events. If this looks like a partial release (fewer modifiers
    // than before, none added), wait briefly to see whether it settles at zero rather than
    // flickering the bezel down to a smaller glyph set before it disappears.
    BOOL isPartialRelease = [visualizerWindow isShowingModifierOnlyBezel]
        && flags != previousFlags
        && (flags & ~previousFlags) == 0;

    if (isPartialRelease) {
        [self performSelector:@selector(_showHeldModifierGlyphs) withObject:nil afterDelay:0.1];
        return;
    }

    if ([visualizerWindow isShowingModifierOnlyBezel]) {
        [self _showHeldModifierGlyphs];
        return;
    }

    if ([visualizerWindow hasActiveBezel]) {
        return;
    }

    [self performSelector:@selector(_showHeldModifierGlyphs) withObject:nil afterDelay:0.3];
}

- (void)noteKeyUpEvent:(KCKeycastrEvent *)event
{
    if (![event isKindOfClass:[KCKeystroke class]]) {
        return;
    }
    [visualizerWindow noteKeyUp:((KCKeystroke *)event).keyCode];
}

- (void)noteCapturingDidStop
{
    // -noteFlagsChanged: schedules -_showHeldModifierGlyphs via performSelector:afterDelay:
    // rather than showing the bezel immediately, so a hold that's still mid-chord (modifiers
    // down, final key not pressed yet) can have a call already in flight here with nothing
    // on screen yet -- forceDismissAnyLingeringBezel below only cancels bezels that are
    // already displayed, so without this the scheduled call still fires after capturing has
    // stopped, puts up a bezel for the first time, and then can never be dismissed since all
    // further flagsChanged events are now dropped upstream.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_showHeldModifierGlyphs) object:nil];
    _pendingModifierFlags = 0;

    [visualizerWindow forceDismissAnyLingeringBezel];
}

- (void)_showHeldModifierGlyphs
{
    NSEventModifierFlags flags = _pendingModifierFlags;
    NSMutableString *glyphs = [NSMutableString string];
    if (flags & NSEventModifierFlagControl) [glyphs appendString:@"⌃"];
    if (flags & NSEventModifierFlagOption)  [glyphs appendString:@"⌥"];
    if (flags & NSEventModifierFlagShift)   [glyphs appendString:@"⇧"];
    if (flags & NSEventModifierFlagCommand) [glyphs appendString:@"⌘"];

    if (glyphs.length > 0) {
        [visualizerWindow showModifierGlyphs:glyphs];
    }
}

+ (NSDictionary<NSString *, NSObject *> *)visualizerDefaults
{
    return @{ @"default.commandKeysOnly": @YES,
              @"default.collapseRepeatedShortcuts": @YES,
              @"default.collapseLongTyping": @YES,
              @"default.typingBurstThreshold": @4,
              @"default.showHeldModifiers": @YES,
              @"default.fadeDelay": @2.0,
              @"default.fadeDuration": @0.2,
              @"default.fontSize": @16.0,
              @"default.typingIndicatorFontSize": @16.0,
              @"default.keystrokeDelay": @0.5,
              @"default.bezelColor": [NSKeyedArchiver archivedDataWithRootObject:[NSColor colorWithCalibratedWhite:0 alpha:0.8]
                                                           requiringSecureCoding:NO
                                                                           error:NULL],
              @"default.textColor": [NSKeyedArchiver archivedDataWithRootObject:[NSColor colorWithCalibratedWhite:1 alpha:1]
                                                          requiringSecureCoding:NO
                                                                          error:NULL],
              @"default_displayModifiedCharacters": @NO,
    };
}

@end

static NSRect KC_defaultFrameForScreen(NSScreen *screen) {
    NSRect screenFrame = screen.frame;
    CGFloat width = NSWidth(screenFrame) - 2 * kKCDefaultBezelPadding;
    return NSMakeRect(NSMinX(screenFrame) + kKCDefaultBezelPadding,
                       NSMinY(screenFrame) + kKCDefaultBezelPadding,
                       width,
                       kKCDefaultBezelHeight);
}

// Used when the bezel has no valid saved position to fall back to (e.g. its screen was
// disconnected). Picks the largest connected screen, since that's almost always the
// projector/external display in a presentation setup.
static NSScreen *KC_bestAvailableScreen(void) {
    NSScreen *best = nil;
    CGFloat bestArea = -1;
    for (NSScreen *screen in NSScreen.screens) {
        NSRect frame = screen.frame;
        CGFloat area = NSWidth(frame) * NSHeight(frame);
        if (area > bestArea) {
            bestArea = area;
            best = screen;
        }
    }
    return best ?: NSScreen.mainScreen;
}

// Whether a point (typically a window's origin) currently falls within any connected
// screen's bounds -- as opposed to just NSScreen.mainScreen, which for a background
// utility like this is essentially "whichever screen has the menu bar" and has nothing
// to do with which screen the bezel was actually left on.
static BOOL KC_pointIsOnAnyScreen(NSPoint point) {
    for (NSScreen *screen in NSScreen.screens) {
        NSRect boundingRect = NSInsetRect(screen.frame, kKCDefaultBezelPadding, kKCDefaultBezelPadding);
        if (NSPointInRect(point, boundingRect)) {
            return YES;
        }
    }
    return NO;
}

// The modifier bits a displayed shortcut can depend on; used to know which keys we're
// still waiting to see released before the bezel is allowed to start fading out.
static const NSEventModifierFlags kKCTrackedModifierFlags = NSEventModifierFlagControl
    | NSEventModifierFlagOption
    | NSEventModifierFlagShift
    | NSEventModifierFlagCommand;

@implementation KCDefaultVisualizerWindow {
	BOOL _shouldResize;
	BOOL _dragging;

    KCDefaultVisualizerBezelView* _awaitingReleaseBezelView;
    NSEventModifierFlags _awaitingReleaseModifierFlags;
    uint16_t _awaitingReleaseKeyCode;
    BOOL _awaitingReleaseKeyCodeStillDown;
    BOOL _isAwaitingFullRelease;
    NSUInteger _forceDismissGeneration;
}

- (instancetype)init
{
    return [self initWithContentRect:KC_defaultFrameForScreen(KC_bestAvailableScreen())
                           styleMask:NSWindowStyleMaskBorderless
                             backing:NSBackingStoreBuffered
                               defer:NO];
}

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)styleMask backing:(NSBackingStoreType)backing defer:(BOOL)defer
{
    if (!(self = [super initWithContentRect:contentRect styleMask:styleMask backing:backing defer:defer]))
        return nil;
    
    _runningAnimations = [[NSMutableArray alloc] init];

    [self setFrameUsingName:@"KCBezelWindow default.bezelWindow" force:YES];
    [self setFrameAutosaveName:@"KCBezelWindow default.bezelWindow"];
    [self resizePreservingHeight:NO];
    [self repositionIfOffscreen];

    [self setLevel:NSScreenSaverWindowLevel];
    [self setOpaque:NO];

    [self setBackgroundColor:[NSColor clearColor]];
    [self setAlphaValue:1];

    [self setMovableByWindowBackground:YES];
    [self setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillTerminate:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenParametersDidChange:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];
    return self;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self _suspendAnimations];
    [self resizePreservingHeight:NO];
    [self saveFrameUsingName:self.frameAutosaveName];
}

// Handles displays being connected/disconnected (or resized) while the app is already
// running -- e.g. plugging in or unplugging a projector mid-session. Only repositions
// when the bezel actually ends up somewhere invalid; otherwise leaves a manually-dragged
// position alone.
- (void)screenParametersDidChange:(NSNotification *)notification {
    [self repositionIfOffscreen];
    [self resizePreservingHeight:YES];
    [self saveFrameUsingName:self.frameAutosaveName];
}

- (void)repositionIfOffscreen {
    if (!KC_pointIsOnAnyScreen(self.frame.origin)) {
        NSLog(@"================> Out of range: %@", NSStringFromRect(self.frame));

        [self resetFrame];
    }
}

- (void)resizePreservingHeight:(BOOL)keepHeight {
    NSScreen *screen = self.screen ?: NSScreen.mainScreen;
    NSRect screenRect = screen.frame;

    // Need to calculate a different width if our origin is dragged to a screen to the left
    CGFloat optimalWidth;
    if (NSMinX(self.frame) < NSMinX(screenRect)) {
        optimalWidth = NSMinX(screenRect) - NSMinX(self.frame) - kKCDefaultBezelPadding;
    } else {
        optimalWidth = fabs(NSMaxX(screenRect) - NSMinX(self.frame)) - kKCDefaultBezelPadding;
    }

    CGFloat height;
    if (keepHeight) {
        height = fmaxf(kKCDefaultBezelHeight, NSHeight(self.frame));
    } else {
        height = kKCDefaultBezelHeight;
    }

    NSRect frame = NSMakeRect(NSMinX(self.frame), NSMinY(self.frame), optimalWidth, height);
	[self setFrame:frame display:NO];
}

- (void)resetFrame {
    [self setFrame:KC_defaultFrameForScreen(KC_bestAvailableScreen()) display:NO];
}

- (void)abandonCurrentBezelView {
    // A modifier-only bezel has had BOTH its fade-out and its line-break cancelled by
    // -showModifierGlyphs:, so nothing else is scheduled that would ever remove it from
    // screen. Whoever stops tracking it therefore has to re-arm the fade, or the row is
    // orphaned on screen permanently. -dismissModifierGlyphsIfNeeded used to be the only
    // caller that did that, but -addMouseEvent: also lands here -- a mouse click arriving
    // while a modifier is held (with a mouse display option that routes clicks to this
    // visualizer) would silently strand the held-modifier row forever. Re-arming here
    // instead of at each call site makes every caller correct by construction.
    if (_isModifierOnlyBezel && _currentBezelView != nil) {
        [_currentBezelView scheduleFadeOut];
    }
    _currentBezelView = nil;
    _plainCharCount = 0;
    _isModifierOnlyBezel = NO;
}

// Called once a bezel row's fade-out animation has actually removed it from the view
// hierarchy, so no state keeps pointing at a view that's no longer on screen. Deliberately
// does NOT route through -abandonCurrentBezelView: that re-arms a fade-out, which would be
// meaningless (and would re-schedule work) on a view that has already finished fading.
- (void)noteBezelViewDidFadeOut:(KCDefaultVisualizerBezelView *)bezelView {
    if (bezelView == _currentBezelView) {
        _currentBezelView = nil;
        _plainCharCount = 0;
        _isModifierOnlyBezel = NO;
    }
    if (bezelView == _awaitingReleaseBezelView) {
        _awaitingReleaseBezelView = nil;
        _isAwaitingFullRelease = NO;
    }
}

- (BOOL)hasActiveBezel {
    return _currentBezelView != nil && !_isModifierOnlyBezel;
}

- (BOOL)isShowingModifierOnlyBezel {
    return _currentBezelView != nil && _isModifierOnlyBezel;
}

- (void)showModifierGlyphs:(NSString *)glyphs {
    if (_currentBezelView != nil && _isModifierOnlyBezel) {
        [_currentBezelView setText:glyphs];
    } else {
        [self appendString:glyphs];
        _isModifierOnlyBezel = YES;
    }
    [self _cancelLineBreak];
    [NSObject cancelPreviousPerformRequestsWithTarget:_currentBezelView selector:@selector(beginFadeOut:) object:nil];
}

- (void)dismissModifierGlyphsIfNeeded {
    if (_isModifierOnlyBezel) {
        // -abandonCurrentBezelView re-arms the fade itself now; see the comment there.
        [self abandonCurrentBezelView];
    }
}

// Called whenever a shortcut (modifiers + a key) is displayed. Suppresses the fade-out
// that just got scheduled by the text update, and starts tracking which of the shortcut's
// keys are still held down -- the fade is only re-armed once they've all been released.
- (void)beginAwaitingFullReleaseForKeystroke:(KCKeystroke *)keystroke bezelView:(KCDefaultVisualizerBezelView *)bezelView {
    if (_isAwaitingFullRelease && _awaitingReleaseBezelView != nil && _awaitingReleaseBezelView != bezelView) {
        // A previous shortcut is still displayed but has been superseded by this one;
        // let it fade on its own rather than tracking more than one bezel at a time.
        [_awaitingReleaseBezelView scheduleFadeOut];
    }

    _awaitingReleaseBezelView = bezelView;
    _awaitingReleaseModifierFlags = keystroke.modifierFlags & kKCTrackedModifierFlags;
    _awaitingReleaseKeyCode = keystroke.keyCode;
    _awaitingReleaseKeyCodeStillDown = YES;
    _isAwaitingFullRelease = YES;

    [NSObject cancelPreviousPerformRequestsWithTarget:bezelView selector:@selector(beginFadeOut:) object:nil];
}

- (void)noteModifierFlagsChanged:(NSEventModifierFlags)flags {
    if (!_isAwaitingFullRelease) {
        return;
    }
    _awaitingReleaseModifierFlags &= flags;
    [self _completeAwaitingReleaseIfNeeded];
}

- (void)noteKeyUp:(uint16_t)keyCode {
    if (!_isAwaitingFullRelease || keyCode != _awaitingReleaseKeyCode) {
        return;
    }
    _awaitingReleaseKeyCodeStillDown = NO;
    [self _completeAwaitingReleaseIfNeeded];
}

- (void)_completeAwaitingReleaseIfNeeded {
    if (_awaitingReleaseModifierFlags != 0 || _awaitingReleaseKeyCodeStillDown) {
        return;
    }
    [self _armAwaitingReleaseFadeOut];
}

- (void)_armAwaitingReleaseFadeOut {
    _isAwaitingFullRelease = NO;
    [_awaitingReleaseBezelView scheduleFadeOut];
    _awaitingReleaseBezelView = nil;
}

// Forces any bezel that's frozen awaiting a release signal (a held-modifier display, or a
// shortcut awaiting all its keys to release before it's allowed to start fading) to
// dismiss now via its normal fade-out, rather than staying stuck forever if capturing
// stops before that signal ever arrives -- e.g. toggling casting off via its own hotkey
// while a modifier is still held. The keyUp/flagsChanged-to-zero events that would
// normally resolve either state are silently dropped by KCAppController once
// _isCapturing is NO, so without this they'd never reach here. Bezels that aren't frozen
// (already fading on their own independent timer) are untouched.
- (void)forceDismissAnyLingeringBezel {
    // Bumped so -addKeystroke:'s dispatch_async'd merge-into-existing-bezel block (below)
    // can tell, when it actually runs, whether a force-dismiss happened in the meantime --
    // that block runs one runloop turn after being scheduled, and if capturing stops in that
    // window, this method runs first and (correctly, at that moment) finds nothing frozen
    // yet, since the keystroke hasn't transitioned the bezel into "awaiting full release"
    // yet. Without this, the block would go on to do that transition anyway, immediately
    // after this method already ran, freezing a bezel nothing will ever resolve now that
    // capturing is off.
    _forceDismissGeneration++;

    [self dismissModifierGlyphsIfNeeded];

    if (_isAwaitingFullRelease) {
        [self _armAwaitingReleaseFadeOut];
    }
}

-(void) _cancelLineBreak
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(abandonCurrentBezelView) object:nil];
}

-(void) _scheduleLineBreak
{
	[self performSelector:@selector(abandonCurrentBezelView)
			   withObject:nil
			   afterDelay:[[NSUserDefaults standardUserDefaults] floatForKey:@"default.keystrokeDelay"]];
}

- (void)addMouseEvent:(KCMouseEvent *)mouseEvent
{
    if (NSEventMaskFromType(mouseEvent.type) & (NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown)) {
        [self abandonCurrentBezelView];
        [self appendString:[mouseEvent convertToString]];
    }
}

- (void)addKeystroke:(KCKeystroke *)keystroke
{
    [self _cancelLineBreak];

    NSString *string = [keystroke convertToString];
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    BOOL collapseRepeats = [userDefaults boolForKey:@"default.collapseRepeatedShortcuts"];
    BOOL collapseLongTyping = [userDefaults boolForKey:@"default.collapseLongTyping"];
    NSUInteger typingThreshold = [userDefaults integerForKey:@"default.typingBurstThreshold"];

    if (_isModifierOnlyBezel && _currentBezelView != nil)
    {
        _isModifierOnlyBezel = NO;
        KCDefaultVisualizerBezelView *bezelToUpdate = _currentBezelView;
        NSUInteger generationAtEnqueue = _forceDismissGeneration;
        dispatch_async(dispatch_get_main_queue(), ^{
            // If -forceDismissAnyLingeringBezel ran between this being scheduled and now,
            // capturing has stopped and nothing will ever deliver the release events that
            // -beginAwaitingFullReleaseForKeystroke:bezelView: below would depend on to
            // un-freeze this bezel -- so don't start awaiting a release that will never
            // come. Just let it fade on its own instead. See the comment on
            // -forceDismissAnyLingeringBezel for why this generation counter exists rather
            // than reading _isCapturing directly (this class has no visibility into it).
            if (self->_forceDismissGeneration != generationAtEnqueue) {
                [bezelToUpdate scheduleFadeOut];
                return;
            }
            [bezelToUpdate setText:string];
            [self beginAwaitingFullReleaseForKeystroke:keystroke bezelView:bezelToUpdate];
        });
        _lastCommandString = string;
        _commandRepeatCount = 1;
        _plainCharCount = [keystroke isCommand] ? 0 : 1;
        [self _scheduleLineBreak];
        return;
    }

    // Both computed here, after the modifier-merge path above has had its chance to return:
    // nothing between this point and their use below mutates the state they read.
    BOOL inTypingBurst = collapseLongTyping && _currentBezelView != nil && _plainCharCount >= typingThreshold;
    BOOL isRepeatOfLastShortcut = collapseRepeats && _currentBezelView != nil && [string isEqualToString:_lastCommandString];

    // Gated on -isModified rather than -isCommand so single-modifier shortcuts (Shift+M in
    // Photoshop) collapse to "⇧M ×4" like Cmd+Shift+4 always has. Control/Command repeats
    // still collapse unconditionally, exactly as before; a Shift/Option-only repeat instead
    // yields to collapseLongTyping when a typing burst is already running, so holding Shift
    // to type an all-caps word containing a double letter ("ALL") stays "Typing…" rather
    // than flipping to "⇧L ×2" mid-word. Ordinary mixed-case typing can't reach this gate at
    // all: consecutive characters differ, and any unmodified character clears
    // _lastCommandString below.
    if (isRepeatOfLastShortcut && [keystroke isModified] && ([keystroke isCommand] || !inTypingBurst))
    {
        _commandRepeatCount++;
        [_currentBezelView setText:[NSString stringWithFormat:@"%@ ×%lu", string, (unsigned long)_commandRepeatCount]];
        [self beginAwaitingFullReleaseForKeystroke:keystroke bezelView:_currentBezelView];
        [self _scheduleLineBreak];
        return;
    }

    // Deliberately still -isCommand, NOT -isModified: this branch calls
    // -abandonCurrentBezelView and resets _plainCharCount, so admitting Shift-capitalized
    // letters would tear down an in-progress "Typing…" bezel and restart the burst count on
    // every capital in a sentence -- the exact visual noise collapseLongTyping exists to
    // prevent. Single-modifier shortcuts reach the repeat gate above via _lastCommandString
    // instead, without needing to own a bezel outright.
    if ([keystroke isCommand])
    {
        [self abandonCurrentBezelView];
        _lastCommandString = string;
        _commandRepeatCount = 1;
        _plainCharCount = 0;
        [self appendString:string];
        [self beginAwaitingFullReleaseForKeystroke:keystroke bezelView:_currentBezelView];
        return;
    }

    // Remembering this for modified-but-not-Command keystrokes is what lets the repeat gate
    // above match on the SECOND press of e.g. Shift+M; it used to be cleared unconditionally
    // here, which is why widening that gate alone had no effect. Unmodified characters still
    // clear it, which is what keeps ordinary sentence typing out of the repeat path.
    _lastCommandString = [keystroke isModified] ? string : nil;
    _commandRepeatCount = [keystroke isModified] ? 1 : 0;

    if (inTypingBurst)
    {
        _plainCharCount++;
        CGFloat typingIndicatorFontSize = [userDefaults floatForKey:@"default.typingIndicatorFontSize"];
        [_currentBezelView setText:@"Typing…" fontSize:typingIndicatorFontSize];
        [self _scheduleLineBreak];
        return;
    }

    _plainCharCount++;
    [self appendString:string];
}

- (void)appendString:(NSString *)string
{
	if (_currentBezelView == nil)
	{
        if (!(NSWidth(self.frame) > 0)) {
            NSLog(@"Fixing frame; width not greater than 0: %@", NSStringFromRect(self.frame));
            [self resetFrame];
        }

		NSColor *backgroundColor = [[NSUserDefaults standardUserDefaults] colorForKey:@"default.bezelColor"];
		_currentBezelView = [[KCDefaultVisualizerBezelView alloc] initWithMaxWidth:NSWidth(self.frame)
																			  text:string
																   backgroundColor:backgroundColor];
		[_currentBezelView setAutoresizingMask:NSViewMinYMargin];

        // Growing the window to fit _currentBezelView's height now happens in
        // KCDefaultVisualizerBezelView.viewDidMoveToWindow, triggered by addSubview: below
        // -- that's the first point a real window exists to grow, since
        // -initWithMaxWidth:text:backgroundColor: (just above) runs before this view is
        // attached to anything.
		[[self contentView] addSubview:_currentBezelView];
	}
	else
	{
		[_currentBezelView appendString:string];
	}
    [self _scheduleLineBreak];
}

-(void) addRunningAnimation:(KCBezelAnimation*)animation
{
    [_runningAnimations addObject:animation];
    [self saveFrameUsingName:self.frameAutosaveName];

    if (_dragging)
		[animation stopAnimation];
}

-(void) removeRunningAnimation:(KCBezelAnimation*)animation
{
	[_runningAnimations removeObject:animation];
    [self saveFrameUsingName:self.frameAutosaveName];

    if (_runningAnimations.count == 0) {
        if (_shouldResize) {
            _shouldResize = NO;
            [self resizePreservingHeight:YES];
        }
    }
}

- (void)_suspendAnimations
{
	NSUInteger vc = [_runningAnimations count];
	int i;
	for (i = 0; i < vc; ++i)
	{
		NSAnimation* anim = [_runningAnimations objectAtIndex:i];
		[anim stopAnimation];
	}
}

- (void)_resumeAnimations
{
	NSUInteger vc = [_runningAnimations count];
	int i;
	for (i = 0; i < vc; ++i)
	{
		NSAnimation* anim = [_runningAnimations objectAtIndex:i];
		[anim startAnimation];
	}
}

- (void)mouseDown:(NSEvent*)theEvent
{
    _dragging = YES;
    [self _suspendAnimations];

    [super mouseDown:theEvent];
}

- (void)mouseUp:(NSEvent*)theEvent
{
    _dragging = NO;
    _shouldResize = YES;
    [self _resumeAnimations];

    [super mouseUp:theEvent];
}

@end


@implementation KCBezelAnimation

- (KCBezelAnimation *)initWithBezelView:(KCDefaultVisualizerBezelView*)bezelView
{
	if (!(self = [super init]))
		return nil;

    _bezelView = bezelView;

	return self;
}

-(void) fadeOutOverDuration:(NSTimeInterval)duration
{
	if ([self isAnimating])
		return;

	if (duration < 0.01)
	{
		// just do it immediately
		[self animationDidEnd:self];
		return;
	}

	[self setDelegate:self];
	[self setDuration:duration];
	[self setFrameRate:30];
	[self setAnimationCurve:NSAnimationLinear];
	[self setAnimationBlockingMode:NSAnimationNonblocking];
	[self startAnimation];
}

-(void) setCurrentProgress:(NSAnimationProgress)progress
{
	[super setCurrentProgress:progress];

	[_bezelView setAlphaValue:(1 - progress)];
	[_bezelView setNeedsDisplay:YES];
}

-(void) animationDidEnd:(NSAnimation*)anim
{
	NSRect removedFrame = [_bezelView frame];
	CGFloat deltaY = removedFrame.size.height + 10;
	KCDefaultVisualizerWindow* w = (KCDefaultVisualizerWindow*)[_bezelView window];
	[w removeRunningAnimation:self];
	[_bezelView removeFromSuperview];

	// Without this, _currentBezelView can outlive the view's removal from the hierarchy and
	// keep pointing at it, so -appendString: takes its "append to the existing bezel" branch
	// and writes into a view that is no longer on screen -- the keystroke is silently never
	// displayed. Normally the line-break timer (default.keystrokeDelay, 0.5s) clears
	// _currentBezelView well before the fade timer (default.fadeDelay, 2.0s) even starts, so
	// the defaults never expose this; but both are user-adjustable sliders whose ranges
	// overlap (fadeDelay goes down to 0.1, keystrokeDelay up to 1.0), so a fade CAN finish
	// first and strand the pointer.
	[w noteBezelViewDidFadeOut:_bezelView];

	// Only rows that sat ABOVE the removed one move, sliding DOWN by its height to close
	// the gap it left; rows below it keep their position. deltaY is the removed row's own
	// height, so rows of differing heights (a larger font size, or the smaller "Typing…"
	// override) each close the correct amount of space.
	//
	// Each survivor is pinned to the bottom (MaxYMargin) for the duration of the window
	// resize below and restored afterward. Without that, autoresizing applies a second
	// shift of its own to every row on top of the explicit one here -- which is what made
	// the previous unconditional `origin.y += deltaY` cancel itself out exactly, leaving
	// rows at their original position inside a window that had gotten shorter, so they
	// were clipped by the window edge.
	NSArray *survivors = [[[w contentView] subviews] copy];
	for (NSView *v in survivors)
	{
		if (NSMinY(v.frame) > NSMinY(removedFrame))
		{
			NSRect f = [v frame];
			f.origin.y -= deltaY;
			[v setFrame:f];
		}
		[v setAutoresizingMask:NSViewMaxYMargin];
	}

	NSRect r = [w frame];
	r.size.height -= deltaY;
	if (r.size.height < 0)
		r.size.height = 0;
	[w setFrame:r display:YES animate:NO];

	for (NSView *v in survivors)
		[v setAutoresizingMask:NSViewMinYMargin];
}

@end


@implementation KCDefaultVisualizerBezelView

static const int kKCBezelBorder = 6;

- (id)initWithMaxWidth:(CGFloat)maxWidth text:(NSString *)string backgroundColor:(NSColor *)color
{
	if (!(self = [super initWithFrame:NSMakeRect(0, 0, maxWidth, kKCDefaultBezelHeight)]))
		return nil;

	_opacity = 1.0;

	_maxWidth = maxWidth;
	_backgroundColor = color;

	_textStorage = [[NSTextStorage alloc] initWithString:string];
	_textContainer = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(_maxWidth-kKCBezelBorder*2, FLT_MAX)];
	_layoutManager = [[NSLayoutManager alloc] init];
	[_layoutManager addTextContainer:_textContainer];
	[_textStorage addLayoutManager:_layoutManager];
	[_textStorage setAttributes:[self attributes] range:NSMakeRange(0, [_textStorage length])];

	[self setAutoresizingMask:NSViewMinYMargin];

	[self maybeResize];
	[self scheduleFadeOut];

	return self;
}

// -maybeResize (called above, during init) already resized this view's own frame to fit
// its content -- but it can't grow the WINDOW to match, since self.window is still nil at
// that point (this view hasn't been added to one yet; that happens afterward, in
// KCDefaultVisualizerWindow.appendString:'s new-bezel path). Once AppKit actually adds
// this view to a window (addSubview:), it calls this, and this is the first point where
// growing the window for real is possible. This reproduces exactly the "+10 padding + my
// height" calculation appendString: used to do itself immediately after -initWithMaxWidth:
// ...returned -- moved here instead, since here is the first point it can actually work,
// and removed from the caller to avoid the same growth being computed in two places.
- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];

    if (_hasGrownWindowForInitialSize || self.window == nil) {
        return;
    }
    _hasGrownWindowForInitialSize = YES;

    NSWindow *w = self.window;
    NSRect frame = [w frame];
    frame.size.height += 10 + self.frame.size.height;

    // Pin self to the bottom for the duration of the grow, so this new row stays anchored
    // at the bottom of the stack and the rows already present (NSViewMinYMargin) shift up
    // to make room for it. Without this, autoresizing sweeps this row upward along with
    // the older ones and leaves an empty row-sized gap at the bottom of the window. This
    // is the same mask-flip idiom -maybeResize uses when resizing the window around a view.
    [self setAutoresizingMask:NSViewMaxYMargin];
    [w setFrame:frame display:YES animate:NO];
    [self setAutoresizingMask:NSViewMinYMargin];
}

-(void) scheduleFadeOut
{
	NSTimeInterval fadeDelay = [[NSUserDefaults standardUserDefaults] floatForKey:@"default.fadeDelay"];
	if (fadeDelay == 0)
		fadeDelay = 2;
	SEL fadeOutSelector = @selector(beginFadeOut:);
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:fadeOutSelector object:nil];
	[self performSelector:fadeOutSelector withObject:nil afterDelay:fadeDelay];
}

-(void) beginFadeOut:(id)sender
{
	KCDefaultVisualizerWindow *window = (KCDefaultVisualizerWindow *)[self window];
	KCBezelAnimation *animation = [[KCBezelAnimation alloc] initWithBezelView:self];
	// Added to the window's running-animations list BEFORE starting the fade: when
	// default.fadeDuration is under 0.01, -fadeOutOverDuration: below calls -animationDidEnd:
	// synchronously, which calls -removeRunningAnimation: -- if that ran before this
	// animation was ever added, the remove would silently no-op (NSMutableArray
	// -removeObject: on an absent object is a safe no-op) and this animation would then get
	// added afterward with nothing left to ever remove it, stranding it in the list forever
	// and permanently breaking the "_runningAnimations.count == 0" check that re-widens the
	// window after a drag.
	[window addRunningAnimation:animation];
	[animation fadeOutOverDuration:[[NSUserDefaults standardUserDefaults] floatForKey:@"default.fadeDuration"]];
}

-(NSDictionary*) attributes
{
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	NSColor* c = [ud colorForKey:@"default.textColor"];
    CGFloat fontSize = (_fontSizeOverride > 0) ? _fontSizeOverride : [ud floatForKey:@"default.fontSize"];
	return [NSDictionary dictionaryWithObjectsAndKeys:
		[NSFont systemFontOfSize:fontSize], NSFontAttributeName,
		[c colorWithAlphaComponent:_opacity * [c alphaComponent]], NSForegroundColorAttributeName,
		nil];
}

-(void) setAlphaValue:(float)opacity
{
	_opacity = opacity;
	[_textStorage setAttributes:[self attributes] range:NSMakeRange(0, [_textStorage length])];
}

-(void) drawRect:(NSRect)r
{
	NSRect frame = [self bounds];

	NSBezierPath *bgPath = [NSBezierPath bezierPath];
	[bgPath appendRoundedRect:frame radius:16];

	[[_backgroundColor colorWithAlphaComponent:_opacity * [_backgroundColor alphaComponent]] setFill];
	[bgPath fill];

	[_layoutManager drawGlyphsForGlyphRange:NSMakeRange(0,[_textStorage length]) atPoint:NSMakePoint(kKCBezelBorder, kKCBezelBorder)];
}

-(void) maybeResize
{
	NSRect frame = [self frame];
	[_layoutManager glyphRangeForTextContainer:_textContainer];
	NSSize size = [_layoutManager usedRectForTextContainer:_textContainer].size;
	size.width += kKCBezelBorder * 2;
	size.height += kKCBezelBorder * 2;
	if (frame.size.width != size.width || frame.size.height != size.height)
	{
		[self setFrameSize:size];
		if (size.height != frame.size.height)
		{
			float deltaY = size.height - frame.size.height;
			NSWindow* w = [self window];
			NSArray* siblings = [[w contentView] subviews];

			// Pin every sibling to MaxYMargin for the duration of the window resize below,
			// so autoresizing can't ALSO shift it on top of the explicit repositioning here
			// -- same root cause/fix as -animationDidEnd:. Every bezel row is created with
			// MinYMargin, so without this, AppKit auto-shifts every row regardless of the
			// position guard below, moving rows that should stay put.
			for (NSView* v in siblings)
			{
				if (v != self)
					[v setAutoresizingMask:NSViewMaxYMargin];
			}

			for (NSView* v in siblings)
			{
				if (v == self) continue;
				if ([v frame].origin.y > frame.origin.y)
				{
					NSRect f = [v frame];
					f.origin.y += deltaY;
					[v setFrame:f];
				}
			}

			NSRect r = [w frame];
			r.size.height += deltaY;
			[self setAutoresizingMask:NSViewMaxYMargin];
			[w setFrame:r display:YES];
			[self setAutoresizingMask:NSViewMinYMargin];

			for (NSView* v in siblings)
			{
				if (v != self)
					[v setAutoresizingMask:NSViewMinYMargin];
			}
		}
	}
}

-(void) appendString:(NSString*)t
{
    _fontSizeOverride = 0;
    [self scheduleFadeOut];
    [_textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:t]];
    [_textStorage setAttributes:[self attributes] range:NSMakeRange(0, [_textStorage length])];
    [self maybeResize];
    [self setNeedsDisplay:YES];
}

-(void) setText:(NSString*)t
{
    _fontSizeOverride = 0;
    [self scheduleFadeOut];
    [_textStorage deleteCharactersInRange:NSMakeRange(0, [_textStorage length])];
    [_textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:t]];
    [_textStorage setAttributes:[self attributes] range:NSMakeRange(0, [_textStorage length])];
    [self maybeResize];
    [self setNeedsDisplay:YES];
}

// Renders text at a specific font size for just this one update, independent of
// default.fontSize -- used for the "Typing…" placeholder. The override is scoped to this
// call only: any subsequent appendString:/setText: (without an explicit size) reverts to
// the normal default.fontSize-driven attributes, so it can never leak onto unrelated text.
-(void) setText:(NSString*)t fontSize:(CGFloat)fontSize
{
    _fontSizeOverride = fontSize;
    [self scheduleFadeOut];
    [_textStorage deleteCharactersInRange:NSMakeRange(0, [_textStorage length])];
    [_textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:t]];
    [_textStorage setAttributes:[self attributes] range:NSMakeRange(0, [_textStorage length])];
    [self maybeResize];
    [self setNeedsDisplay:YES];
}

-(BOOL) isFlipped
{
	return YES;
}

@end
