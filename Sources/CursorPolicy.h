#ifndef CURSOR_POLICY_H
#define CURSOR_POLICY_H
#include "Gesture.h"

typedef enum { CursorMove, CursorDown, CursorUp } CursorInput;
typedef struct {
    bool enabled, tracking, blocked, locked;
    int path;
    double x, y, started, lastFrame, moveTailUntil, clickTailUntil;
    EdgeAction edge;
    GestureFeedback cancellation;
    unsigned suppressedButtons;
} CursorPolicy;

void cursorPolicyConfigure(CursorPolicy *p, bool enabled, double now);
void cursorPolicyFrame(CursorPolicy *p, int count, int path, double x, double y,
                       bool buttonHeld, double now);
void cursorPolicyTick(CursorPolicy *p, double now);
// True means delete this pointer event. Suppressed downs retain their matching ups.
bool cursorPolicySuppress(CursorPolicy *p, CursorInput input, unsigned button, double now);
#endif
