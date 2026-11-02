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
    double _lastX, _lastY;
    NSUInteger _generation;
}
- (void)consumeCount:(int)count identifier:(int)identifier x:(double)x y:(double)y
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
        int touching = 0, identifier = 0;
        double x = 0, y = 0;
        for (size_t i = 0; i < count; i++) {
            if (contacts[i].state == 3 || contacts[i].state == 4) {
                touching++;
                identifier = contacts[i].identifier;
                x = contacts[i].normalized.position.x;
                y = contacts[i].normalized.position.y;
            }
        }
        NSUInteger generation = [trackpad generation];
        dispatch_async(dispatch_get_main_queue(), ^{
            [trackpad consumeCount:touching identifier:identifier x:x y:y
                             time:timestamp generation:generation];
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
}
- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    // Require a fresh all-fingers-up frame after any toggle.
    _gesture = (Gesture){ .blocked = true };
}
- (void)setMode:(GestureMode)mode {
    _mode = mode;
    _gesture = (Gesture){ .blocked = true };
}
- (void)consumeCount:(int)count identifier:(int)identifier x:(double)x y:(double)y
                time:(double)time generation:(NSUInteger)generation {
    if (generation != _generation || !_enabled || !_device) return;
    if (count == 1) { _lastX = x; _lastY = y; }
    EdgeAction action = gestureUpdate(&_gesture, _mode, count, identifier,
                                     count == 0 ? _lastX : x,
                                     count == 0 ? _lastY : y, time);
    if (action != ActionNone && self.onAction) self.onAction(action);
}
@end
