//	KCAnnotationModeController.m

#if !__has_feature(objc_arc)
#error "ARC is required for this file -- enable with -fobjc-arc"
#endif

#import "KCAnnotationModeController.h"
#import "KCAnnotationOverlayWindow.h"
#import "KCKeystroke.h"

// kVK_ANSI_A / kVK_ANSI_C -- physical key positions, independent of keyboard layout/typed
// character.
static const uint16_t kKCAnnotationModeHotkeyKeyCode = 0;
static const uint16_t kKCClearAnnotationsHotkeyKeyCode = 8;
static const NSEventModifierFlags kKCAnnotationHotkeyRequiredFlags = NSEventModifierFlagControl | NSEventModifierFlagOption;
static const NSEventModifierFlags kKCRelevantModifierFlags = NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagShift;

@implementation KCAnnotationModeController {
    BOOL _annotationModeEnabled;
    BOOL _persistentAnnotationsEnabled;
    KCAnnotationOverlayWindow *_overlayWindow;
}

- (BOOL)isAnnotationModeEnabled {
    return _annotationModeEnabled;
}

- (BOOL)isPersistentAnnotationsEnabled {
    return _persistentAnnotationsEnabled;
}

// Created on first use rather than at app launch -- if annotation mode is never toggled
// on in a session, no extra window ever gets allocated. Reused across toggles afterward.
- (KCAnnotationOverlayWindow *)overlayWindow {
    if (_overlayWindow == nil) {
        _overlayWindow = [[KCAnnotationOverlayWindow alloc] init];
    }
    return _overlayWindow;
}

- (BOOL)handleKeystroke:(KCKeystroke *)keystroke {
    if ((keystroke.modifierFlags & kKCRelevantModifierFlags) != kKCAnnotationHotkeyRequiredFlags) {
        return NO;
    }

    if (keystroke.keyCode == kKCAnnotationModeHotkeyKeyCode) {
        [self toggleAnnotationMode];
        return YES;
    }

    if (keystroke.keyCode == kKCClearAnnotationsHotkeyKeyCode) {
        [self clearAnnotations];
        return YES;
    }

    return NO;
}

- (void)toggleAnnotationMode {
    _annotationModeEnabled = !_annotationModeEnabled;
    self.overlayWindow.catchesClicks = _annotationModeEnabled;
}

- (void)togglePersistentAnnotations {
    _persistentAnnotationsEnabled = !_persistentAnnotationsEnabled;
    self.overlayWindow.persistentAnnotationsEnabled = _persistentAnnotationsEnabled;
}

- (void)clearAnnotations {
    [self.overlayWindow clearAllShapes];
}

@end
