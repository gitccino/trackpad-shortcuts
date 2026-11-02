#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import "Trackpad.h"
#import "Diagnostics.h"
#include <math.h>

static BOOL accessibilityGranted(BOOL prompt) {
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{
        (__bridge NSString *)kAXTrustedCheckOptionPrompt: @(prompt)
    });
}

static BOOL windowRect(AXUIElementRef window, CGRect *rect) {
    CFTypeRef position = NULL, size = NULL;
    AXUIElementCopyAttributeValue(window, kAXPositionAttribute, &position);
    AXUIElementCopyAttributeValue(window, kAXSizeAttribute, &size);
    BOOL success = position && size && CFGetTypeID(position) == AXValueGetTypeID() &&
        CFGetTypeID(size) == AXValueGetTypeID() &&
        AXValueGetValue((AXValueRef)position, kAXValueCGPointType, &rect->origin) &&
        AXValueGetValue((AXValueRef)size, kAXValueCGSizeType, &rect->size);
    if (position) CFRelease(position);
    if (size) CFRelease(size);
    return success;
}

// AppKit uses bottom-left origins; Accessibility uses the primary screen's top left.
static CGRect accessibilityRect(NSRect rect) {
    CGFloat primaryTop = NSMaxY(NSScreen.screens.firstObject.frame);
    return CGRectMake(rect.origin.x, primaryTop - NSMaxY(rect), rect.size.width, rect.size.height);
}

static NSString *arrangeWindow(EdgeAction action) {
    if (!accessibilityGranted(NO)) return @"Accessibility access needed — use the menu to grant access.";
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (!front || front.processIdentifier == NSProcessInfo.processInfo.processIdentifier)
        return @"Select a window in another app first.";
    AXUIElementRef app = AXUIElementCreateApplication(front.processIdentifier);
    AXUIElementSetMessagingTimeout(app, 0.3);
    CFTypeRef value = NULL;
    AXError read = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute, &value);
    CFRelease(app);
    if (read != kAXErrorSuccess || !value) return @"No focused window available.";
    if (CFGetTypeID(value) != AXUIElementGetTypeID()) {
        CFRelease(value);
        return @"The focused window is unavailable.";
    }
    AXUIElementRef window = (AXUIElementRef)value;
    CFTypeRef fullScreen = NULL;
    AXUIElementCopyAttributeValue(window, CFSTR("AXFullScreen"), &fullScreen);
    BOOL isFullScreen = fullScreen && CFEqual(fullScreen, kCFBooleanTrue);
    if (fullScreen) CFRelease(fullScreen);
    if (isFullScreen) { CFRelease(window); return @"Exit macOS fullscreen before arranging this window."; }
    CGRect current = CGRectZero;
    if (!windowRect(window, &current)) { CFRelease(window); return @"Cannot read this window's bounds."; }
    NSScreen *screen = NSScreen.screens.firstObject;
    CGFloat largestArea = -1;
    for (NSScreen *candidate in NSScreen.screens) {
        CGRect overlap = CGRectIntersection(current, accessibilityRect(candidate.frame));
        CGFloat area = CGRectIsNull(overlap) ? 0 : overlap.size.width * overlap.size.height;
        if (area > largestArea) { largestArea = area; screen = candidate; }
    }
    if (!screen) { CFRelease(window); return @"No display available."; }
    CGRect target = accessibilityRect(screen.visibleFrame);
    if (action == ActionAlmostMaximize) target = CGRectInset(target, 12, 12);
    else {
        CGFloat leftWidth = floor(target.size.width / 2);
        if (action == ActionRight) {
            target.origin.x += leftWidth;
            target.size.width -= leftWidth;
        } else target.size.width = leftWidth;
    }
    AXValueRef position = AXValueCreate(kAXValueCGPointType, &target.origin);
    AXValueRef size = AXValueCreate(kAXValueCGSizeType, &target.size);
    // Shrink first so crossing a display boundary doesn't clamp the position.
    AXError sizeError = AXUIElementSetAttributeValue(window, kAXSizeAttribute, size);
    AXError positionError = AXUIElementSetAttributeValue(window, kAXPositionAttribute, position);
    sizeError = AXUIElementSetAttributeValue(window, kAXSizeAttribute, size);
    CFRelease(position);
    CFRelease(size);
    CGRect actual = CGRectZero;
    BOOL matches = windowRect(window, &actual) &&
        fabs(actual.origin.x - target.origin.x) <= 2 && fabs(actual.origin.y - target.origin.y) <= 2 &&
        fabs(actual.size.width - target.size.width) <= 2 && fabs(actual.size.height - target.size.height) <= 2;
    CFRelease(window);
    if (sizeError != kAXErrorSuccess || positionError != kAXErrorSuccess || !matches)
        return @"This app restricted the requested window placement.";
    return action == ActionLeft ? @"Moved to left half" :
           action == ActionRight ? @"Moved to right half" : @"Almost maximized (12 pt margin)";
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) Trackpad *trackpad;
@property(nonatomic, strong) NSMenuItem *status;
@property(nonatomic, strong) NSMenuItem *pause;
@property(nonatomic, strong) NSMenuItem *tap;
@property(nonatomic, strong) NSMenuItem *swipe;
@property(nonatomic) BOOL available;
@property(nonatomic, strong) Diagnostics *diagnostics;
@property(nonatomic, strong) NSMenuItem *observe;
@property(nonatomic, strong) NSMenuItem *testPositions;
@end

@implementation AppDelegate
- (NSMenuItem *)item:(NSString *)title action:(SEL)action menu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
    return item;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.trackpad = [Trackpad new];
    self.trackpad.mode = [NSUserDefaults.standardUserDefaults integerForKey:@"gestureMode"] == ModeSwipe ? ModeSwipe : ModeTap;
    __weak AppDelegate *weakSelf = self;
    self.trackpad.onAction = ^(EdgeAction action) {
        AppDelegate *owner = weakSelf;
        if (owner.diagnostics.window.visible && owner.diagnostics.observeOnly) {
            owner.status.title = @"Gesture recognized — diagnostics is observing only";
            [owner.diagnostics recordEvent:@"action_result" fields:@{ @"action": @(action), @"suppressed": @YES,
                @"message": owner.status.title, @"accessibility_trusted": @(accessibilityGranted(NO)) }];
            return;
        }
        NSString *result = arrangeWindow(action);
        owner.status.title = result;
        if (owner.diagnostics.window.visible) [owner.diagnostics recordEvent:@"action_result" fields:@{
            @"action": @(action), @"suppressed": @NO, @"message": result, @"accessibility_trusted": @(accessibilityGranted(NO)) }];
    };
    self.trackpad.onFrame = ^(NSArray<NSDictionary<NSString *, NSNumber *> *> *touches) {
        [weakSelf.diagnostics updateTouches:touches];
    };
    self.trackpad.onFeedback = ^(NSString *feedback) {
        if (weakSelf.diagnostics.window.visible) [weakSelf.diagnostics record:feedback];
    };
    self.trackpad.onRawFrame = ^(NSDictionary *frame) { [weakSelf.diagnostics recordRawFrame:frame]; };
    self.trackpad.onEvent = ^(NSString *type, NSDictionary *fields) { [weakSelf.diagnostics recordEvent:type fields:fields]; };
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"rectangle.split.2x1" accessibilityDescription:@"Trackpad Shortcuts"];
    self.statusItem.button.toolTip = @"Trackpad Shortcuts";
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    menu.delegate = self;
    [self item:@"Trackpad Shortcuts" action:NULL menu:menu].enabled = NO;
    self.status = [self item:@"Starting trackpad…" action:NULL menu:menu];
    self.status.enabled = NO;
    [menu addItem:NSMenuItem.separatorItem];
    for (NSString *title in @[@"Left edge → Left half", @"Right edge → Right half", @"Bottom edge → Almost maximize"]) {
        [self item:title action:NULL menu:menu].enabled = NO;
    }
    [menu addItem:NSMenuItem.separatorItem];
    self.tap = [self item:@"Gesture: Tap" action:@selector(selectTap:) menu:menu];
    self.swipe = [self item:@"Gesture: Swipe inward" action:@selector(selectSwipe:) menu:menu];
    self.pause = [self item:@"Pause" action:@selector(togglePause:) menu:menu];
    [menu addItem:NSMenuItem.separatorItem];
    [self item:@"Grant Accessibility Access…" action:@selector(grantAccess:) menu:menu];
    [self item:@"Reconnect Trackpad" action:@selector(reconnect:) menu:menu];
    [menu addItem:NSMenuItem.separatorItem];
    [self item:@"Open Trackpad Diagnostics…" action:@selector(showDiagnostics:) menu:menu];
    self.observe = [self item:@"Observe Only in Diagnostics" action:@selector(toggleObserve:) menu:menu];
    self.testPositions = [self item:@"Mark Test Position" action:NULL menu:menu];
    NSMenu *positions = [NSMenu new];
    positions.autoenablesItems = NO;
    for (NSString *label in @[@"Left edge", @"Right edge", @"Bottom edge", @"Center", @"Corners", @"Unlabeled"]) {
        [self item:label action:@selector(markTest:) menu:positions];
    }
    self.testPositions.submenu = positions;
    [self item:@"Show Diagnostic Logs in Finder" action:@selector(showLogs:) menu:menu];
    [menu addItem:NSMenuItem.separatorItem];
    [self item:@"Quit" action:@selector(quit:) menu:menu].keyEquivalent = @"q";
    self.statusItem.menu = menu;
    [self reconnect:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(willSleep:)
        name:NSWorkspaceWillSleepNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(reconnect:)
        name:NSWorkspaceDidWakeNotification object:nil];
    if (!accessibilityGranted(NO)) self.status.title = @"Grant Accessibility Access to arrange windows";
}
- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu;
    self.tap.state = self.trackpad.mode == ModeTap ? NSControlStateValueOn : NSControlStateValueOff;
    self.swipe.state = self.trackpad.mode == ModeSwipe ? NSControlStateValueOn : NSControlStateValueOff;
    self.pause.title = self.trackpad.enabled ? @"Pause" : @"Resume";
    self.observe.state = !self.diagnostics || self.diagnostics.observeOnly ? NSControlStateValueOn : NSControlStateValueOff;
    self.observe.enabled = self.diagnostics.window.visible;
    self.testPositions.enabled = self.diagnostics.window.visible;
}
- (void)selectTap:(id)sender { (void)sender; [self setGestureMode:ModeTap]; }
- (void)selectSwipe:(id)sender { (void)sender; [self setGestureMode:ModeSwipe]; }
- (void)setGestureMode:(GestureMode)mode {
    self.trackpad.mode = mode;
    [NSUserDefaults.standardUserDefaults setInteger:mode forKey:@"gestureMode"];
    self.status.title = mode == ModeTap ? @"Tap mode enabled" : @"Inward swipe mode enabled";
    [self refreshDiagnostics];
    if (self.diagnostics.window.visible) [self.diagnostics record:self.status.title];
}
- (void)togglePause:(id)sender {
    (void)sender;
    self.trackpad.enabled = !self.trackpad.enabled;
    self.status.title = self.trackpad.enabled ? @"Listening for edge gestures" : @"Paused";
    self.statusItem.button.appearsDisabled = !self.trackpad.enabled;
    [self refreshDiagnostics];
    if (self.diagnostics.window.visible) [self.diagnostics record:self.status.title];
}
- (void)grantAccess:(id)sender {
    (void)sender;
    accessibilityGranted(YES);
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}
- (void)willSleep:(NSNotification *)notification {
    (void)notification;
    [self.trackpad stop];
    self.available = NO;
    [self refreshDiagnostics];
}
- (void)reconnect:(id)sender {
    (void)sender;
    [self.trackpad stop];
    self.available = [self.trackpad start];
    self.status.title = !self.available ? @"Trackpad unavailable — try Reconnect Trackpad" :
        self.trackpad.enabled ? @"Listening for edge gestures" : @"Paused";
    [self refreshDiagnostics];
    if (self.diagnostics.window.visible) [self.diagnostics record:self.status.title];
}
- (void)refreshDiagnostics {
    [self.diagnostics setMode:self.trackpad.mode enabled:self.trackpad.enabled available:self.available];
}
- (void)showDiagnostics:(id)sender {
    (void)sender;
    if (!self.diagnostics) {
        self.diagnostics = [Diagnostics new];
    }
    __weak AppDelegate *weakSelf = self;
    self.diagnostics.onClose = ^{
        Trackpad *trackpad = weakSelf.trackpad;
        trackpad.mode = trackpad.mode;
    };
    [self refreshDiagnostics];
    [self.diagnostics show];
    self.trackpad.mode = self.trackpad.mode;
    [self refreshDiagnostics];
    [self.diagnostics recordEvent:@"accessibility_status" fields:@{ @"trusted": @(accessibilityGranted(NO)) }];
    [self.diagnostics record:@"Touch the physical trackpad. Close this window to resume normal window actions."];
}
- (void)markTest:(NSMenuItem *)sender { [self.diagnostics markTest:sender.title]; }
- (void)showLogs:(id)sender {
    (void)sender;
    if (!self.diagnostics) self.diagnostics = [Diagnostics new];
    [self.diagnostics showLogs];
}
- (void)toggleObserve:(id)sender {
    (void)sender;
    self.diagnostics.observeOnly = !self.diagnostics.observeOnly;
    // Cancel any gesture spanning the change in action behavior.
    self.trackpad.mode = self.trackpad.mode;
    [self refreshDiagnostics];
    [self.diagnostics record:self.diagnostics.observeOnly ? @"Observe only — window actions suppressed" : @"Window actions enabled"];
}
- (void)quit:(id)sender { (void)sender; [NSApp terminate:nil]; }
- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self.diagnostics finishSession:@"app_quit"];
    [self.trackpad stop];
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        __attribute__((objc_precise_lifetime)) AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
        (void)delegate;
    }
    return 0;
}
