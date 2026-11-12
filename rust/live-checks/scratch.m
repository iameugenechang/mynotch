// Scratch text field that observes its own key status while real CGEvents drive
// the probe. THIS MOVES THE POINTER, CLICKS AND TYPES. Ops are argv; state is
// printed after each. Keys are only sent when the scratch field or the probe's
// editor is known to hold focus.
#import <AppKit/AppKit.h>
static const char *outDir(void) { return getenv("OUT") ?: "/tmp/anotchup-live-checks"; }
static NSWindow *win; static NSTextField *field; static int resigns; static NSString *logPath;
static NSDictionary *probe(BOOL *onscreen) {
    NSArray *on = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    for (NSDictionary *w in on) if ([w[(id)kCGWindowOwnerName] isEqual:@"anotchup-gates"]) { if (onscreen) *onscreen = YES; return w; }
    if (onscreen) *onscreen = NO;
    NSArray *all = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID));
    for (NSDictionary *w in all) if ([w[(id)kCGWindowOwnerName] isEqual:@"anotchup-gates"]) return w;
    return nil;
}
static CGRect pbounds(NSDictionary *w) { CGRect b = CGRectZero; if (w) CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds], &b); return b; }
// Synthetic modifier flags can stay latched in the session after the events that
// carried them. A latched Control turns every later click into a context-menu click.
static void releaseModifiers(void) {
    CGKeyCode mods[] = {59, 62, 63, 56, 60, 58, 61, 55, 54};
    for (int i = 0; i < 9; i++) { CGEventRef u = CGEventCreateKeyboardEvent(NULL, mods[i], false); CGEventSetFlags(u, 0); CGEventPost(kCGHIDEventTap, u); CFRelease(u); usleep(15000); }
    CGEventRef f = CGEventCreate(NULL); CGEventSetType(f, kCGEventFlagsChanged); CGEventSetFlags(f, 0); CGEventPost(kCGHIDEventTap, f); CFRelease(f); usleep(100000);
}
static BOOL modifiersHeld(void) {
    return (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & (kCGEventFlagMaskControl | kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate | kCGEventFlagMaskShift)) != 0;
}
static void post(CGEventType t, CGPoint p) { CGEventRef e = CGEventCreateMouseEvent(NULL, t, p, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e); }
static void spin(double s) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:s];
    for (;;) { NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:end inMode:NSDefaultRunLoopMode dequeue:YES]; if (!e) break; [NSApp sendEvent:e]; }
}
static void click(CGPoint p) { post(kCGEventMouseMoved, p); spin(0.15); post(kCGEventLeftMouseDown, p); usleep(60000); post(kCGEventLeftMouseUp, p); }
static CGPoint fieldPoint(void) {
    NSRect r = [win convertRectToScreen:[field convertRect:field.bounds toView:nil]];
    return CGPointMake(NSMidX(r), NSScreen.screens[0].frame.size.height - NSMidY(r));
}
static NSString *logText(void) { return [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil] ?: @""; }
static BOOL probeEditing(void) {
    NSString *last = nil;
    for (NSString *l in [logText() componentsSeparatedByString:@"\n"]) if ([l hasPrefix:@"[edit]"]) last = l;
    return [last hasPrefix:@"[edit] on"];
}
static BOOL scratchKey(void) { return win.isKeyWindow && NSApp.isActive; }
static void state(NSString *op, NSString *note) {
    BOOL on = NO; NSDictionary *w = probe(&on); CGRect b = pbounds(w);
    NSArray *lines = [logText() componentsSeparatedByString:@"\n"]; NSString *last = lines.count > 1 ? lines[lines.count - 2] : @"";
    printf("%-16s key=%d active=%d editor=%d resigns=%d field='%s' space=%d front='%s' probe=%s(%.0f,%.0f,%.0f,%.0f) log='%s'%s\n", op.UTF8String,
        win.isKeyWindow, NSApp.isActive, win.firstResponder == field.currentEditor, resigns, field.stringValue.UTF8String, win.isOnActiveSpace,
        NSWorkspace.sharedWorkspace.frontmostApplication.localizedName.UTF8String ?: "?", w ? (on ? "on" : "OFF") : "GONE", b.origin.x, b.origin.y, b.size.width, b.size.height,
        last.UTF8String, note.length ? [@" | " stringByAppendingString:note].UTF8String : "");
}
int main(int argc, const char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        logPath = [NSString stringWithUTF8String:getenv("PROBE_LOG") ?: "/tmp/anotchup-live-checks/probe.log"];
        NSRunningApplication *prior = NSWorkspace.sharedWorkspace.frontmostApplication;
        CGEventRef e0 = CGEventCreate(NULL); CGPoint original = CGEventGetLocation(e0); CFRelease(e0);
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular]; [app finishLaunching];
        win = [[NSWindow alloc] initWithContentRect:NSMakeRect(120, 160, 360, 90) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        win.title = @"anotchup focus scratch"; win.releasedWhenClosed = NO; win.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
        field = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 30, 320, 24)]; [win.contentView addSubview:field];
        [win makeKeyAndOrderFront:nil]; [app activateIgnoringOtherApps:YES];
        [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidResignKeyNotification object:win queue:nil usingBlock:^(NSNotification *n) { (void)n; resigns++; }];
        if (modifiersHeld()) { printf("refusing to run: a modifier key is held or latched\n"); return 3; }
        spin(0.8); state(@"start", @"");
        BOOL full = NO;
        for (int i = 1; i < argc; i++) {
            NSString *op = [NSString stringWithUTF8String:argv[i]]; NSArray *a = [op componentsSeparatedByString:@":"]; NSString *note = @"";
            NSString *k = a[0]; CGRect b = pbounds(probe(NULL));
            if ([k isEqual:@"sclick"]) { click(fieldPoint()); spin(0.7); }
            else if ([k isEqual:@"pclick"]) { resigns = 0; click(CGPointMake(b.origin.x + [a[1] doubleValue], b.origin.y + [a[2] doubleValue])); spin(0.9); }
            else if ([k isEqual:@"pmove"]) { post(kCGEventMouseMoved, CGPointMake(b.origin.x + [a[1] doubleValue] - 3, b.origin.y + [a[2] doubleValue])); spin(0.1); post(kCGEventMouseMoved, CGPointMake(b.origin.x + [a[1] doubleValue], b.origin.y + [a[2] doubleValue])); spin(0.7); }
            else if ([k isEqual:@"key"]) {
                // Only type when the destination is known: the scratch field or the probe's editor.
                NSString *target = scratchKey() ? @"scratch" : (probeEditing() ? @"probe" : nil);
                if (!target) note = @"key SKIPPED: neither scratch nor probe editor has focus";
                else { note = [@"key sent, expected target " stringByAppendingString:target];
                    CGEventRef d = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)[a[1] intValue], true); CGEventPost(kCGHIDEventTap, d); CFRelease(d); usleep(40000);
                    CGEventRef u = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)[a[1] intValue], false); CGEventPost(kCGHIDEventTap, u); CFRelease(u); spin(0.6); }
            }
            else if ([k isEqual:@"wait"]) spin([a[1] doubleValue] / 1000.0);
            else if ([k isEqual:@"clear"]) field.stringValue = @"";
            else if ([k isEqual:@"shot"]) { NSDictionary *w = probe(NULL); if (w) system([NSString stringWithFormat:@"screencapture -x -o -l %d %s/%@.png", [w[(id)kCGWindowNumber] intValue], outDir(), a[1]].UTF8String); }
            else if ([k isEqual:@"region"]) { system([NSString stringWithFormat:@"screencapture -x -R%.0f,%.0f,%.0f,%.0f %s/%@.png", b.origin.x, b.origin.y, b.size.width, b.size.height, outDir(), a[1]].UTF8String); note = [NSString stringWithFormat:@"fullscreen=%d", (win.styleMask & NSWindowStyleMaskFullScreen) != 0]; }
            else if ([k isEqual:@"strip"]) system([NSString stringWithFormat:@"screencapture -x -R0,0,1728,60 %s/%@.png", outDir(), a[1]].UTF8String);
            else if ([k isEqual:@"mission"]) { system("open -a 'Mission Control'"); spin(2.0); }
            else if ([k isEqual:@"full"]) { [win toggleFullScreen:nil]; full = !full; spin(3.5); }
            else if ([k isEqual:@"top"]) { post(kCGEventMouseMoved, CGPointMake(200, 40)); spin(0.2); post(kCGEventMouseMoved, CGPointMake(200, 1)); spin(0.1); post(kCGEventMouseMoved, CGPointMake(201, 0)); spin(2.0); }
            else if ([k isEqual:@"space"]) {
                CGKeyCode code = [a[1] isEqual:@"right"] ? 124 : 123;
                CGEventRef d = CGEventCreateKeyboardEvent(NULL, code, true); CGEventSetFlags(d, kCGEventFlagMaskControl | kCGEventFlagMaskSecondaryFn | kCGEventFlagMaskNumericPad); CGEventPost(kCGHIDEventTap, d); CFRelease(d); usleep(60000);
                CGEventRef u = CGEventCreateKeyboardEvent(NULL, code, false); CGEventSetFlags(u, kCGEventFlagMaskControl | kCGEventFlagMaskSecondaryFn | kCGEventFlagMaskNumericPad); CGEventPost(kCGHIDEventTap, u); CFRelease(u); releaseModifiers(); spin(2.0);
            }
            state(op, note);
            if (modifiersHeld()) { printf("stopping: a modifier is latched after %s\n", op.UTF8String); releaseModifiers(); break; }
        }
        releaseModifiers();
        if (full) { [win toggleFullScreen:nil]; spin(3.0); }
        [win close]; CGWarpMouseCursorPosition(original); [prior activateWithOptions:0]; spin(0.4);
        return 0;
    }
}
