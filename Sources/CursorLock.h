#import <Foundation/Foundation.h>
#import "Gesture.h"

// updateFrame runs directly on the touch callback thread, before main-thread work.
@interface CursorLock : NSObject
@property(nonatomic, readonly) BOOL available;
- (BOOL)start;
- (void)configureEnabled:(BOOL)enabled mode:(GestureMode)mode;
- (NSDictionary *)updateFrameCount:(int)count path:(int)path x:(double)x y:(double)y;
- (void)reset;
- (void)stop;
@end
