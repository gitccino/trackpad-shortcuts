#import <Foundation/Foundation.h>
#import "Gesture.h"

@interface Trackpad : NSObject
@property(nonatomic) BOOL enabled;
@property(nonatomic) GestureMode mode;
@property(nonatomic, copy) void (^onAction)(EdgeAction);
// Delivered on the main thread, including while actions are paused.
// Each sample contains id, x, y and state (3 = touch down, 4 = touching).
@property(nonatomic, copy) void (^onFrame)(NSArray<NSDictionary<NSString *, NSNumber *> *> *);
@property(nonatomic, copy) void (^onFeedback)(NSString *);
- (BOOL)start;
- (void)stop;
@end
