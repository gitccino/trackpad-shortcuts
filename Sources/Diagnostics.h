#import <AppKit/AppKit.h>
#import "Gesture.h"

@interface Diagnostics : NSWindowController
@property(nonatomic) BOOL observeOnly;
@property(nonatomic, copy) void (^onClose)(void);
- (void)show;
- (void)updateTouches:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)touches;
- (void)record:(NSString *)message;
- (void)setMode:(GestureMode)mode enabled:(BOOL)enabled available:(BOOL)available;
- (void)recordRawFrame:(NSDictionary *)frame;
- (void)recordEvent:(NSString *)type fields:(NSDictionary *)fields;
- (void)markTest:(NSString *)label;
- (void)showLogs;
- (void)finishSession:(NSString *)reason;
@end
