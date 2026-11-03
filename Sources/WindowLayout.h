#ifndef WINDOW_LAYOUT_H
#define WINDOW_LAYOUT_H
#include <CoreGraphics/CGGeometry.h>
#include <math.h>
#include "Gesture.h"

enum { WindowMatchTolerance = 2 };

static inline CGRect almostMaximizedRect(CGRect usableScreen) {
    return CGRectInset(usableScreen, usableScreen.size.width * 0.05, usableScreen.size.height * 0.05);
}

static inline bool validWindowRect(CGRect rect) {
    return isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
        isfinite(rect.size.width) && isfinite(rect.size.height) &&
        rect.size.width > 0 && rect.size.height > 0;
}

static inline bool windowFramesMatch(CGRect current, CGRect target) {
    return validWindowRect(current) && validWindowRect(target) &&
        fabs(current.origin.x - target.origin.x) <= WindowMatchTolerance &&
        fabs(current.origin.y - target.origin.y) <= WindowMatchTolerance &&
        fabs(current.size.width - target.size.width) <= WindowMatchTolerance &&
        fabs(current.size.height - target.size.height) <= WindowMatchTolerance;
}

static inline bool shouldHideFocusedApp(EdgeAction action, CGRect current, CGRect target) {
    return action == ActionAlmostMaximize && windowFramesMatch(current, target);
}
#endif
