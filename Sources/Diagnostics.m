#import "Diagnostics.h"
#include <math.h>

@interface TrackpadView : NSView
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSNumber *> *> *touches;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<NSValue *> *> *trails;
@property(nonatomic, strong) NSMutableArray<NSString *> *events;
@property(nonatomic, copy) NSString *state;
@property(nonatomic, strong) NSValue *clickPoint;
@end

@implementation TrackpadView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _touches = @[];
        _trails = [NSMutableDictionary dictionary];
        _events = [NSMutableArray array];
        _state = @"Waiting for trackpad";
    }
    return self;
}
- (BOOL)isOpaque { return YES; }
- (void)text:(NSString *)text rect:(NSRect)rect size:(CGFloat)size color:(NSColor *)color {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    [text drawInRect:rect withAttributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:size],
        NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style }];
}
- (NSPoint)point:(NSPoint)normalized inPad:(NSRect)pad {
    return NSMakePoint(NSMinX(pad) + normalized.x * NSWidth(pad),
                       NSMinY(pad) + normalized.y * NSHeight(pad));
}
- (void)zone:(NSRect)rect color:(NSColor *)color {
    [[color colorWithAlphaComponent:0.2] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:8 yRadius:8] fill];
    [[color colorWithAlphaComponent:0.65] setStroke];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:8 yRadius:8] stroke];
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = self.bounds;
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(bounds);
    CGFloat width = NSWidth(bounds), height = NSHeight(bounds);
    [self text:@"Trackpad Diagnostics" rect:NSMakeRect(28, height - 48, width - 56, 28)
          size:23 color:NSColor.labelColor];
    [self text:self.state rect:NSMakeRect(28, height - 78, width - 56, 22)
          size:13 color:NSColor.secondaryLabelColor];
    NSString *live = self.touches.count ? [NSString stringWithFormat:@"%lu finger%@ touching", (unsigned long)self.touches.count,
        self.touches.count == 1 ? @"" : @"s"] : @"No fingers touching · last path stays visible";
    [self text:live rect:NSMakeRect(28, height - 104, width - 56, 20) size:12 color:NSColor.secondaryLabelColor];

    NSRect pad = NSMakeRect(28, 218, width - 56, height - 338);
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:pad xRadius:24 yRadius:24];
    NSGradient *surface = [[NSGradient alloc] initWithStartingColor:NSColor.controlBackgroundColor
        endingColor:NSColor.windowBackgroundColor];
    [surface drawInBezierPath:outline angle:90];
    [NSColor.separatorColor setStroke];
    outline.lineWidth = 2;
    [outline stroke];
    CGFloat edge = EdgeWidthPercent / 100.0, corner = EdgeCornerPercent / 100.0;
    [self zone:NSMakeRect(NSMinX(pad), NSMinY(pad) + corner * NSHeight(pad), edge * NSWidth(pad), (1 - 2 * corner) * NSHeight(pad)) color:NSColor.systemOrangeColor];
    [self zone:NSMakeRect(NSMaxX(pad) - edge * NSWidth(pad), NSMinY(pad) + corner * NSHeight(pad), edge * NSWidth(pad), (1 - 2 * corner) * NSHeight(pad)) color:NSColor.systemBlueColor];
    [self zone:NSMakeRect(NSMinX(pad) + corner * NSWidth(pad), NSMinY(pad), (1 - 2 * corner) * NSWidth(pad), edge * NSHeight(pad)) color:NSColor.systemGreenColor];
    [self text:@"Left half" rect:NSMakeRect(NSMinX(pad) + 16, NSMidY(pad), 110, 20) size:12 color:NSColor.secondaryLabelColor];
    [self text:@"Right half" rect:NSMakeRect(NSMaxX(pad) - 116, NSMidY(pad), 100, 20) size:12 color:NSColor.secondaryLabelColor];
    [self text:@"Almost maximize" rect:NSMakeRect(NSMidX(pad) - 58, NSMinY(pad) + 6, 140, 20) size:12 color:NSColor.secondaryLabelColor];
    [self text:@"Inactive corners · colored strips show the exact active zones"
        rect:NSMakeRect(NSMinX(pad) + 16, NSMaxY(pad) - 30, NSWidth(pad) - 32, 20) size:12 color:NSColor.tertiaryLabelColor];

    [NSGraphicsContext saveGraphicsState];
    [outline addClip];
    for (NSArray<NSValue *> *trail in self.trails.allValues) {
        NSBezierPath *path = [NSBezierPath bezierPath];
        for (NSUInteger i = 0; i < trail.count; i++) {
            NSPoint point = [self point:trail[i].pointValue inPad:pad];
            if (i == 0) [path moveToPoint:point]; else [path lineToPoint:point];
        }
        [[NSColor.systemTealColor colorWithAlphaComponent:0.45] setStroke];
        path.lineWidth = 2;
        [path stroke];
        if (trail.count) {
            NSPoint start = [self point:trail.firstObject.pointValue inPad:pad];
            [[NSColor.systemTealColor colorWithAlphaComponent:0.6] setStroke];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(start.x - 4, start.y - 4, 8, 8)] stroke];
        }
    }
    for (NSDictionary *touch in self.touches) {
        double x = [touch[@"x"] doubleValue], y = [touch[@"y"] doubleValue];
        if (!isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) continue;
        NSPoint point = [self point:NSMakePoint(x, y) inPad:pad];
        NSColor *color = gestureEdgeAt(x, y) == ActionNone ? NSColor.systemTealColor : NSColor.systemBlueColor;
        [[color colorWithAlphaComponent:0.15] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(point.x - 24, point.y - 24, 48, 48)] fill];
        [[color colorWithAlphaComponent:0.8] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(point.x - 10, point.y - 10, 20, 20)] fill];
        NSString *label = [NSString stringWithFormat:@"#%@  x %.1f%%  y %.1f%%", touch[@"id"], x * 100, y * 100];
        CGFloat labelX = fmin(fmax(point.x - 65, NSMinX(pad) + 8), NSMaxX(pad) - 190);
        CGFloat labelY = point.y > NSMaxY(pad) - 50 ? point.y - 36 : point.y + 24;
        [self text:label rect:NSMakeRect(labelX, labelY, 185, 20) size:11 color:NSColor.labelColor];
    }
    if (self.clickPoint) {
        NSPoint point = [self point:self.clickPoint.pointValue inPad:pad];
        [NSColor.systemPinkColor setStroke];
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(point.x - 18, point.y - 18, 36, 36)];
        ring.lineWidth = 3;
        [ring stroke];
    }
    [NSGraphicsContext restoreGraphicsState];
    [self text:@"Recent events" rect:NSMakeRect(28, 181, width - 56, 22) size:14 color:NSColor.labelColor];
    for (NSUInteger i = 0; i < self.events.count; i++) {
        [self text:self.events[i] rect:NSMakeRect(28, 155 - i * 22, width - 56, 21)
            size:11 color:i == 0 ? NSColor.labelColor : NSColor.secondaryLabelColor];
    }
    [self text:@"Coordinates start at bottom left. Pink ring = click near a recent touch; mouse source is unknown."
        rect:NSMakeRect(28, 12, width - 56, 22) size:11 color:NSColor.secondaryLabelColor];
}
@end

// A nonactivating panel leaves the real target app focused while you watch.
@interface DiagnosticPanel : NSPanel
@end
@implementation DiagnosticPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface Diagnostics () <NSWindowDelegate>
@property(nonatomic, strong) TrackpadView *trackpadView;
@property(nonatomic, strong) id globalClickMonitor;
@property(nonatomic, strong) id localClickMonitor;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSNumber *> *> *lastTouches;
@property(nonatomic) NSTimeInterval lastTouchTime;
@end

@implementation Diagnostics
- (instancetype)init {
    DiagnosticPanel *panel = [[DiagnosticPanel alloc] initWithContentRect:NSMakeRect(0, 0, 800, 660)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:panel])) {
        _observeOnly = YES;
        panel.title = @"Trackpad Diagnostics";
        panel.minSize = NSMakeSize(760, 640);
        panel.floatingPanel = YES;
        panel.hidesOnDeactivate = NO;
        panel.releasedWhenClosed = NO;
        panel.delegate = self;
        _trackpadView = [[TrackpadView alloc] initWithFrame:panel.contentView.bounds];
        _trackpadView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        panel.contentView = _trackpadView;
        [panel center];
        __weak Diagnostics *weakSelf = self;
        _globalClickMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^(NSEvent *event) {
            (void)event;
            [weakSelf recordClick];
        }];
        _localClickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *event) {
            [weakSelf recordClick];
            return event;
        }];
    }
    return self;
}
- (void)dealloc {
    if (_globalClickMonitor) [NSEvent removeMonitor:_globalClickMonitor];
    if (_localClickMonitor) [NSEvent removeMonitor:_localClickMonitor];
}
- (void)show {
    if (!self.window.visible) {
        self.trackpadView.touches = @[];
        [self.trackpadView.trails removeAllObjects];
        self.trackpadView.clickPoint = nil;
        self.lastTouches = @[];
        self.trackpadView.needsDisplay = YES;
    }
    [self.window orderFrontRegardless];
}
- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    if (self.onClose) self.onClose();
}
- (void)record:(NSString *)message {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"%@  %@", [formatter stringFromDate:NSDate.date], message];
    [self.trackpadView.events insertObject:line atIndex:0];
    if (self.trackpadView.events.count > 6) [self.trackpadView.events removeLastObject];
    self.trackpadView.toolTip = [self.trackpadView.events componentsJoinedByString:@"\n"];
    self.trackpadView.needsDisplay = YES;
}
- (void)updateTouches:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)touches {
    if (!self.window.visible) return;
    if (touches.count && !self.trackpadView.touches.count) {
        [self.trackpadView.trails removeAllObjects];
        self.trackpadView.clickPoint = nil;
    }
    for (NSDictionary *touch in touches) {
        NSNumber *identifier = touch[@"id"];
        double x = [touch[@"x"] doubleValue], y = [touch[@"y"] doubleValue];
        if (!isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) continue;
        NSMutableArray *trail = self.trackpadView.trails[identifier];
        if (!trail) {
            // Bound storage even if a driver continually changes contact IDs.
            if (self.trackpadView.trails.count >= 16) [self.trackpadView.trails removeAllObjects];
            trail = [NSMutableArray array];
            self.trackpadView.trails[identifier] = trail;
        }
        [trail addObject:[NSValue valueWithPoint:NSMakePoint(x, y)]];
        if (trail.count > 100) [trail removeObjectAtIndex:0];
    }
    self.trackpadView.touches = touches;
    if (touches.count) {
        self.lastTouches = touches;
        self.lastTouchTime = NSProcessInfo.processInfo.systemUptime;
    }
    self.trackpadView.needsDisplay = YES;
}
- (void)recordClick {
    if (!self.window.visible || !self.lastTouches.count ||
        NSProcessInfo.processInfo.systemUptime - self.lastTouchTime > 0.15) return;
    NSDictionary *touch = self.lastTouches.firstObject;
    double x = [touch[@"x"] doubleValue], y = [touch[@"y"] doubleValue];
    if (!isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) return;
    self.trackpadView.clickPoint = [NSValue valueWithPoint:NSMakePoint(x, y)];
    [self record:[NSString stringWithFormat:@"Mouse-down near touch # %@ at %.1f%%, %.1f%% (approximate)", touch[@"id"], x * 100, y * 100]];
}
- (void)setMode:(GestureMode)mode enabled:(BOOL)enabled available:(BOOL)available {
    self.trackpadView.state = [NSString stringWithFormat:@"%@ · %@ · %@",
        !available ? @"Trackpad unavailable — use Reconnect Trackpad" : !enabled ? @"Paused (raw touches still shown)" : @"Trackpad connected",
        mode == ModeTap ? @"Tap" : @"Inward swipe",
        self.observeOnly ? @"Observe only while this window is open" : @"Window actions enabled"];
    self.trackpadView.needsDisplay = YES;
}
@end
