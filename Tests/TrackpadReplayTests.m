#import "../Sources/Trackpad.h"
#include <stdio.h>
#include <stdlib.h>

@interface Trackpad (RecordedFrameTests)
- (void)processContactFrame:(NSDictionary *)raw;
@end

static void require(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

static NSArray<NSDictionary *> *fixture(void) {
    NSData *data = [NSData dataWithContentsOfFile:@"Tests/Fixtures/identity-change.json"];
    require(data != nil, @"Recorded input fixture is missing");
    NSArray *frames = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    require(frames.count > 0, @"Recorded input fixture is invalid");
    return frames;
}

int main(void) {
    @autoreleasepool {
        Trackpad *trackpad = [Trackpad new];
        __block NSMutableArray *actions = [NSMutableArray array];
        __block NSMutableArray *results = [NSMutableArray array];
        trackpad.onAction = ^(EdgeAction action) { [actions addObject:@(action)]; };
        trackpad.onEvent = ^(NSString *type, NSDictionary *event) {
            if ([type isEqual:@"gesture_result"]) [results addObject:event];
        };
        // Real stationary right-edge tap: id changes 12 → 7; path stays 6.
        for (NSDictionary *frame in fixture()) [trackpad processContactFrame:frame];
        require(actions.count == 1 && [actions.firstObject intValue] == ActionRight,
            @"A stationary tap with stable path must survive a raw id change");
        require(results.count == 1 && [results.firstObject[@"feedback"] intValue] == FeedbackRecognized,
            @"The recorded tap must finish as recognized");

        [actions removeAllObjects]; [results removeAllObjects];
        // Changing the path really does break continuity, even if id stays fixed.
        for (NSDictionary *frame in fixture()) {
            NSMutableDictionary *changedFrame = [frame mutableCopy];
            NSMutableArray *contacts = [NSMutableArray array];
            for (NSDictionary *contact in frame[@"contacts"]) {
                NSMutableDictionary *changed = [contact mutableCopy];
                changed[@"path"] = [contact[@"id"] intValue] == 7 ? @7 : @6;
                changed[@"id"] = @12;
                [contacts addObject:changed];
            }
            changedFrame[@"contacts"] = contacts;
            [trackpad processContactFrame:changedFrame];
        }
        require(actions.count == 0 && results.count == 1 &&
            [results.firstObject[@"feedback"] intValue] == FeedbackContactChanged,
            @"A changed path must still cancel the gesture");

        [actions removeAllObjects]; [results removeAllObjects];
        BOOL injected = NO;
        for (NSDictionary *frame in fixture()) {
            NSMutableDictionary *changedFrame = [frame mutableCopy];
            NSMutableArray *contacts = [frame[@"contacts"] mutableCopy];
            if (!injected && [contacts.firstObject[@"state"] intValue] == 4) {
                NSMutableDictionary *second = [contacts.firstObject mutableCopy];
                second[@"path"] = @99;
                second[@"id"] = @99;
                [contacts addObject:second];
                injected = YES;
            }
            changedFrame[@"contacts"] = contacts;
            [trackpad processContactFrame:changedFrame];
        }
        require(injected && actions.count == 0 && results.count == 1 &&
            [results.firstObject[@"feedback"] intValue] == FeedbackMultipleFingers,
            @"A second finger must still cancel until all contacts lift");
        puts("Recorded trackpad replay tests passed");
    }
    return 0;
}
