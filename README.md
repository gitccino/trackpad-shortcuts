<img src="assets/icon.svg" width="64" height="64" alt="">

# trackpad-shortcuts

A minimal native macOS menu bar app for arranging the focused window using
single-finger trackpad-edge gestures. No third-party dependencies, Dock icon,
account, or background service.

- Left edge → left half of the window's current display.
- Right edge → right half.
- Bottom edge → almost maximize, with a 12-point margin inside the usable screen.

The usable screen excludes the menu bar and Dock. Almost maximize keeps the
window in the current desktop rather than entering macOS fullscreen.

## Build and run

Requires macOS 12 or later, a Mac trackpad, and Xcode Command Line Tools
(`xcode-select --install`). Both Apple Silicon and Intel are intended targets;
the build script builds for the Mac running it.

```sh
make test
make build
ditto "build/Trackpad Shortcuts.app" "/Applications/Trackpad Shortcuts.app"
open "/Applications/Trackpad Shortcuts.app"
```

Open the menu bar icon and select **Grant Accessibility Access…**. Enable the
app in System Settings → Privacy & Security → Accessibility. Relaunch if macOS
doesn't recognize the permission immediately. Keep the app in a stable location;
rebuilding the ad hoc signed app may require granting access again.

## Try it over several days

The default is **Tap**. Touch and lift one finger in the middle portion of the
left, right, or bottom edge, without clicking. The outer 7% is active; corners
are deliberately inactive. The tap must last 35–250 ms and move no more than
2.5% of the trackpad dimension in normalized coordinates.

Choose **Gesture: Swipe inward** from the menu to try the alternative. Start at
the same edge, travel at least 8% inward, then lift within 700 ms. Sideways drift
must stay within 5%. Actions happen on lift. The app remembers your gesture mode.
Multiple fingers cancel a gesture until every finger lifts.

Use **Pause** whenever needed. **Reconnect Trackpad** retries detection after a
device change; the app also reconnects after sleep. This MVP uses the system's
default trackpad, one device at a time. Test with the built-in trackpad first.

Useful observations during your trial: accidental activations, missed gestures,
whether the bottom edge is comfortable, and whether the 12-point margin feels
right. Keep the mode fixed for a session so the observations are easier to judge.

## Live trackpad diagnostics

Choose **Open Trackpad Diagnostics…** from the menu bar icon. The floating
window shows a trackpad with the exact active strips, a dot for every touching
finger, finger IDs, normalized coordinates, and the last movement paths. The
small hollow circle marks the start of a path. Corners remain inactive.

The window does not take keyboard focus away from your target app. While it is
open, **Observe Only in Diagnostics** is enabled by default: gestures are still
recognized and explained, but window actions are suppressed. Turn that option
off to test actual placement while watching the view. Closing the diagnostic
window resumes normal actions, subject to the app's Pause setting. Changing this
option or opening/closing the window cancels the gesture currently in progress.

Recent events show recognition or the actual rejection reason from the same
recognizer used for window actions: inactive starting position, multiple fingers,
short/long touch, excessive movement, wrong direction, short swipe, or sideways
drift. Completed gestures include duration and start/end coordinates. An action
that was recognized can still fail at the Accessibility stage; that result is
shown separately when window actions are enabled.

Raw finger positions continue to display while **Pause** is enabled, although
gesture recognition is paused. If the trackpad cannot start, the window reports
that instead. The recent event list is limited to six entries, and paths are
bounded in memory. While this window is open, a complete test-session log is
also written locally as described below. Nothing is transmitted.

A pink ring marks a mouse-down event within 150 ms of a sampled touch, near the
most recent finger position. This is approximate: macOS mouse events do not
identify which touch/device caused the click. Tap-to-click can arrive after lift,
and an external mouse click can also correlate with a finger resting on the
trackpad. Click monitoring does not consume or block events. Accessibility access
may be required for clicks outside the app to appear.

To investigate a miss, first check whether the finger dot appears. Then check
whether its starting point is in the colored strip, and read the last rejection
reason. A recognized gesture followed by an action error points to permissions
or window constraints rather than edge detection.

### Record real test cases

Opening Diagnostics automatically creates a new `Session-….jsonl` file in:

```text
~/Library/Logs/Trackpad Shortcuts/
```

The recording line above the trackpad shows the filename and current test label.
Use **Show Diagnostic Logs in Finder** in the menu to reveal the latest file.
Closing Diagnostics or quitting the app ends the session and flushes all queued
records. Reopening starts a separate file. No session data is deliberately
sampled or capped; keep an eye on disk space during long tests. A write failure
is shown in red, so a failed recording is not mistaken for missing touches.

For a useful trial:

1. Open Diagnostics and keep **Observe Only** enabled to test recognition without
   moving windows. Keep **Pause** off so recognition results are recorded.
2. Choose **Mark Test Position → Left edge**, then touch several positions along
   that edge repeatedly. Try natural taps without aiming for the displayed strip.
3. Mark and repeat for **Right edge**, **Bottom edge**, **Center**, and **Corners**.
   Each marker labels subsequent records until changed, including missed attempts.
4. If comparing tap and swipe, switch modes and repeat the same batches. Mode
   changes are logged, so separate files are optional.
5. Close Diagnostics to finish, reveal the log in Finder, and share the `.jsonl`
   file for analysis. Note any intended touches that produced no dot or log event;
   software cannot reconstruct a physical contact the trackpad never reported.

The JSON Lines format contains one JSON object per line, in sequence order:

- `session_start`: build revision, macOS version, algorithm identifier, exact
  thresholds, starting settings, and executable path.
- `touch_frame`: native frame number/time, callback uptime, stream generation,
  all raw contact states (including hover/lift states), finger IDs, coordinates,
  velocities, contact shape and `z_total`, plus the recognizer's touching count.
  `z_total` is the framework's raw field, not calibrated force.
- `gesture_result`: action/rejection code and reason, duration, start/end points,
  peak movement, and cancellation state. Action codes: 0 none, 1 left, 2 right,
  3 almost maximize. The accompanying reason explains the feedback code.
- `action_result`: attempted or observe-only-suppressed action, message, and
  Accessibility trust status. This separates recognition from window-control errors.
- `settings`, `recognizer_reset`, `stream_start`, `stream_stop`, `test_marker`,
  `accessibility_status`, `mouse_down`, and the UI's `message` events.
- `session_end`: normal stop reason. Its absence can indicate an interrupted run.

Every entry includes `schema_version`, a monotonically increasing `sequence`,
wall-clock Unix time, process uptime, and a `data` object. Marked records carry
`test_label`. Coordinates are normalized with the origin at bottom left. Device
timestamps remain in their native clock; `callback_uptime` and entry `uptime`
help identify delivery delays. Invalid nonfinite numbers are preserved as
`"NaN"`, `"Infinity"`, or `"-Infinity"` rather than dropping a frame.

Writes run on a background serial queue. Each record is written immediately to
the OS without application-level buffering; normal session close also calls
`fsync`. An interrupted write can leave an incomplete final line. Click events
remain approximate correlations and currently cover left mouse-down events.
Logs do not contain typed text, window titles, or document contents. Files are
retained until you delete them; this recording feature is intended for testing.

## Current limits

- Absolute touch coordinates come from Apple's undocumented
  `MultitouchSupport.framework`. Compatibility is experimental and may change
  with macOS or hardware. If the interface can't load, the menu reports that
  the trackpad is unavailable instead of terminating the app.
- Normal pointer movement, clicks, and system gestures are not suppressed.
  Tap-to-click may also click beneath the pointer or change focus. The action
  targets the focused window when the gesture completes. Try swipe mode if tap
  mode causes unwanted clicks; input suppression is outside this MVP.
- Apps can enforce minimum window sizes or refuse Accessibility changes. The
  menu reports rejected or constrained placement. macOS fullscreen windows are
  left alone; exit fullscreen before arranging them.
- Local ad hoc signing only; no App Store packaging, notarization, auto-update,
  launch at login, custom bindings, or cursor locking.

## Validation

`make test` runs portable C tests for the three mappings, inward direction,
duration and movement limits, corners, ordinary touches, multiple fingers,
contact replacement, and one action per gesture. The macOS CI job also compiles
and packages the app, and runs session-log tests for ordered frame retention,
nonfinite sensor values, stopping/reopening sessions, and directory failures.
CI cannot validate physical trackpad input or permissions.

This initial implementation was written in a Linux workspace. Gesture tests can
run there; the AppKit build, private framework ABI, device behavior, Accessibility
permission flow, and multi-monitor placement still require validation on a Mac.

On a Mac, try each action in a resizable app, both gesture modes, two-finger
scrolling, Pause/Resume, permission denied/granted, sleep/wake, and a secondary
display positioned above or left of the primary one. Confirm ordinary touches
leave windows alone and constrained-size apps fail gracefully.

## Technical references

- [Apple Accessibility attribute writes](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue)
- [Apple Accessibility screen coordinates](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute)
- [Community documentation of the MultitouchSupport ABI](https://github.com/mkalten/twongseng/blob/master/multitouch.h)
- [Trackpad interface background from RWTH Aachen](https://hci.rwth-aachen.de/guide-trackpad)

Created in [T3 Code](https://t3.codes).
