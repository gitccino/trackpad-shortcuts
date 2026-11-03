#import <Foundation/Foundation.h>
#import "Gesture.h"
@class CursorLock;

@interface Trackpad : NSObject
@property(nonatomic) BOOL enabled;
@property(nonatomic) GestureMode mode;
@property(nonatomic, strong) CursorLock *cursorLock;
@property(nonatomic, copy) void (^onAction)(EdgeAction);
// Delivered on the main thread, including while actions are paused.
// Each sample contains raw id, stable contact path, x, y and state
// (3 = touch down, 4 = touching). Recognition and trails use path, not raw id.
@property(nonatomic, copy) void (^onFrame)(NSArray<NSDictionary<NSString *, NSNumber *> *> *);
@property(nonatomic, copy) void (^onFeedback)(NSString *);
// All framework contact states, before the recognizer's touch-state filter.
@property(nonatomic, copy) void (^onRawFrame)(NSDictionary *);
@property(nonatomic, copy) void (^onEvent)(NSString *, NSDictionary *);
- (BOOL)start;
- (void)stop;
@end
