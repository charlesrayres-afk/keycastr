//	Copyright (c) 2009 Stephen Deken
//	Copyright (c) 2014-2025 Andrew Kitchen
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

#import <Quartz/Quartz.h>
#import <ShortcutRecorder/ShortcutRecorder.h>
#import "KCAnnotationModeController.h"
#import "KCAppController.h"
#import "KCEventTap.h"
#import "KCKeystroke.h"
#import "KCMouseEventVisualizer.h"
#import "KCPrefsWindowController.h"
#import "KCUserDefaultsMigration.h"
#import "KCVisualizer.h"

typedef struct _KeyCombo {
    unsigned int flags; // 0 for no flags
    signed short code; // -1 for no code
} KeyCombo;

static NSString* kKCPrefCapturingHotKey = @"capturingHotKey";
static NSString* kKCPrefVisibleAtLaunch = @"alwaysShowPrefs";
static NSString* kKCPrefDisplayIcon = @"displayIcon";
static NSString* kKCPrefSelectedVisualizer = @"selectedVisualizer";
static NSString* kKCSupplementalAlertText = @"\n\nPlease grant KeyCastr access to the Accessibility and/or Input Monitoring API in order to broadcast your keyboard inputs.\n\nWithin the System Preferences application, open the Security & Privacy preferences and add KeyCastr to the Accessibility and/or Input Monitoring list within the Privacy tab. If KeyCastr is already listed under the menus, please remove it and try again.\n";

static NSInteger kKCPrefDisplayIconInMenuBar = 0x01;
static NSInteger kKCPrefDisplayIconInDock = 0x02;

// Encodes an NSColor via NSKeyedArchiver, matching how default.bezelColor/textColor are
// encoded in KCDefaultVisualizer.m -- used below for default.annotationStrokeColor.
static NSData *KCArchivedColor(NSColor *color) {
    return [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:NULL];
}

@interface KCAppController () <KCEventTapDelegate, KCMouseEventVisualizerDelegate, NSMenuItemValidation, NSMenuDelegate>

@property (nonatomic, strong) KCEventTap *eventTap;
@property (nonatomic, strong) NSStatusItem *statusItem;

@property (nonatomic, assign) NSInteger prefDisplayIcon;
@property (nonatomic, assign) BOOL showInDock;
@property (nonatomic, assign) BOOL showInMenuBar;
@property (nonatomic, strong) SRShortcut *toggleCastingShortcut;

@property (nonatomic, assign) IBOutlet NSMenu *statusMenu;
@property (nonatomic, strong) IBOutlet NSWindow *aboutWindow;
@property (nonatomic, strong) IBOutlet QCView   *aboutQCView;
@property (nonatomic, assign) IBOutlet NSWindow *preferencesWindow;
@property (nonatomic, assign) IBOutlet KCPrefsWindowController *prefsWindowController;
@property (nonatomic, assign) IBOutlet SRRecorderControl *shortcutRecorder;
@property (nonatomic, assign) IBOutlet NSMenuItem *statusShortcutItem;
@property (nonatomic, assign) IBOutlet NSMenuItem *dockShortcutItem;

@property (nonatomic, strong) KCMouseEventVisualizer *mouseEventVisualizer;
@property (nonatomic, strong) id<KCVisualizer> currentVisualizer;

@property (nonatomic, strong) NSMenuItem *annotationModeMenuItem;
@property (nonatomic, strong) NSMenuItem *persistentAnnotationsMenuItem;
@property (nonatomic, strong) NSMenuItem *clearAnnotationsMenuItem;

@property (nonatomic, strong) KCAnnotationModeController *annotationModeController;

@end

@implementation KCAppController {
    BOOL _isCapturing;
}

@synthesize eventTap, statusItem, statusMenu, aboutWindow, aboutQCView, preferencesWindow, prefsWindowController, shortcutRecorder, dockShortcutItem, statusShortcutItem, mouseEventVisualizer, currentVisualizer;
@synthesize toggleCastingShortcut = _toggleCastingShortcut;

#pragma mark -
#pragma mark Startup Procedures

- (id)init {
    if (!(self = [super init]))
        return nil;

    eventTap = [KCEventTap new];
    eventTap.delegate = self;

    [self registerVisualizers];
    [self registerDefaults];

    mouseEventVisualizer = [KCMouseEventVisualizer new];
    mouseEventVisualizer.delegate = self;

    self.annotationModeController = [KCAnnotationModeController new];

    [NSColor setIgnoresAlpha:NO];

    return self;
}

- (void)awakeFromNib {
    [self setIsCapturing:NO];
    
    // Set current visualizer from user preferences
    [self setCurrentVisualizerName:[[NSUserDefaults standardUserDefaults] objectForKey:kKCPrefSelectedVisualizer]];

    [shortcutRecorder setObjectValue:self.toggleCastingShortcut];
    [self updateToggleShortcutDisplay:self.toggleCastingShortcut];

    [prefsWindowController nudge];
    [self updateAboutPanel];

    [[NSUserDefaults standardUserDefaults] addObserver:self
                                            forKeyPath:kKCPrefDisplayIcon
                                               options:(NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew)
                                               context:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidHide:)
                                                 name:NSApplicationDidHideNotification
                                               object:NSApp];

    [self reorderStatusMenu];
}

- (void)applicationDidHide:(NSNotification *)notification {
    [NSApp unhideWithoutActivation];
}

// The status menu's base items (About/Preferences/Start-Stop Casting/Quit) are built
// entirely in the nib -- there's no NSMenuItem-construction code for them to reorder
// directly. Quit is located by its action selector (unique within this menu; there's no
// IBOutlet for it) rather than by title, since that's stable regardless of exact string
// formatting. About/Preferences/Casting are already in the nib's existing relative order
// (confirmed by inspecting Base.lproj/MainMenu.nib/designable.nib) and don't need to move
// -- only Quit needs repositioning, and separators need adding around the annotation group
// and before Quit, isolating it at the bottom per standard macOS convention.
- (void)reorderStatusMenu {
    if (statusMenu == nil) {
        return;
    }

    NSMenuItem *quitItem = nil;
    for (NSMenuItem *item in statusMenu.itemArray) {
        if (item.action == @selector(terminate:)) {
            quitItem = item;
            break;
        }
    }

    if (quitItem != nil) {
        [statusMenu removeItem:quitItem];
    }

    [statusMenu addItem:[NSMenuItem separatorItem]];
    [self installAnnotationMenuItems];
    [statusMenu addItem:[NSMenuItem separatorItem]];

    if (quitItem != nil) {
        [statusMenu addItem:quitItem];
    }
}

#pragma mark -
#pragma mark Annotation Mode

// Appended after whatever's already in the status menu (defined in the xib) -- these are
// checkable mode toggles / a related action, kept together as their own trailing group.
- (void)installAnnotationMenuItems {
    if (statusMenu == nil) {
        return;
    }

    // statusMenu has no existing delegate anywhere in this codebase (checked), so it's
    // safe to claim it here for -menu:hasKeyEquivalent:forEvent:target:action: below.
    statusMenu.delegate = self;

    NSMenuItem *annotationItem = [[NSMenuItem alloc] initWithTitle:@"Annotation Mode"
                                                             action:@selector(toggleAnnotationMode:)
                                                      keyEquivalent:@"a"];
    annotationItem.target = self;
    annotationItem.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagOption;
    [statusMenu addItem:annotationItem];
    self.annotationModeMenuItem = annotationItem;

    NSMenuItem *persistentItem = [[NSMenuItem alloc] initWithTitle:@"Persistent Annotations"
                                                              action:@selector(toggleAnnotationPersistence:)
                                                       keyEquivalent:@""];
    persistentItem.target = self;
    [statusMenu addItem:persistentItem];
    self.persistentAnnotationsMenuItem = persistentItem;

    NSMenuItem *clearItem = [[NSMenuItem alloc] initWithTitle:@"Clear Annotations"
                                                        action:@selector(clearAnnotations:)
                                                 keyEquivalent:@"c"];
    clearItem.target = self;
    clearItem.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagOption;
    [statusMenu addItem:clearItem];
    self.clearAnnotationsMenuItem = clearItem;

    // Annotation Mode and Clear Annotations now carry REAL keyEquivalent/
    // keyEquivalentModifierMask, purely so AppKit renders the native right-aligned shortcut
    // hint -- but invoking them via that key equivalent is suppressed below in
    // -menu:hasKeyEquivalent:forEvent:target:action:, so the only real trigger for either
    // remains the global KCEventTap-based hotkey, unchanged, which fires regardless of
    // focus. Without that suppression, pressing Ctrl+Opt+A/C while KeyCastr is frontmost
    // would fire the action twice: once from the global event tap, once from AppKit's own
    // menu key-equivalent dispatch. Persistent Annotations has no hotkey, so it keeps an
    // empty keyEquivalent and isn't affected by any of this.
}

// See the comment in -installAnnotationMenuItems for why this exists. Per AppKit's
// documented behavior for this method: returning NO means "I have no opinion, do your
// normal per-item keyEquivalent search" -- which would still find and invoke a matching
// item normally. Returning YES means "I've resolved this myself," and handing back a nil
// target/NULL action means the resolution is "nothing to invoke," bypassing AppKit's own
// search entirely for this event. That's the actual suppression mechanism: YES+nil for our
// two combos, NO for every other key equivalent in the app (Quit, Preferences, etc.), which
// falls through to AppKit's completely normal, untouched per-item search.
- (BOOL)menu:(NSMenu *)menu hasKeyEquivalent:(NSString *)string forEvent:(NSEvent *)event target:(id *)target action:(SEL *)action {
    NSEventModifierFlags relevantFlags = event.modifierFlags & (NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagShift);

    BOOL matchesAnnotationItem = relevantFlags == self.annotationModeMenuItem.keyEquivalentModifierMask
        && [string isEqualToString:self.annotationModeMenuItem.keyEquivalent];
    BOOL matchesClearItem = relevantFlags == self.clearAnnotationsMenuItem.keyEquivalentModifierMask
        && [string isEqualToString:self.clearAnnotationsMenuItem.keyEquivalent];

    if (matchesAnnotationItem || matchesClearItem) {
        if (target) {
            *target = nil;
        }
        if (action) {
            *action = NULL;
        }
        return YES;
    }

    return NO;
}

- (void)toggleAnnotationMode:(id)sender {
    [self.annotationModeController toggleAnnotationMode];
}

- (void)toggleAnnotationPersistence:(id)sender {
    [self.annotationModeController togglePersistentAnnotations];
}

- (void)clearAnnotations:(id)sender {
    [self.annotationModeController clearAnnotations];
}

// Sync mechanism for both checkmarks: NSMenuItemValidation, not a notification or eager
// push after every toggle call site. AppKit calls -validateMenuItem: on this item's target
// automatically, right before the menu is shown, for every item with a target+action --
// no extra wiring (no delegate, no observer add/remove) beyond implementing this one
// method. That makes it correct by construction regardless of how many places call
// -toggleAnnotationMode/-togglePersistentAnnotations now or in the future (hotkey today,
// these menu items, anything added later): none of them need to remember to "also refresh
// the menu," since nothing refreshes it manually at all -- it's always recomputed fresh
// from the single source of truth (KCAnnotationModeController) at the moment it's about to
// be seen. A notification/KVO push would only be worth the extra plumbing if some other,
// simultaneously-visible piece of UI also needed to reflect this state while the menu is
// closed, which isn't the case here. Clear Annotations has no state to sync -- it's a
// momentary action, not a toggle.
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem == self.annotationModeMenuItem) {
        menuItem.state = self.annotationModeController.isAnnotationModeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (menuItem == self.persistentAnnotationsMenuItem) {
        menuItem.state = self.annotationModeController.isPersistentAnnotationsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    }
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp activateIgnoringOtherApps:YES];

    if (![self installTap]) {
        [self setIsCapturing:NO];

        return;
    }

    [self setIsCapturing:YES];

    if ([[NSUserDefaults standardUserDefaults] boolForKey:kKCPrefVisibleAtLaunch]) {
        [preferencesWindow center];
        [preferencesWindow makeKeyAndOrderFront:self];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [eventTap removeTap];
}

- (SRShortcut *)toggleCastingShortcut {
    if (_toggleCastingShortcut == nil) {
        KeyCombo toggleShortcutKey;
        NSData *toggleShortcutKeyData = [[NSUserDefaults standardUserDefaults] dataForKey:kKCPrefCapturingHotKey];
        if (toggleShortcutKeyData != nil) {
            [toggleShortcutKeyData getBytes:&toggleShortcutKey length:sizeof(toggleShortcutKey)];
        }

        _toggleCastingShortcut = [SRShortcut shortcutWithDictionary:@{SRShortcutKeyKeyCode: @(toggleShortcutKey.code),
                                                                      SRShortcutKeyModifierFlags: @(toggleShortcutKey.flags)}];
    }
    return _toggleCastingShortcut;
}

- (void)setToggleCastingShortcut:(SRShortcut *)toggleCastingShortcut {
    _toggleCastingShortcut = toggleCastingShortcut;

    KeyCombo newKeyCombo;
    newKeyCombo.code = toggleCastingShortcut.keyCode;
    newKeyCombo.flags = (unsigned int)toggleCastingShortcut.modifierFlags; // migration needed to avoid cast

    [[NSUserDefaults standardUserDefaults] setObject:[NSData dataWithBytes:&newKeyCombo length:sizeof(newKeyCombo)] forKey:kKCPrefCapturingHotKey];
}

- (void)openPrefsPane:(id)sender {
    NSString *text = @"tell application \"System Preferences\" \n reveal anchor \"Privacy_Accessibility\" of pane id \"com.apple.preference.security\" \n activate \n end tell";
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:text];
    [script executeAndReturnError:nil];
}

- (void)displayPermissionsAlertWithError:(NSError *)error {
    NSAlert *alert = [NSAlert new];
    [alert addButtonWithTitle:@"Close"];
    [alert addButtonWithTitle:@"Open System Preferences"];
    alert.messageText = @"Additional Permissions Required";
    alert.informativeText = [error.localizedDescription stringByAppendingString:kKCSupplementalAlertText];
    alert.alertStyle = NSAlertStyleCritical;

    switch ([alert runModal]) {
        case NSAlertFirstButtonReturn:
            [NSApp terminate:nil];
            break;
        case NSAlertSecondButtonReturn: {
            [self openPrefsPane:nil];
            [NSApp terminate:nil];
        }
            break;
    }
}

- (BOOL)installTap {
    NSError *error = nil;
    if (![eventTap installTapWithError:&error]) {
        // Only display a custom error message if we're running on macOS < 10.15
        NSOperatingSystemVersion minVersion = { .majorVersion = 10, .minorVersion = 15, .patchVersion = 0 };
        BOOL supportsNewPermissionsAlert = [NSProcessInfo.processInfo respondsToSelector:@selector(isOperatingSystemAtLeastVersion:)] && [NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:minVersion];

        if (!supportsNewPermissionsAlert) {
            [self displayPermissionsAlertWithError:error];
        }
        return NO;
    }
    return YES;
}

- (void)registerDefaults
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [KCUserDefaultsMigration performMigration:userDefaults];

    KeyCombo keyCombo;
    keyCombo.code = 40;
    keyCombo.flags = NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand;

    NSDictionary *appDefaults = @{ kKCPrefDisplayIcon: @3,
                                   kKCPrefSelectedVisualizer: @"Default",
                                   kKCPrefVisibleAtLaunch: @YES,
                                   kKCPrefCapturingHotKey: [NSData dataWithBytes:&keyCombo length:sizeof(keyCombo)],
                                   @"default.annotationDiameter": @40.0,
                                   @"default.annotationStrokeWidth": @2.0,
                                   @"default.annotationStrokeColor": KCArchivedColor([NSColor colorWithCalibratedRed:1.0 green:0.65 blue:0.0 alpha:1.0]),
                                   @"default.annotationFillOpacity": @0.0 };
    
    NSArray *factories = [KCVisualizer availableVisualizerFactories];
    NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
    for (KCVisualizerFactory *factory in factories) {
        Class visualizerClass = factory.visualizerClass;
        if ([visualizerClass conformsToProtocol:@protocol(KCVisualizer)]) {
            [defaults addEntriesFromDictionary:[(Class<KCVisualizer>)visualizerClass visualizerDefaults]];
        }
    }
    
    [defaults addEntriesFromDictionary:appDefaults];
    [userDefaults registerDefaults:defaults];
}

- (void)eventTap:(KCEventTap *)tap noteKeystroke:(KCKeystroke *)keystroke
{
    if ([self.annotationModeController handleKeystroke:keystroke]) {
        return;
    }

    if (keystroke.keyCode == self.toggleCastingShortcut.keyCode && (keystroke.modifierFlags & (NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption)) == (self.toggleCastingShortcut.modifierFlags & (NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption)))
	{
        [self toggleRecording:self];
		return;
	}
	
    if (!_isCapturing) {
		return;
    }

    if (currentVisualizer != nil) {
		[currentVisualizer noteKeyEvent:keystroke];
    }
}

- (void)eventTap:(KCEventTap *)tap noteKeyUp:(KCKeystroke *)keystroke
{
    if (!_isCapturing) {
        return;
    }

    if (currentVisualizer != nil && [currentVisualizer respondsToSelector:@selector(noteKeyUpEvent:)]) {
        [currentVisualizer noteKeyUpEvent:keystroke];
    }
}

- (void)eventTap:(KCEventTap *)tap noteFlagsChanged:(NSEventModifierFlags)flags
{
    if (!_isCapturing) {
        return;
    }
    
    if (currentVisualizer != nil) {
		[currentVisualizer noteFlagsChanged:flags];
    }
}

- (void)eventTap:(KCEventTap *)eventTap noteMouseEvent:(KCMouseEvent *)mouseEvent
{
    // TODO: need to let mouseUp events through after isCapturing or mouse events are disabled, otherwise we can end up with a stuck visualizer animation
    if (!_isCapturing) {
        return;
    }

    [mouseEventVisualizer noteMouseEvent:mouseEvent];
}

- (void)mouseEventVisualizer:(KCMouseEventVisualizer *)visualizer didNoteMouseEvent:(KCMouseEvent *)mouseEvent
{
    [currentVisualizer noteMouseEvent:mouseEvent];
}

-(NSStatusItem*) createStatusItem
{
	if (statusItem == nil)
	{
		statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:30];
		[statusItem setMenu:statusMenu];
		[statusItem.button setImage:(_isCapturing
			? [NSImage imageNamed:@"KeyCastrStatusItemActive"]
			: [NSImage imageNamed:@"KeyCastrStatusItemInactive"])];
	}
	return statusItem;
}

-(void) deleteStatusItem
{
	if (statusItem != nil)
	{
		statusItem = nil;
	}
}

-(void) registerVisualizers
{
	// register visualizers from plug-in paths
    [KCVisualizer loadPluginsFromDirectory:[[NSBundle mainBundle] builtInPlugInsPath]];
}

- (void)updateToggleShortcutDisplay:(SRShortcut *)shortcut
{
    SRKeyCodeTransformer *transformer = [SRKeyCodeTransformer sharedTransformer];
    [statusShortcutItem setKeyEquivalent:[transformer transformedValue:@(shortcut.keyCode)]];
    [statusShortcutItem setKeyEquivalentModifierMask:shortcut.modifierFlags];
    [dockShortcutItem setKeyEquivalent:[transformer transformedValue:@(shortcut.keyCode)]];
    [dockShortcutItem setKeyEquivalentModifierMask:shortcut.modifierFlags];
}

- (void)updateAboutPanel
{
    for (NSView *subview in aboutWindow.contentView.subviews) {
        if ([subview isKindOfClass:[NSTextField class]]) {
            NSTextField *textField = (NSTextField *)subview;
            NSString *prefix = @"Version ";
            if ([textField.stringValue rangeOfString:prefix].location == 0) {
                [textField setStringValue:[prefix stringByAppendingString:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]]];
            }
        }
    }

    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"KeyCastrAbout" ofType:@"qtz"];
    [aboutQCView loadCompositionFromFile:filePath];
}

-(void) orderFrontKeyCastrAboutPanel:(id)sender
{
    [aboutWindow center];
    [aboutWindow makeKeyAndOrderFront:sender];
    
    if (!aboutQCView.isRendering) {
        [aboutQCView startRendering];
    }
    
    [NSApp activateIgnoringOtherApps:YES];
}

-(void) orderFrontKeyCastrPreferencesPanel:(id)sender
{
	[preferencesWindow makeKeyAndOrderFront:sender];
	[NSApp activateIgnoringOtherApps:YES];
}

-(void) toggleRecording:(id)sender
{
	[self setIsCapturing:![self isCapturing]];
}

-(void) stopPretending:(id)what
{
	[self toggleRecording:self];
}

-(void) pretendToDoSomethingImportant:(id)sender
{
	[self performSelector:@selector(stopPretending:) withObject:nil afterDelay:0.1];
}

-(NSString*) currentVisualizerName
{
	if (currentVisualizer == nil)
		return nil;

	return [currentVisualizer visualizerName];
}

-(void) setCurrentVisualizerName:(NSString*)visualizerName
{
	[[NSUserDefaults standardUserDefaults] setObject:visualizerName forKey:kKCPrefSelectedVisualizer];
	id<KCVisualizer> new = [KCVisualizer visualizerWithName:visualizerName];
	[self setCurrentVisualizer:new];
}

-(id<KCVisualizer>) currentVisualizer
{
	return currentVisualizer;
}

- (void)setCurrentVisualizer:(id <KCVisualizer>)newVisualizer {
    if (newVisualizer == nil || currentVisualizer == newVisualizer) {
        return;
    }
    
    id <KCVisualizer> oldVisualizer = currentVisualizer;

    if (oldVisualizer != nil) {
        [oldVisualizer deactivateVisualizer:self];
    }

    currentVisualizer = newVisualizer;
    [newVisualizer showVisualizer:self];

    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:newVisualizer, @"newVisualizer", oldVisualizer, @"oldVisualizer", nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"KCVisualizerChanged" object:self userInfo:userInfo];
}

-(NSArray*) availableVisualizerNames
{
	NSArray* factories = [KCVisualizer availableVisualizerFactories];
	NSMutableArray* rval = [NSMutableArray array];
	int i = 0;
	for (i = 0; i < [factories count]; ++i)
	{
		id<KCVisualizerFactory> factory = [factories objectAtIndex:i];
		[rval addObject:[factory visualizerName]];
	}
	return rval;
}

- (NSArray *)availableMouseDisplayOptionNames {
    return mouseEventVisualizer.mouseDisplayOptionNames;
}

- (NSString *)currentMouseDisplayOptionName {
    return mouseEventVisualizer.currentMouseDisplayOptionName;
}

- (void)setCurrentMouseDisplayOptionName:(NSString *)displayOptionName {
    mouseEventVisualizer.currentMouseDisplayOptionName = displayOptionName;
}

-(void) setIsCapturing:(BOOL)capture
{
    if (capture && !eventTap.tapInstalled) {
        return;
    }

    BOOL wasCapturing = _isCapturing;
	_isCapturing = capture;

    // Fires regardless of what stopped capturing (hotkey, menu, anything else funneling
    // through this one setter) -- see the protocol method's doc comment for why this is
    // needed: the event tap itself never stops running, so KCAppController's own
    // _isCapturing guards are what silently drop any future key-up/flags-changed events a
    // visualizer might have been relying on to resolve state left over from before the stop.
    if (wasCapturing && !capture) {
        if (currentVisualizer != nil && [currentVisualizer respondsToSelector:@selector(noteCapturingDidStop)]) {
            [currentVisualizer noteCapturingDidStop];
        }
    }

	[statusItem.button setImage:(_isCapturing
		? [NSImage imageNamed:@"KeyCastrStatusItemActive"]
		: [NSImage imageNamed:@"KeyCastrStatusItemInactive"])
		];
	[statusShortcutItem setTitle:(_isCapturing
		? @"Stop Casting"
		: @"Start Casting")];
	[dockShortcutItem setTitle:(_isCapturing
		? @"Stop Casting"
		: @"Start Casting")];
	[NSApp setApplicationIconImage:(_isCapturing
		? [NSImage imageNamed:@"KeyCastr"]
		: [NSImage imageNamed:@"KeyCastrInactive"])];
}

-(void) restartPanel:(NSAlert*)alert closedWithCode:(NSModalResponse)returnCode
{
	if (returnCode == NSAlertFirstButtonReturn)
	{
		[[NSUserDefaults standardUserDefaults] synchronize];

        NSURL *bundleURL = [[NSBundle mainBundle] bundleURL];
        [[NSWorkspace sharedWorkspace] launchApplicationAtURL:bundleURL
                                                      options:NSWorkspaceLaunchNewInstance
                                                configuration:@{}
                                                        error:NULL];
		[NSApp terminate:self];
	}
}

-(void) changeIconPreference:(id)sender
{
    // sent from the UI.  Ignore until we can update the UI to remove this event.
}

#pragma mark -
#pragma mark Observers

-(void) prefDisplayIconUpdatedTo:(NSInteger)prefDisplayIcon {
    // if the pref is set such that the icon is hidden in both the menu bar and the dock,
    // show the icon in the dock regardless of the user's preference.
    if (0 == (prefDisplayIcon & (kKCPrefDisplayIconInMenuBar | kKCPrefDisplayIconInDock))) {
        prefDisplayIcon = prefDisplayIcon | kKCPrefDisplayIconInDock;
    }
    
    ProcessSerialNumber psn = { 0, kCurrentProcess };
    if (prefDisplayIcon & kKCPrefDisplayIconInDock) {
        // show dock icon
        TransformProcessType(&psn, kProcessTransformToForegroundApplication);
    }
    else {
        // hide dock icon
        preferencesWindow.canHide = NO;
        TransformProcessType(&psn, kProcessTransformToUIElementApplication);
    }

    if (prefDisplayIcon & kKCPrefDisplayIconInMenuBar) {
        // show icon in menu bar
        [self createStatusItem];
    }
    else {
        // hide icon in menu bar
        [self deleteStatusItem];
    }
}

-(void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:kKCPrefDisplayIcon]) {
        [self prefDisplayIconUpdatedTo:[[change objectForKey:NSKeyValueChangeNewKey] integerValue]];
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark -
#pragma mark Properties

-(NSInteger) prefDisplayIcon {
    return [NSUserDefaults.standardUserDefaults integerForKey:kKCPrefDisplayIcon];
}

-(void) setPrefDisplayIcon:(NSInteger)prefDisplayIcon {
    [NSUserDefaults.standardUserDefaults setInteger:prefDisplayIcon forKey:kKCPrefDisplayIcon];
}

-(BOOL) showInDock {
    return (self.prefDisplayIcon & kKCPrefDisplayIconInDock) == kKCPrefDisplayIconInDock;
}

-(void) setShowInDock:(BOOL)showInDock {
    self.prefDisplayIcon = (self.prefDisplayIcon & ~kKCPrefDisplayIconInDock) | (showInDock ? kKCPrefDisplayIconInDock : 0);
}

-(BOOL) showInMenuBar {
    return (self.prefDisplayIcon & kKCPrefDisplayIconInMenuBar) == kKCPrefDisplayIconInMenuBar;
}

-(void) setShowInMenuBar:(BOOL)showInMenuBar {
    self.prefDisplayIcon = (self.prefDisplayIcon & ~kKCPrefDisplayIconInMenuBar) | (showInMenuBar ? kKCPrefDisplayIconInMenuBar : 0);
}

#pragma mark -
#pragma mark SRRecorderControlDelegate methods

- (void)shortcutRecorderDidEndRecording:(SRRecorderControl *)recorder;
{
    SRShortcut *newShortcut = recorder.objectValue;
    if (!newShortcut) {
        [shortcutRecorder setObjectValue:self.toggleCastingShortcut];
        return;
    }
    self.toggleCastingShortcut = newShortcut;
    [shortcutRecorder setObjectValue:newShortcut];
    [self updateToggleShortcutDisplay:newShortcut];
}

@end
