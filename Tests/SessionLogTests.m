#import "../Sources/SessionLog.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static NSArray *entries(NSURL *file) {
    NSString *text = [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:NULL];
    assert(text && [text hasSuffix:@"\n"]);
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (!line.length) continue;
        NSDictionary *entry = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        assert(entry);
        [result addObject:entry];
    }
    return result;
}

int main(void) {
    @autoreleasepool {
        NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
            URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        SessionLog *log = [SessionLog new];
        NSError *error = nil;
        assert([log startInDirectory:directory metadata:@{ @"mode": @"tap" } error:&error]);
        NSURL *firstFile = log.fileURL;
        for (int i = 0; i < 1000; i++) {
            [log append:@"touch_frame" fields:@{ @"frame": @(i), @"contacts": @[
                @{ @"id": @1, @"state": @(i % 8), @"x": @0.97, @"y": @0.5 }
            ] }];
        }
        [log append:@"touch_frame" fields:@{ @"contacts": @[@{ @"x": @(NAN), @"y": @(INFINITY) }] }];
        [log finish:@"window_closed"];
        assert(!log.active);
        [log append:@"should_not_record" fields:@{}];
        [log finish:@"duplicate_close"];
        NSArray *records = entries(firstFile);
        assert(records.count == 1003);
        assert([records.firstObject[@"type"] isEqual:@"session_start"]);
        assert([records.lastObject[@"type"] isEqual:@"session_end"]);
        for (NSUInteger i = 0; i < records.count; i++) {
            assert([records[i][@"sequence"] unsignedIntegerValue] == i);
            assert([records[i][@"schema_version"] intValue] == 1);
            if (i >= 1 && i <= 1000) assert([records[i][@"data"][@"frame"] unsignedIntegerValue] == i - 1);
        }
        assert([records[1001][@"data"][@"contacts"][0][@"x"] isEqual:@"NaN"]);
        assert([records[1001][@"data"][@"contacts"][0][@"y"] isEqual:@"Infinity"]);
        assert([log startInDirectory:directory metadata:@{} error:&error]);
        assert(![log.fileURL isEqual:firstFile]);
        [log finish:@"app_quit"];
        assert(entries(log.fileURL).count == 2);
        assert(entries(firstFile).count == 1003);
        // A regular file cannot be used as the destination directory.
        assert(![log startInDirectory:firstFile metadata:@{} error:&error]);
        assert(error && !log.active);
        [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
        puts("Session log tests passed");
    }
    return 0;
}
