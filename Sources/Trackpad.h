#import <Foundation/Foundation.h>
#import "Gesture.h"

@interface Trackpad : NSObject
@property(nonatomic) BOOL enabled;
@property(nonatomic) GestureMode mode;
@property(nonatomic, copy) void (^onAction)(EdgeAction);
- (BOOL)start;
- (void)stop;
@end
