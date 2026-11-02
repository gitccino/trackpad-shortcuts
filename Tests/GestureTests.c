#include "../Sources/Gesture.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static EdgeAction sequence(GestureMode mode, double x, double y,
                           double endX, double endY, double duration) {
    Gesture g = {0};
    assert(gestureUpdate(&g, mode, 1, 1, x, y, 1) == ActionNone);
    assert(gestureUpdate(&g, mode, 1, 1, endX, endY, 1 + duration / 2) == ActionNone);
    return gestureUpdate(&g, mode, 0, 0, endX, endY, 1 + duration);
}

int main(void) {
    assert(sequence(ModeTap, .03, .5, .03, .5, .12) == ActionLeft);
    assert(sequence(ModeTap, .97, .5, .97, .5, .12) == ActionRight);
    assert(sequence(ModeTap, .5, .03, .5, .03, .12) == ActionAlmostMaximize);
    assert(sequence(ModeSwipe, .03, .5, .15, .5, .2) == ActionLeft);
    assert(sequence(ModeSwipe, .97, .5, .85, .5, .2) == ActionRight);
    assert(sequence(ModeSwipe, .5, .03, .5, .15, .2) == ActionAlmostMaximize);
    // Ordinary touches, corners, outward swipes and scrolling must do nothing.
    assert(sequence(ModeTap, .5, .5, .5, .5, .12) == ActionNone);
    assert(sequence(ModeTap, .02, .02, .02, .02, .12) == ActionNone);
    assert(sequence(ModeTap, .98, .98, .98, .98, .12) == ActionNone);
    assert(sequence(ModeSwipe, .03, .5, .01, .5, .2) == ActionNone);
    assert(sequence(ModeSwipe, .97, .5, .97, .7, .2) == ActionNone);
    assert(sequence(ModeSwipe, .5, .5, .97, .5, .2) == ActionNone);
    assert(sequence(ModeSwipe, .97, .5, .84, .7, .2) == ActionNone);
    assert(sequence(ModeSwipe, .97, .5, .95, .5, .2) == ActionNone);
    assert(sequence(ModeSwipe, .97, .5, .85, .5, 1) == ActionNone);
    assert(sequence(ModeTap, .97, .5, .97, .5, .5) == ActionNone);
    assert(sequence(ModeTap, .97, .5, .97, .5, .01) == ActionNone);
    assert(sequence(ModeTap, .97, .5, .85, .5, .12) == ActionNone);
    assert(sequence(ModeTap, NAN, .5, .97, .5, .12) == ActionNone);
    // A second finger cancels the whole sequence, even if it lifts first.
    Gesture g = {0};
    gestureUpdate(&g, ModeTap, 1, 1, .97, .5, 1);
    gestureUpdate(&g, ModeTap, 2, 1, .97, .5, 1.03);
    gestureUpdate(&g, ModeTap, 1, 1, .97, .5, 1.06);
    assert(gestureUpdate(&g, ModeTap, 0, 0, .97, .5, 1.12) == ActionNone);
    gestureUpdate(&g, ModeTap, 1, 2, .03, .5, 2);
    assert(gestureUpdate(&g, ModeTap, 0, 0, .03, .5, 2.12) == ActionLeft);
    // Never mistake a replacement contact for the original finger.
    gestureUpdate(&g, ModeTap, 1, 1, .97, .5, 3);
    gestureUpdate(&g, ModeTap, 1, 2, .97, .5, 3.05);
    assert(gestureUpdate(&g, ModeTap, 0, 0, .97, .5, 3.12) == ActionNone);
    // An excursion followed by a return is not a stationary tap.
    gestureUpdate(&g, ModeTap, 1, 1, .97, .5, 4);
    gestureUpdate(&g, ModeTap, 1, 1, .8, .5, 4.04);
    gestureUpdate(&g, ModeTap, 1, 1, .97, .5, 4.08);
    assert(gestureUpdate(&g, ModeTap, 0, 0, .97, .5, 4.12) == ActionNone);
    assert(gestureUpdate(&g, ModeTap, 0, 0, .97, .5, 4.2) == ActionNone);
    puts("Gesture tests passed");
}
