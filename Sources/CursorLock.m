#import "CursorLock.h"
#import "CursorPolicy.h"
#import "CursorEventFilter.h"
#import <ApplicationServices/ApplicationServices.h>
#include <pthread.h>

@interface CursorLock () {
    pthread_mutex_t _mutex;
    CursorPolicy _policy;
    CFMachPortRef _tap;
    CFRunLoopSourceRef _source;
    CFRunLoopRef _loop;
    BOOL _stopping;
    BOOL _requested;
    BOOL _available;
    NSThread *_thread;
    NSUInteger _suppressedMoves, _suppressedClicks;
}
- (CGEventRef)filterType:(CGEventType)type event:(CGEventRef)event;
- (void)runFilter:(id)unused;
- (void)expirePolicy;
@end

static CGEventRef filterPointer(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *context) {
    (void)proxy;
    return [(__bridge CursorLock *)context filterType:type event:event];
}
static void expirePointer(CFRunLoopTimerRef timer, void *context) {
    (void)timer;
    [(__bridge CursorLock *)context expirePolicy];
}

@implementation CursorLock
- (instancetype)init {
    if ((self = [super init])) pthread_mutex_init(&_mutex, NULL);
    return self;
}
- (void)dealloc { pthread_mutex_destroy(&_mutex); }
- (BOOL)available {
    pthread_mutex_lock(&_mutex);
    BOOL result = _available && _tap && _loop && CGEventTapIsEnabled(_tap);
    pthread_mutex_unlock(&_mutex);
    return result;
}
- (BOOL)start {
    pthread_mutex_lock(&_mutex);
    if (_tap) {
        BOOL wasAvailable = _available;
        if (!_stopping && !CGEventTapIsEnabled(_tap)) {
            CGEventTapEnable(_tap, true);
        }
        _available = !_stopping && _loop && CGEventTapIsEnabled(_tap);
        if (!wasAvailable && _available)
            cursorPolicyConfigure(&_policy, _requested, NSProcessInfo.processInfo.systemUptime);
        else _policy.enabled = _requested && _available;
        BOOL result = _available;
        pthread_mutex_unlock(&_mutex);
        return result;
    }
    CGEventMask mask = CGEventMaskBit(kCGEventMouseMoved) |
        CGEventMaskBit(kCGEventLeftMouseDragged) | CGEventMaskBit(kCGEventRightMouseDragged) | CGEventMaskBit(kCGEventOtherMouseDragged) |
        CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventLeftMouseUp) |
        CGEventMaskBit(kCGEventRightMouseDown) | CGEventMaskBit(kCGEventRightMouseUp) |
        CGEventMaskBit(kCGEventOtherMouseDown) | CGEventMaskBit(kCGEventOtherMouseUp);
    _tap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
        mask, filterPointer, (__bridge void *)self);
    if (!_tap) { pthread_mutex_unlock(&_mutex); return NO; }
    _source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _tap, 0);
    if (!_source) { CFRelease(_tap); _tap = NULL; pthread_mutex_unlock(&_mutex); return NO; }
    _available = NO;
    _stopping = NO;
    cursorPolicyConfigure(&_policy, false, NSProcessInfo.processInfo.systemUptime);
    _thread = [[NSThread alloc] initWithTarget:self selector:@selector(runFilter:) object:nil];
    _thread.name = @"Trackpad pointer filter";
    [_thread start];
    pthread_mutex_unlock(&_mutex);
    return YES;
}
- (void)runFilter:(id)unused {
    (void)unused;
    @autoreleasepool {
        pthread_mutex_lock(&_mutex);
        _loop = CFRunLoopGetCurrent();
        CFRetain(_loop);
        CFRunLoopAddSource(_loop, _source, kCFRunLoopCommonModes);
        CFRunLoopTimerContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
        CFRunLoopTimerRef timer = CFRunLoopTimerCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.025,
            0.025, 0, 0, expirePointer, &context);
        CFRunLoopAddTimer(_loop, timer, kCFRunLoopCommonModes);
        BOOL shouldRun = !_stopping;
        _available = shouldRun && CGEventTapIsEnabled(_tap);
        cursorPolicyConfigure(&_policy, _requested && _available, NSProcessInfo.processInfo.systemUptime);
        pthread_mutex_unlock(&_mutex);
        // Periodic expiry keeps a missing release frame from trapping the pointer.
        if (shouldRun) CFRunLoopRun();
        pthread_mutex_lock(&_mutex);
        CFRunLoopRemoveTimer(_loop, timer, kCFRunLoopCommonModes);
        CFRelease(timer);
        CGEventTapEnable(_tap, false);
        CFMachPortInvalidate(_tap);
        CFRunLoopRemoveSource(_loop, _source, kCFRunLoopCommonModes);
        CFRelease(_source); _source = NULL;
        CFRelease(_tap); _tap = NULL;
        CFRelease(_loop); _loop = NULL;
        _available = NO;
        _thread = nil;
        pthread_mutex_unlock(&_mutex);
    }
}
- (void)expirePolicy {
    pthread_mutex_lock(&_mutex);
    cursorPolicyTick(&_policy, NSProcessInfo.processInfo.systemUptime);
    if (_stopping && _loop) CFRunLoopStop(_loop);
    if (_tap && !_stopping && !CGEventTapIsEnabled(_tap)) {
        _available = NO;
        if (_policy.enabled) {
            cursorPolicyConfigure(&_policy, false, NSProcessInfo.processInfo.systemUptime);
            if (_policy.blocked) _policy.cancellation = FeedbackCursorCaptureCancelled;
        }
    }
    pthread_mutex_unlock(&_mutex);
}
- (void)configureEnabled:(BOOL)enabled mode:(GestureMode)mode {
    pthread_mutex_lock(&_mutex);
    _requested = enabled && mode == ModeSwipe;
    cursorPolicyConfigure(&_policy, _requested && _available, NSProcessInfo.processInfo.systemUptime);
    pthread_mutex_unlock(&_mutex);
}
- (NSDictionary *)updateFrameCount:(int)count path:(int)path x:(double)x y:(double)y {
    pthread_mutex_lock(&_mutex);
    double now = NSProcessInfo.processInfo.systemUptime;
    // Preserve a timeout cancellation on the first subsequent lift frame.
    cursorPolicyTick(&_policy, now);
    GestureFeedback pending = _policy.cancellation;
    BOOL buttonHeld = false;
    if (count == 1 && !_policy.tracking && !_policy.blocked && _policy.enabled) {
        buttonHeld = CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonLeft) ||
            CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonRight) ||
            CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonCenter);
    }
    cursorPolicyFrame(&_policy, count, path, x, y, buttonHeld, now);
    GestureFeedback feedback = _policy.cancellation != FeedbackNone ? _policy.cancellation : pending;
    NSDictionary *result = @{ @"locked": @(_policy.locked), @"available": @(_available),
        @"cancellation": @(feedback), @"suppressed_move_events": @(_suppressedMoves), @"suppressed_click_events": @(_suppressedClicks) };
    pthread_mutex_unlock(&_mutex);
    return result;
}
- (CGEventRef)filterType:(CGEventType)type event:(CGEventRef)event {
    pthread_mutex_lock(&_mutex);
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        cursorPolicyConfigure(&_policy, false, NSProcessInfo.processInfo.systemUptime);
        if (_policy.blocked) _policy.cancellation = FeedbackCursorCaptureCancelled;
        if (_tap && !_stopping) {
            CGEventTapEnable(_tap, true);
            _available = CGEventTapIsEnabled(_tap);
            _policy.enabled = _requested && _available;
        }
        pthread_mutex_unlock(&_mutex);
        return event;
    }
    CGEventRef result = filterCursorEvent(&_policy, type, event, NSProcessInfo.processInfo.systemUptime);
    if (!result && event) {
        CursorInput input;
        if (cursorInputForEvent(type, &input)) {
            if (input == CursorMove) _suppressedMoves++; else _suppressedClicks++;
        }
    }
    pthread_mutex_unlock(&_mutex);
    return result;
}
- (void)reset {
    pthread_mutex_lock(&_mutex);
    cursorPolicyConfigure(&_policy, false, NSProcessInfo.processInfo.systemUptime);
    _policy.enabled = _requested && _available;
    pthread_mutex_unlock(&_mutex);
}
- (void)stop {
    pthread_mutex_lock(&_mutex);
    _requested = NO;
    cursorPolicyConfigure(&_policy, false, NSProcessInfo.processInfo.systemUptime);
    _available = NO;
    _stopping = YES;
    if (_tap) CGEventTapEnable(_tap, false);
    if (_loop) { CFRunLoopStop(_loop); CFRunLoopWakeUp(_loop); }
    pthread_mutex_unlock(&_mutex);
}
@end
