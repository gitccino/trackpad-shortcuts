#ifndef CURSOR_EVENT_FILTER_H
#define CURSOR_EVENT_FILTER_H
#include <ApplicationServices/ApplicationServices.h>
#include "CursorPolicy.h"

static inline bool cursorInputForEvent(CGEventType type, CursorInput *input) {
    switch (type) {
        case kCGEventMouseMoved:
        case kCGEventLeftMouseDragged:
        case kCGEventRightMouseDragged:
        case kCGEventOtherMouseDragged: *input = CursorMove; return true;
        case kCGEventLeftMouseDown:
        case kCGEventRightMouseDown:
        case kCGEventOtherMouseDown: *input = CursorDown; return true;
        case kCGEventLeftMouseUp:
        case kCGEventRightMouseUp:
        case kCGEventOtherMouseUp: *input = CursorUp; return true;
        default: return false;
    }
}

static inline CGEventRef filterCursorEvent(CursorPolicy *policy, CGEventType type, CGEventRef event, double now) {
    CursorInput input;
    if (!event || !cursorInputForEvent(type, &input)) return event;
    unsigned button = (unsigned)CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
    return cursorPolicySuppress(policy, input, button, now) ? NULL : event;
}
#endif
