#import "SessionLog.h"
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <unistd.h>

// JSON cannot represent nonfinite sensor values. Preserve them explicitly.
static id jsonSafe(id value) {
    if ([value isKindOfClass:NSNumber.class]) {
        double number = [value doubleValue];
        if (!isfinite(number)) return isnan(number) ? @"NaN" : number > 0 ? @"Infinity" : @"-Infinity";
    } else if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *array = [NSMutableArray array];
        for (id item in value) [array addObject:jsonSafe(item)];
        return array;
    } else if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        for (id key in value) dictionary[key] = jsonSafe(value[key]);
        return dictionary;
    }
    return value;
}

@interface SessionLog () {
    dispatch_queue_t _writer;
    int _descriptor;
    BOOL _failed;
    NSUInteger _sequence;
}
@property(nonatomic, readwrite) BOOL active;
@property(nonatomic, readwrite, strong) NSURL *fileURL;
@end

@implementation SessionLog
+ (NSURL *)directoryURL {
    NSURL *library = [NSFileManager.defaultManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject;
    return [[library URLByAppendingPathComponent:@"Logs" isDirectory:YES]
        URLByAppendingPathComponent:@"Trackpad Shortcuts" isDirectory:YES];
}
- (instancetype)init {
    if ((self = [super init])) {
        _descriptor = -1;
        _writer = dispatch_queue_create("xyz.trackpadshortcuts.session-log", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
- (void)dealloc { if (_descriptor >= 0) close(_descriptor); }
- (BOOL)startInDirectory:(NSURL *)directory metadata:(NSDictionary *)metadata error:(NSError **)error {
    if (self.active) [self finish:@"restarted"];
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *filename = [NSString stringWithFormat:@"Session-%@-%@.jsonl", [formatter stringFromDate:NSDate.date], NSUUID.UUID.UUIDString];
    self.fileURL = [directory URLByAppendingPathComponent:filename];
    _descriptor = open(self.fileURL.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (_descriptor < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    _failed = NO;
    _sequence = 0;
    self.active = YES;
    [self append:@"session_start" fields:metadata];
    return YES;
}
- (void)fail:(NSError *)error {
    if (_failed) return;
    _failed = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.onError) self.onError(error);
    });
}
- (void)append:(NSString *)type fields:(NSDictionary *)fields {
    if (!self.active) return;
    NSDictionary *entry = @{ @"schema_version": @1, @"sequence": @(_sequence++), @"type": type,
        @"wall_time": @(NSDate.date.timeIntervalSince1970),
        @"uptime": @(NSProcessInfo.processInfo.systemUptime), @"data": fields };
    dispatch_async(_writer, ^{
        @autoreleasepool {
            if (self->_failed) return;
            NSError *error = nil;
            NSData *json = [NSJSONSerialization dataWithJSONObject:jsonSafe(entry) options:NSJSONWritingSortedKeys error:&error];
            if (!json) { [self fail:error]; return; }
            NSMutableData *line = [json mutableCopy];
            [line appendBytes:"\n" length:1];
            const unsigned char *bytes = line.bytes;
            size_t remaining = line.length;
            while (remaining) {
                ssize_t written = write(self->_descriptor, bytes, remaining);
                if (written < 0 && errno == EINTR) continue;
                if (written <= 0) {
                    [self fail:[NSError errorWithDomain:NSPOSIXErrorDomain code:written < 0 ? errno : EIO userInfo:nil]];
                    return;
                }
                bytes += written;
                remaining -= (size_t)written;
            }
        }
    });
}
- (void)finish:(NSString *)reason {
    if (!self.active) return;
    [self append:@"session_end" fields:@{ @"reason": reason }];
    self.active = NO;
    // Drain queued frames before flushing and closing. No per-frame main-thread I/O.
    dispatch_sync(_writer, ^{
        if (fsync(self->_descriptor) < 0) [self fail:[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]];
        if (close(self->_descriptor) < 0) [self fail:[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]];
        self->_descriptor = -1;
    });
}
@end
