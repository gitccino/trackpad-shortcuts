#include "../Sources/CursorEventFilter.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    CursorPolicy p = {0};
    cursorPolicyConfigure(&p, true, 1);
    CGEventRef move = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(200, 300), kCGMouseButtonLeft);
    assert(move);
    assert(filterCursorEvent(&p, kCGEventMouseMoved, move, 1) == move);
    cursorPolicyFrame(&p, 1, 6, .97, .5, false, 1);
    assert(filterCursorEvent(&p, kCGEventMouseMoved, move, 1.01) == NULL);
    assert(filterCursorEvent(&p, kCGEventLeftMouseDragged, move, 1.01) == NULL);
    assert(filterCursorEvent(&p, kCGEventScrollWheel, move, 1.01) == move);
    CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointMake(200, 300), kCGMouseButtonLeft);
    CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, CGPointMake(200, 300), kCGMouseButtonLeft);
    assert(down && up);
    assert(filterCursorEvent(&p, kCGEventLeftMouseDown, down, 1.02) == NULL);
    cursorPolicyFrame(&p, 0, 0, 0, 0, false, 1.1);
    assert(filterCursorEvent(&p, kCGEventLeftMouseUp, up, 1.4) == NULL);
    assert(filterCursorEvent(&p, kCGEventMouseMoved, move, 1.4) == move);
    CGPoint unchanged = CGEventGetLocation(move);
    assert(unchanged.x == 200 && unchanged.y == 300); // No cursor warps or event replay.
    CFRelease(move); CFRelease(down); CFRelease(up);
    puts("Native cursor event filter tests passed");
}
