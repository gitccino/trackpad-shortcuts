#import <Foundation/Foundation.h>

// Main-thread API; serialization and file writes run on one background queue.
@interface SessionLog : NSObject
@property(nonatomic, readonly) BOOL active;
@property(nonatomic, readonly, strong) NSURL *fileURL;
@property(nonatomic, copy) void (^onError)(NSError *);
+ (NSURL *)directoryURL;
- (BOOL)startInDirectory:(NSURL *)directory metadata:(NSDictionary *)metadata error:(NSError **)error;
- (void)append:(NSString *)type fields:(NSDictionary *)fields;
- (void)finish:(NSString *)reason;
@end
