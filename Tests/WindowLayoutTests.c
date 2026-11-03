#include "../Sources/WindowLayout.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    CGRect usable = CGRectMake(0, 24, 1440, 876);
    CGRect target = almostMaximizedRect(usable);
    assert(fabs(target.origin.x - 72) < 0.0001);
    assert(fabs(target.origin.y - 67.8) < 0.0001);
    assert(fabs(target.size.width - 1296) < 0.0001);
    assert(fabs(target.size.height - 788.4) < 0.0001);
    assert(shouldHideFocusedApp(ActionAlmostMaximize, target, target));
    assert(!shouldHideFocusedApp(ActionLeft, target, target));
    assert(!shouldHideFocusedApp(ActionRight, target, target));
    assert(!shouldHideFocusedApp(ActionNone, target, target));
    assert(!shouldHideFocusedApp(ActionAlmostMaximize, usable, target));
    assert(!shouldHideFocusedApp(ActionAlmostMaximize, CGRectMake(0, 24, 720, 876), target));
    assert(!shouldHideFocusedApp(ActionAlmostMaximize, CGRectMake(720, 24, 720, 876), target));

    // Accept normal pixel/point rounding, including fractional display geometry.
    CGRect rounded = CGRectMake(round(target.origin.x), round(target.origin.y), round(target.size.width), round(target.size.height));
    assert(shouldHideFocusedApp(ActionAlmostMaximize, rounded, target));
    CGRect current = target;
    current.origin.x += 2;
    current.origin.y -= 2;
    current.size.width += 2;
    current.size.height -= 2;
    assert(shouldHideFocusedApp(ActionAlmostMaximize, current, target));
    current.origin.x += 0.01;
    assert(!shouldHideFocusedApp(ActionAlmostMaximize, current, target));

    // Every frame component matters: moved or constrained windows must resize.
    for (int component = 0; component < 4; component++) {
        current = target;
        switch (component) {
            case 0: current.origin.x += 3; break;
            case 1: current.origin.y += 3; break;
            case 2: current.size.width += 3; break;
            case 3: current.size.height += 3; break;
        }
        assert(!shouldHideFocusedApp(ActionAlmostMaximize, current, target));
    }
    current = target;
    current.size.width += 100; // App-enforced minimum width.
    assert(!shouldHideFocusedApp(ActionAlmostMaximize, current, target));

    CGRect secondDisplay = CGRectMake(-1920, -1080, 1920, 1056);
    CGRect secondTarget = almostMaximizedRect(secondDisplay);
    assert(shouldHideFocusedApp(ActionAlmostMaximize, secondTarget, secondTarget));
    assert(!shouldHideFocusedApp(ActionAlmostMaximize, target, secondTarget));
    assert(!shouldHideFocusedApp(ActionAlmostMaximize, CGRectZero, CGRectZero));
    assert(!shouldHideFocusedApp(ActionAlmostMaximize, CGRectMake(NAN, 0, 100, 100), target));
    assert(!shouldHideFocusedApp(ActionAlmostMaximize, target, CGRectMake(0, 0, INFINITY, 100)));
    puts("Window layout toggle tests passed");
}
