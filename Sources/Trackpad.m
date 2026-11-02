#import "Trackpad.h"
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
}
- (void)consumeTouches:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)touches
                time:(double)time generation:(NSUInteger)generation;
- (NSUInteger)generation;
@end

static void receiveFrame(void *device, Contact *contacts, size_t count,
                         double timestamp, size_t frame) {
    (void)device; (void)frame;
    @autoreleasepool {
        Trackpad *trackpad = activeTrackpad;
        if (!trackpad) return;
        // Copy scalar values before returning: the framework owns the buffer.
        NSMutableArray *samples = [NSMutableArray array];
        for (size_t i = 0; i < count; i++) {
            if (contacts[i].state == 3 || contacts[i].state == 4) {
                [samples addObject:@{ @"id": @(contacts[i].identifier),
                    @"x": @(contacts[i].normalized.position.x),
                    @"y": @(contacts[i].normalized.position.y), @"state": @(contacts[i].state) }];
            }
        }
        NSUInteger generation = [trackpad generation];
        NSArray *snapshot = [samples copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            [trackpad consumeTouches:snapshot time:timestamp generation:generation];
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
    return YES;
}
- (void)stop {
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
    // Cancel a contact already in progress without discarding the next fresh gesture.
    _gesture = (Gesture){ .blocked = _touchCount > 0,
        .feedback = _touchCount > 0 ? FeedbackWaitingForLift : FeedbackNone };
}
- (void)setMode:(GestureMode)mode {
    _mode = mode;
    _gesture = (Gesture){ .blocked = _touchCount > 0,
        .feedback = _touchCount > 0 ? FeedbackWaitingForLift : FeedbackNone };
}
- (void)consumeTouches:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)touches
                time:(double)time generation:(NSUInteger)generation {
    if (generation != _generation || !_device) return;
    _touchCount = (int)touches.count;
    if (self.onFrame) self.onFrame(touches);
    if (!_enabled) return;
    int count = (int)touches.count;
    NSDictionary *touch = touches.firstObject;
    int identifier = [touch[@"id"] intValue];
    double x = [touch[@"x"] doubleValue], y = [touch[@"y"] doubleValue];
    if (count == 1) { _lastX = x; _lastY = y; }
    Gesture before = _gesture;
    EdgeAction action = gestureUpdate(&_gesture, _mode, count, identifier,
                                     count == 0 ? _lastX : x,
                                     count == 0 ? _lastY : y, time);
    if (count == 0 && (before.tracking || before.blocked) && self.onFeedback) {
        NSString *reason = [NSString stringWithUTF8String:gestureFeedbackText(_gesture.feedback)];
        NSString *name = action == ActionLeft ? @"Left half" : action == ActionRight ? @"Right half" : @"Almost maximize";
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
