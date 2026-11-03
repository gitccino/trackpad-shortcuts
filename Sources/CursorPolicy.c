#include "CursorPolicy.h"
#include <math.h>

static void releaseLock(CursorPolicy *p, double now) {
    if (p->locked) {
        // Absorb delayed movement and tap-to-click events from the ending swipe.
        p->moveTailUntil = now + 0.035;
        p->clickTailUntil = now + 0.15;
    }
    p->locked = false;
}

static void cancel(CursorPolicy *p, GestureFeedback reason, double now) {
    releaseLock(p, now);
    p->blocked = true;
    p->cancellation = reason;
}

void cursorPolicyConfigure(CursorPolicy *p, bool enabled, double now) {
    bool wasTracking = p->tracking || p->blocked;
    unsigned buttons = p->suppressedButtons;
    *p = (CursorPolicy){ .enabled = enabled, .blocked = wasTracking,
        .cancellation = wasTracking ? FeedbackWaitingForLift : FeedbackNone,
        .lastFrame = now, .suppressedButtons = buttons };
}

void cursorPolicyTick(CursorPolicy *p, double now) {
    if (!p->locked) return;
    if (now - p->started > GestureSwipeMaxDuration)
        cancel(p, FeedbackTooLong, now);
    else if (now - p->lastFrame > 0.25)
        cancel(p, FeedbackCursorCaptureCancelled, now);
}

void cursorPolicyFrame(CursorPolicy *p, int count, int path, double x, double y,
                       bool buttonHeld, double now) {
    cursorPolicyTick(p, now);
    p->lastFrame = now;
    if (count == 0) {
        releaseLock(p, now);
        p->tracking = false;
        p->blocked = false;
        p->cancellation = FeedbackNone;
        return;
    }
    if (!p->enabled) {
        // Remember an existing contact so enabling capture cannot grab it mid-touch.
        p->tracking = true;
        return;
    }
    if (p->blocked) return;
    if (count != 1) { cancel(p, FeedbackMultipleFingers, now); return; }
    if (!isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) {
        cancel(p, FeedbackInvalidPosition, now); return;
    }
    if (!p->tracking) {
        // A fresh ordinary touch ends the short post-swipe suppression tail.
        p->moveTailUntil = p->clickTailUntil = 0;
        p->tracking = true;
        p->path = path; p->x = x; p->y = y; p->started = now;
        p->edge = gestureEdgeAt(x, y);
        // Never interfere with a drag whose button-down was already delivered.
        if (p->edge != ActionNone && buttonHeld) {
            cancel(p, FeedbackCursorCaptureCancelled, now);
            return;
        }
        p->locked = p->edge != ActionNone;
        return;
    }
    if (path != p->path) { cancel(p, FeedbackContactChanged, now); return; }
    if (!p->locked) return;
    double dx = x - p->x, dy = y - p->y;
    double inward = p->edge == ActionLeft ? dx : p->edge == ActionRight ? -dx : dy;
    double sideways = p->edge == ActionAlmostMaximize ? fabs(dx) : fabs(dy);
    if (inward < -GestureTapMaxDistance) cancel(p, FeedbackWrongDirection, now);
    else if (sideways > GestureSwipeMaxDrift) cancel(p, FeedbackSidewaysDrift, now);
}

bool cursorPolicySuppress(CursorPolicy *p, CursorInput input, unsigned button, double now) {
    cursorPolicyTick(p, now);
    unsigned bit = button < 32 ? 1u << button : 0;
    if (input == CursorUp && (p->suppressedButtons & bit)) {
        p->suppressedButtons &= ~bit;
        return true;
    }
    if (input == CursorMove) return p->locked || now < p->moveTailUntil;
    if (input == CursorDown && (p->suppressedButtons & bit)) return true;
    // Do not swallow an up unless this filter swallowed its down.
    if (input == CursorDown && (p->locked || now < p->clickTailUntil)) {
        if (!bit) return false;
        p->suppressedButtons |= bit;
        return true;
    }
    return false;
}
