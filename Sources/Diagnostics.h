#import <AppKit/AppKit.h>
#import "Gesture.h"

@interface Diagnostics : NSWindowController
@property(nonatomic) BOOL observeOnly;
@property(nonatomic, copy) void (^onClose)(void);
- (void)show;
- (void)updateTouches:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)touches;
- (void)record:(NSString *)message;
- (void)setMode:(GestureMode)mode enabled:(BOOL)enabled available:(BOOL)available;
@end
