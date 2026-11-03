#ifndef GESTURE_H
#define GESTURE_H
#include <stdbool.h>

typedef enum { ActionNone, ActionLeft, ActionRight, ActionAlmostMaximize } EdgeAction;
typedef enum { ModeTap, ModeSwipe } GestureMode;
typedef enum {
    FeedbackNone, FeedbackRecognized, FeedbackOutsideEdge, FeedbackMultipleFingers,
    FeedbackInvalidPosition, FeedbackContactChanged, FeedbackTooBrief,
    FeedbackTooLong, FeedbackTapMoved, FeedbackSwipeShort, FeedbackWrongDirection,
    FeedbackSidewaysDrift, FeedbackWaitingForLift, FeedbackCursorCaptureCancelled
} GestureFeedback;
enum { EdgeWidthPercent = 7, EdgeCornerPercent = 15 };
extern const double GestureMinDuration, GestureTapMaxDuration, GestureSwipeMaxDuration;
extern const double GestureTapMaxDistance, GestureSwipeMinDistance, GestureSwipeMaxDrift;
typedef struct {
    bool tracking, blocked;
    int identifier;
    double startX, startY, started, maxDistance;
    EdgeAction edge;
    GestureFeedback feedback;
} Gesture;

EdgeAction gestureEdgeAt(double x, double y);
const char *gestureFeedbackText(GestureFeedback feedback);

// Coordinates are normalized, with (0, 0) at the trackpad's bottom left.
// A zero-contact frame ends the sequence; multiple contacts cancel until all lift.
// identifier must be the stable contact path, not the mutable raw id field.
EdgeAction gestureUpdate(Gesture *g, GestureMode mode, int count, int identifier,
                         double x, double y, double time);
#endif
