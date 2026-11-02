#ifndef GESTURE_H
#define GESTURE_H
#include <stdbool.h>

typedef enum { ActionNone, ActionLeft, ActionRight, ActionAlmostMaximize } EdgeAction;
typedef enum { ModeTap, ModeSwipe } GestureMode;
typedef struct {
    bool tracking, blocked;
    int identifier;
    double startX, startY, started, maxDistance;
    EdgeAction edge;
} Gesture;

// Coordinates are normalized, with (0, 0) at the trackpad's bottom left.
// A zero-contact frame ends the sequence; multiple contacts cancel until all lift.
EdgeAction gestureUpdate(Gesture *g, GestureMode mode, int count, int identifier,
                         double x, double y, double time);
#endif
