#include "../Sources/CursorPolicy.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static CursorPolicy begin(double x, double y) {
    CursorPolicy p = {0};
    cursorPolicyConfigure(&p, true, 1);
    cursorPolicyFrame(&p, 1, 6, x, y, false, 1);
    return p;
}

int main(void) {
    CursorPolicy p = {0};
    cursorPolicyConfigure(&p, false, 1); // Tap mode or paused.
    cursorPolicyFrame(&p, 1, 6, .97, .5, false, 1);
    assert(!p.locked && !cursorPolicySuppress(&p, CursorMove, 0, 1.1));
    assert(!cursorPolicySuppress(&p, CursorDown, 0, 1.1));
    assert(!cursorPolicySuppress(&p, CursorUp, 0, 1.2));
    cursorPolicyConfigure(&p, true, 1.21);
    cursorPolicyFrame(&p, 1, 6, .97, .5, false, 1.22);
    assert(!p.locked); // Enabling capture must not seize an existing tap/drag.
    cursorPolicyFrame(&p, 0, 0, 0, 0, false, 1.23);
    cursorPolicyFrame(&p, 1, 6, .97, .5, false, 1.24);
    assert(p.locked);

    p = begin(.97, .5);
    assert(p.locked);
    assert(cursorPolicySuppress(&p, CursorMove, 0, 1.01));
    assert(cursorPolicySuppress(&p, CursorDown, 0, 1.01));
    cursorPolicyFrame(&p, 1, 6, .85, .5, false, 1.08);
    assert(p.locked);
    cursorPolicyFrame(&p, 0, 0, 0, 0, false, 1.1);
    assert(!p.locked);
    assert(cursorPolicySuppress(&p, CursorMove, 0, 1.12)); // Queued movement tail.
    assert(!cursorPolicySuppress(&p, CursorMove, 0, 1.14));
    assert(cursorPolicySuppress(&p, CursorUp, 0, 1.3)); // Matches swallowed down.
    assert(!cursorPolicySuppress(&p, CursorUp, 0, 1.31));
    assert(!cursorPolicySuppress(&p, CursorDown, 0, 1.31));

    p = begin(.03, .5);
    cursorPolicyFrame(&p, 0, 0, 0, 0, false, 1.1);
    assert(cursorPolicySuppress(&p, CursorDown, 0, 1.15)); // Delayed tap-to-click.
    assert(cursorPolicySuppress(&p, CursorUp, 0, 1.16));
    cursorPolicyFrame(&p, 1, 9, .5, .5, false, 1.17);
    assert(!cursorPolicySuppress(&p, CursorDown, 0, 1.18)); // Fresh ordinary touch.
    assert(!p.locked);
    cursorPolicyFrame(&p, 1, 9, .97, .5, false, 1.2);
    assert(!p.locked); // Must start at the edge.

    p = begin(.5, .03);
    assert(p.locked);
    cursorPolicyFrame(&p, 2, 6, .5, .05, false, 1.03);
    assert(!p.locked && p.cancellation == FeedbackMultipleFingers);
    cursorPolicyFrame(&p, 1, 6, .5, .15, false, 1.05);
    assert(!p.locked && p.blocked);
    cursorPolicyFrame(&p, 0, 0, 0, 0, false, 1.1);
    cursorPolicyFrame(&p, 1, 7, .5, .03, false, 1.2);
    assert(p.locked);

    p = begin(.97, .5);
    cursorPolicyFrame(&p, 1, 7, .97, .5, false, 1.03);
    assert(!p.locked && p.cancellation == FeedbackContactChanged);
    p = begin(.95, .5);
    cursorPolicyFrame(&p, 1, 6, .99, .5, false, 1.03);
    assert(!p.locked && p.cancellation == FeedbackWrongDirection);
    p = begin(.97, .5);
    cursorPolicyFrame(&p, 1, 6, .9, .56, false, 1.03);
    assert(!p.locked && p.cancellation == FeedbackSidewaysDrift);
    p = begin(.97, .5);
    cursorPolicyFrame(&p, 1, 6, NAN, .5, false, 1.03);
    assert(!p.locked && p.cancellation == FeedbackInvalidPosition);

    p = begin(.97, .5);
    cursorPolicyTick(&p, 1.251); // Device stopped delivering frames.
    assert(!p.locked && p.cancellation == FeedbackCursorCaptureCancelled);
    assert(!cursorPolicySuppress(&p, CursorMove, 0, 1.3));
    p = begin(.97, .5);
    for (int i = 1; i <= 6; i++) cursorPolicyFrame(&p, 1, 6, .97, .5, false, 1 + i * .1);
    cursorPolicyTick(&p, 1.701);
    assert(!p.locked && p.cancellation == FeedbackTooLong);

    p = begin(.97, .5);
    assert(cursorPolicySuppress(&p, CursorDown, 1, 1.01));
    cursorPolicyConfigure(&p, false, 1.02); // Pause, mode change, sleep, or stop.
    assert(!cursorPolicySuppress(&p, CursorMove, 0, 1.021));
    assert(cursorPolicySuppress(&p, CursorDown, 1, 1.025)); // No unmatched repeated down.
    assert(cursorPolicySuppress(&p, CursorUp, 1, 1.03));
    assert(!cursorPolicySuppress(&p, CursorDown, 1, 1.04));
    cursorPolicyConfigure(&p, true, 1.05);
    cursorPolicyFrame(&p, 1, 6, .97, .5, false, 1.06);
    assert(!p.locked); // No recapture mid-touch after a setting change.

    p = (CursorPolicy){0};
    cursorPolicyConfigure(&p, true, 1);
    cursorPolicyFrame(&p, 1, 6, .97, .5, true, 1);
    assert(!p.locked); // Existing drag continues normally.
    assert(!cursorPolicySuppress(&p, CursorMove, 0, 1.01));
    assert(!cursorPolicySuppress(&p, CursorUp, 0, 1.02));
    p = begin(.02, .02);
    assert(!p.locked); // Inactive corner.
    puts("Cursor capture policy tests passed");
}
