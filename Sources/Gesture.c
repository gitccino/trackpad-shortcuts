#include "Gesture.h"
#include <math.h>

static EdgeAction edgeAt(double x, double y) {
    // Leave corners inactive so every starting point has one clear meaning.
    if (y >= 0.15 && y <= 0.85) {
        if (x <= 0.07) return ActionLeft;
        if (x >= 0.93) return ActionRight;
    }
    if (y <= 0.07 && x >= 0.15 && x <= 0.85) return ActionAlmostMaximize;
    return ActionNone;
}

EdgeAction gestureUpdate(Gesture *g, GestureMode mode, int count, int identifier,
                         double x, double y, double time) {
    if (count == 0) {
        EdgeAction result = ActionNone;
        double duration = time - g->started;
        if (g->tracking && !g->blocked && duration >= 0.035) {
            if (mode == ModeTap && duration <= 0.25 && g->maxDistance <= 0.025)
                result = g->edge;
            if (mode == ModeSwipe && duration <= 0.7) {
                double dx = g->startX - x, dy = y - g->startY;
                if ((g->edge == ActionLeft && -dx >= 0.08 && fabs(dy) <= 0.05) ||
                    (g->edge == ActionRight && dx >= 0.08 && fabs(dy) <= 0.05) ||
                    (g->edge == ActionAlmostMaximize && dy >= 0.08 && fabs(dx) <= 0.05))
                    result = g->edge;
            }
        }
        *g = (Gesture){0};
        return result;
    }
    if (count != 1 || !isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) {
        g->blocked = true;
        return ActionNone;
    }
    if (g->blocked) return ActionNone;
    if (!g->tracking) {
        g->tracking = true;
        g->identifier = identifier;
        g->startX = x;
        g->startY = y;
        g->started = time;
        g->edge = edgeAt(x, y);
    } else if (g->identifier != identifier) {
        g->blocked = true;
    }
    double distance = hypot(x - g->startX, y - g->startY);
    if (distance > g->maxDistance) g->maxDistance = distance;
    return ActionNone;
}
