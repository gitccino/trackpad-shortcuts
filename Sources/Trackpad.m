#import "Trackpad.h"
#import "CursorLock.h"
#include <dlfcn.h>
#include <stdint.h>

// Reverse-engineered MultitouchSupport ABI; see README's technical references.
typedef struct { float x, y; } ContactPoint;
typedef struct { ContactPoint position, velocity; } ContactVector;
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t path, state, identifier, hand;
    ContactVector normalized;
    float pressure;
    int32_t reserved1;
    float angle, major, minor;
    ContactVector absolute;
    int32_t reserved2, reserved3;
    float density;
} Contact;
_Static_assert(sizeof(Contact) == 96, "Unexpected multitouch contact ABI");

typedef void (*FrameCallback)(void *, Contact *, size_t, double, size_t);
static __weak Trackpad *activeTrackpad;

@interface Trackpad () {
    void *_library;
    void *_device;
    void (*_register)(void *, FrameCallback);
    void (*_unregister)(void *, FrameCallback);
    int (*_start)(void *, int);
    int (*_stop)(void *);
    void (*_release)(void *);
    Gesture _gesture;
    int _touchCount;
    double _lastX, _lastY;
    NSUInteger _generation;
    NSDictionary *_lastCursorState;
}
- (void)consumeFrame:(NSDictionary *)raw generation:(NSUInteger)generation;
- (void)processContactFrame:(NSDictionary *)raw;
- (NSUInteger)generation;
@end

static void receiveFrame(void *device, Contact *contacts, size_t count,
                         double timestamp, size_t frame) {
    (void)device;
    @autoreleasepool {
        NSTimeInterval callbackUptime = NSProcessInfo.processInfo.systemUptime;
        Trackpad *trackpad = activeTrackpad;
        if (!trackpad) return;
        // Copy scalar values before returning: the framework owns the buffer.
        NSUInteger touchingCount = 0;
        int path = 0;
        double x = 0, y = 0;
        NSMutableArray *rawContacts = [NSMutableArray array];
        for (size_t i = 0; i < count; i++) {
            Contact c = contacts[i];
            [rawContacts addObject:@{ @"id": @(c.identifier), @"path": @(c.path), @"state": @(c.state),
                @"x": @(c.normalized.position.x), @"y": @(c.normalized.position.y),
                @"velocity_x": @(c.normalized.velocity.x), @"velocity_y": @(c.normalized.velocity.y),
                @"contact_timestamp": @(c.timestamp), @"z_total": @(c.pressure),
                @"major_axis": @(c.major), @"minor_axis": @(c.minor), @"angle": @(c.angle) }];
            if (contacts[i].state == 3 || contacts[i].state == 4) {
                touchingCount++;
                path = c.path; x = c.normalized.position.x; y = c.normalized.position.y;
            }
        }
        NSUInteger generation = [trackpad generation];
        NSDictionary *capture = [trackpad.cursorLock updateFrameCount:(int)touchingCount path:path x:x y:y] ?: @{};
        NSDictionary *raw = @{ @"device_timestamp": @(timestamp), @"frame": @(frame),
            @"callback_uptime": @(callbackUptime),
            @"stream_generation": @(generation), @"contacts": [rawContacts copy], @"touching_count": @(touchingCount),
            @"cursor_capture": capture };
        dispatch_async(dispatch_get_main_queue(), ^{
            [trackpad consumeFrame:raw generation:generation];
        });
    }
}

@implementation Trackpad
- (NSUInteger)generation {
    @synchronized (self) { return _generation; }
}
- (instancetype)init {
    if ((self = [super init])) _enabled = YES;
    return self;
}
- (BOOL)start {
    if (_device) return YES;
    if (!_library) _library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);
    if (!_library) return NO;
    void *(*createDefault)(void) = dlsym(_library, "MTDeviceCreateDefault");
    _register = dlsym(_library, "MTRegisterContactFrameCallback");
    _unregister = dlsym(_library, "MTUnregisterContactFrameCallback");
    _start = dlsym(_library, "MTDeviceStart");
    _stop = dlsym(_library, "MTDeviceStop");
    _release = dlsym(_library, "MTDeviceRelease");
    if (!createDefault || !_register || !_unregister || !_start || !_stop || !_release) return NO;
    _device = createDefault();
    if (!_device) return NO;
    activeTrackpad = self;
    _register(_device, receiveFrame);
    if (_start(_device, 0) != 0) { [self stop]; return NO; }
    [self.cursorLock configureEnabled:_enabled mode:_mode];
    if (self.onEvent) self.onEvent(@"stream_start", @{ @"stream_generation": @(_generation) });
    return YES;
}
- (void)stop {
    [self.cursorLock configureEnabled:NO mode:_mode];
    [self.cursorLock reset];
    if (_device && self.onEvent) self.onEvent(@"stream_stop", @{ @"stream_generation": @(_generation), @"touching_count": @(_touchCount) });
    activeTrackpad = nil;
    @synchronized (self) { _generation++; }
    if (_device) {
        _stop(_device);
        _unregister(_device, receiveFrame);
        _release(_device);
        _device = NULL;
    }
    _gesture = (Gesture){0};
    _touchCount = 0;
    if (self.onFrame) self.onFrame(@[]);
}
- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [self.cursorLock configureEnabled:enabled mode:_mode];
    // Cancel a contact already in progress without discarding the next fresh gesture.
    _gesture = (Gesture){ .blocked = _touchCount > 0,
        .feedback = _touchCount > 0 ? FeedbackWaitingForLift : FeedbackNone };
    if (self.onEvent) self.onEvent(@"recognizer_reset", @{ @"reason": @"enabled_changed", @"enabled": @(_enabled), @"touching_count": @(_touchCount) });
}
- (void)setMode:(GestureMode)mode {
    _mode = mode;
    [self.cursorLock configureEnabled:_enabled mode:mode];
    _gesture = (Gesture){ .blocked = _touchCount > 0,
        .feedback = _touchCount > 0 ? FeedbackWaitingForLift : FeedbackNone };
    if (self.onEvent) self.onEvent(@"recognizer_reset", @{ @"reason": @"mode_set", @"mode": _mode == ModeTap ? @"tap" : @"swipe", @"touching_count": @(_touchCount) });
}
- (void)consumeFrame:(NSDictionary *)raw generation:(NSUInteger)generation {
    if (generation != _generation || !_device) return;
    if (self.onRawFrame) self.onRawFrame(raw);
    NSDictionary *capture = raw[@"cursor_capture"];
    if (capture && (![_lastCursorState[@"locked"] isEqual:capture[@"locked"]] ||
                    ![_lastCursorState[@"cancellation"] isEqual:capture[@"cancellation"]] ||
                    ![_lastCursorState[@"available"] isEqual:capture[@"available"]])) {
        _lastCursorState = capture;
        if (self.onEvent) {
            NSMutableDictionary *state = [capture mutableCopy];
            state[@"message"] = [capture[@"locked"] boolValue] ? @"Cursor frozen for edge swipe" : @"Cursor released";
            self.onEvent(@"cursor_capture", state);
        }
    }
    [self processContactFrame:raw];
}
// Shared by live input and the recorded-frame regression test. Device lifecycle
// checks stay in consumeFrame so replay requires no hardware or permissions.
- (void)processContactFrame:(NSDictionary *)raw {
    NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *touches = [NSMutableArray array];
    for (NSDictionary *contact in raw[@"contacts"]) {
        int state = [contact[@"state"] intValue];
        if (state == 3 || state == 4) [touches addObject:contact];
    }
    double time = [raw[@"device_timestamp"] doubleValue];
    _touchCount = (int)touches.count;
    if (self.onFrame) self.onFrame(touches);
    if (!_enabled) return;
    int count = (int)touches.count;
    NSDictionary *touch = touches.firstObject;
    int identifier = [touch[@"path"] intValue];
    double x = [touch[@"x"] doubleValue], y = [touch[@"y"] doubleValue];
    if (count == 1) { _lastX = x; _lastY = y; }
    GestureFeedback captureCancellation = [raw[@"cursor_capture"][@"cancellation"] intValue];
    if (_mode == ModeSwipe && captureCancellation != FeedbackNone) {
        _gesture.blocked = true;
        _gesture.feedback = captureCancellation;
    }
    Gesture before = _gesture;
    EdgeAction action = gestureUpdate(&_gesture, _mode, count, identifier,
                                     count == 0 ? _lastX : x,
                                     count == 0 ? _lastY : y, time);
    if (count == 0 && (before.tracking || before.blocked) && self.onEvent) {
        self.onEvent(@"gesture_result", @{ @"device_timestamp": @(time), @"mode": _mode == ModeTap ? @"tap" : @"swipe",
            @"action": @(action), @"start_edge": @(before.edge), @"feedback": @(_gesture.feedback),
            @"reason": [NSString stringWithUTF8String:gestureFeedbackText(_gesture.feedback)],
            @"has_start": @(before.tracking), @"blocked": @(before.blocked),
            @"contact_identity": @"path", @"contact_path": @(before.identifier),
            @"duration_ms": before.tracking ? @((time - before.started) * 1000) : NSNull.null,
            @"start_x": @(before.startX), @"start_y": @(before.startY),
            @"end_x": @(_lastX), @"end_y": @(_lastY), @"max_distance": @(before.maxDistance) });
    }
    if (count == 0 && (before.tracking || before.blocked) && self.onFeedback) {
        NSString *reason = [NSString stringWithUTF8String:gestureFeedbackText(_gesture.feedback)];
        NSString *name = action == ActionLeft ? @"Left half" : action == ActionRight ? @"Right half" : @"Almost maximize / Hide app";
        NSString *summary = action == ActionNone ? reason : [NSString stringWithFormat:@"Recognized: %@", name];
        if (before.tracking) {
            summary = [summary stringByAppendingFormat:@" · %.0f ms · start %.1f%%, %.1f%% → end %.1f%%, %.1f%%",
                (time - before.started) * 1000, before.startX * 100, before.startY * 100,
                _lastX * 100, _lastY * 100];
        }
        self.onFeedback(summary);
    }
    if (action != ActionNone && self.onAction) self.onAction(action);
}
@end
