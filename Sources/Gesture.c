#include "Gesture.h"
#include <math.h>

const double GestureMinDuration = 0.035, GestureTapMaxDuration = 0.25, GestureSwipeMaxDuration = 0.7;
const double GestureTapMaxDistance = 0.025, GestureSwipeMinDistance = 0.08, GestureSwipeMaxDrift = 0.05;

EdgeAction gestureEdgeAt(double x, double y) {
    if (!isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1)
        return ActionNone;
    // Leave corners inactive so every starting point has one clear meaning.
    const double width = EdgeWidthPercent / 100.0, corner = EdgeCornerPercent / 100.0;
    if (y >= corner && y <= 1 - corner) {
        if (x <= width) return ActionLeft;
        if (x >= 1 - width) return ActionRight;
    }
    if (y <= width && x >= corner && x <= 1 - corner) return ActionAlmostMaximize;
    return ActionNone;
}

const char *gestureFeedbackText(GestureFeedback feedback) {
    switch (feedback) {
        case FeedbackNone: return "Waiting for a gesture";
        case FeedbackRecognized: return "Recognized";
        case FeedbackOutsideEdge: return "Started outside an active edge (corners are inactive)";
        case FeedbackMultipleFingers: return "Multiple fingers detected; lift all fingers and retry";
        case FeedbackInvalidPosition: return "Invalid touch coordinates received";
        case FeedbackContactChanged: return "Contact path changed before lift";
        case FeedbackTooBrief: return "Touch shorter than 35 ms";
        case FeedbackTooLong: return "Touch held too long for the selected gesture mode";
        case FeedbackTapMoved: return "Tap moved more than 2.5%";
        case FeedbackSwipeShort: return "Inward swipe shorter than 8%";
        case FeedbackWrongDirection: return "Swipe traveled away from the center";
        case FeedbackSidewaysDrift: return "Swipe drifted sideways more than 5%";
        case FeedbackWaitingForLift: return "Mode changed or resumed; lift all fingers first";
    }
    return "Unknown gesture result";
}

static GestureFeedback finish(const Gesture *g, GestureMode mode, double x, double y, double time) {
    if (g->blocked) return g->feedback;
    if (g->edge == ActionNone) return FeedbackOutsideEdge;
    double duration = time - g->started;
    if (duration < GestureMinDuration) return FeedbackTooBrief;
    if (duration > (mode == ModeTap ? GestureTapMaxDuration : GestureSwipeMaxDuration)) return FeedbackTooLong;
    if (mode == ModeTap)
        return g->maxDistance <= GestureTapMaxDistance ? FeedbackRecognized : FeedbackTapMoved;
    double dx = x - g->startX, dy = y - g->startY;
    double inward = g->edge == ActionLeft ? dx : g->edge == ActionRight ? -dx : dy;
    double sideways = g->edge == ActionAlmostMaximize ? fabs(dx) : fabs(dy);
    if (inward < 0) return FeedbackWrongDirection;
    if (sideways > GestureSwipeMaxDrift) return FeedbackSidewaysDrift;
    return inward >= GestureSwipeMinDistance ? FeedbackRecognized : FeedbackSwipeShort;
}

EdgeAction gestureUpdate(Gesture *g, GestureMode mode, int count, int identifier,
                         double x, double y, double time) {
    if (count == 0) {
        GestureFeedback feedback = g->tracking || g->blocked ? finish(g, mode, x, y, time) : FeedbackNone;
        EdgeAction result = feedback == FeedbackRecognized ? g->edge : ActionNone;
        *g = (Gesture){ .feedback = feedback };
        return result;
    }
    if (count != 1 || !isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) {
        g->blocked = true;
        g->feedback = count != 1 ? FeedbackMultipleFingers : FeedbackInvalidPosition;
        return ActionNone;
    }
    if (g->blocked) return ActionNone;
    if (!g->tracking) {
        g->tracking = true;
        g->identifier = identifier;
        g->startX = x;
        g->startY = y;
        g->started = time;
        g->edge = gestureEdgeAt(x, y);
        g->feedback = FeedbackNone;
    } else if (g->identifier != identifier) {
        g->blocked = true;
        g->feedback = FeedbackContactChanged;
    }
    double distance = hypot(x - g->startX, y - g->startY);
    if (distance > g->maxDistance) g->maxDistance = distance;
    return ActionNone;
}
