// Scratch text field that observes its own key status while real CGEvents drive
// the probe. THIS MOVES THE POINTER, CLICKS AND TYPES. Ops are argv; state is
// printed after each. Keys are only sent when the scratch field or the probe's
// editor is known to hold focus.
#import <AppKit/AppKit.h>
static const char *outDir(void) { return getenv("OUT") ?: "/tmp/anotchup-live-checks"; }
static NSWindow *win; static NSTextField *field; static int resigns; static int downs; static NSString *logPath;
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
static void tap(CGKeyCode code, CGEventFlags flags, BOOL explicitFlags) {
    CGEventRef d = CGEventCreateKeyboardEvent(NULL, code, true); if (explicitFlags) CGEventSetFlags(d, flags); CGEventPost(kCGHIDEventTap, d); CFRelease(d); usleep(35000);
    CGEventRef u = CGEventCreateKeyboardEvent(NULL, code, false); if (explicitFlags) CGEventSetFlags(u, flags); CGEventPost(kCGHIDEventTap, u); CFRelease(u); usleep(35000);
}
// U.S. layout key codes for the characters the checks type.
static int codeFor(unichar c) {
    static NSDictionary *m; if (!m) m = @{@"a":@0,@"s":@1,@"d":@2,@"f":@3,@"h":@4,@"g":@5,@"z":@6,@"x":@7,@"c":@8,@"v":@9,@"b":@11,@"q":@12,@"w":@13,@"e":@14,@"r":@15,@"y":@16,@"t":@17,@"o":@31,@"u":@32,@"i":@34,@"p":@35,@"l":@37,@"j":@38,@"k":@40,@"n":@45,@"m":@46,@"_":@49,@"1":@18,@"2":@19,@"3":@20};
    NSNumber *n = m[[NSString stringWithCharacters:&c length:1]]; return n ? n.intValue : -1;
}
// The whole pasteboard is saved before the first modified key and restored at exit.
static NSArray *savedBoard;
static void saveBoard(void) {
    if (savedBoard) return; NSMutableArray *items = [NSMutableArray array];
    for (NSPasteboardItem *it in NSPasteboard.generalPasteboard.pasteboardItems) { NSMutableDictionary *d = [NSMutableDictionary dictionary]; for (NSString *t in it.types) { NSData *v = [it dataForType:t]; if (v) d[t] = v; } [items addObject:d]; }
    savedBoard = items;
}
static void restoreBoard(void) {
    if (!savedBoard) return; NSPasteboard *pb = NSPasteboard.generalPasteboard; [pb clearContents]; NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *d in savedBoard) { NSPasteboardItem *it = [NSPasteboardItem new]; for (NSString *t in d) [it setData:d[t] forType:t]; [items addObject:it]; }
    if (items.count) [pb writeObjects:items];
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
    printf("%-16s key=%d active=%d editor=%d resigns=%d downs=%d field='%s' space=%d front='%s' probe=%s(%.0f,%.0f,%.0f,%.0f) log='%s'%s\n", op.UTF8String,
        win.isKeyWindow, NSApp.isActive, win.firstResponder == field.currentEditor, resigns, downs, field.stringValue.UTF8String, win.isOnActiveSpace,
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
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *e) { downs++; return e; }];
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
            // Put the scratch window's top-left at a screen point (top-left origin), e.g. under the probe.
            else if ([k isEqual:@"place"]) { [win setFrameTopLeftPoint:NSMakePoint([a[1] doubleValue], NSScreen.screens[0].frame.size.height - [a[2] doubleValue])]; spin(0.4); }
            else if ([k isEqual:@"click"]) { resigns = 0; click(CGPointMake([a[1] doubleValue], [a[2] doubleValue])); spin(0.8); }
            else if ([k isEqual:@"prclick"]) { resigns = 0; CGPoint p = CGPointMake(b.origin.x + [a[1] doubleValue], b.origin.y + [a[2] doubleValue]); post(kCGEventMouseMoved, p); spin(0.15);
                CGEventRef d = CGEventCreateMouseEvent(NULL, kCGEventRightMouseDown, p, kCGMouseButtonRight); CGEventPost(kCGHIDEventTap, d); CFRelease(d); usleep(60000);
                CGEventRef u = CGEventCreateMouseEvent(NULL, kCGEventRightMouseUp, p, kCGMouseButtonRight); CGEventPost(kCGHIDEventTap, u); CFRelease(u); spin(0.8); }
            else if ([k isEqual:@"pscroll"]) { resigns = 0; post(kCGEventMouseMoved, CGPointMake(b.origin.x + [a[1] doubleValue], b.origin.y + [a[2] doubleValue])); spin(0.15);
                for (int n = 0; n < 5; n++) { CGEventRef w = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 1, -12); CGEventPost(kCGHIDEventTap, w); CFRelease(w); usleep(20000); } spin(0.8); }
            else if ([k isEqual:@"pburst"]) { CGPoint p = CGPointMake(b.origin.x + [a[1] doubleValue], b.origin.y + [a[2] doubleValue]); post(kCGEventMouseMoved, p); spin(0.15);
                for (int n = 0; n < [a[3] intValue]; n++) { post(kCGEventLeftMouseDown, p); usleep(25000); post(kCGEventLeftMouseUp, p); usleep(45000); } spin(1.0); }
            else if ([k isEqual:@"frame"]) { NSRect f = win.frame; note = [NSString stringWithFormat:@"scratch frame x=%.0f..%.0f y=%.0f..%.0f (top-left origin)", NSMinX(f), NSMaxX(f), NSScreen.screens[0].frame.size.height - NSMaxY(f), NSScreen.screens[0].frame.size.height - NSMinY(f)]; }
            // Glide the pointer from a probe point to a screen point in small steps, like a hand would.
            else if ([k isEqual:@"pglide"]) { CGPoint from = CGPointMake(b.origin.x + [a[1] doubleValue], b.origin.y + [a[2] doubleValue]), to = CGPointMake([a[3] doubleValue], [a[4] doubleValue]);
                for (int n = 0; n <= 40; n++) { post(kCGEventMouseMoved, CGPointMake(from.x + (to.x - from.x) * n / 40, from.y + (to.y - from.y) * n / 40)); usleep(8000); } spin(0.7); }
            // The ops below type. They run only when the scratch field or the probe's editor holds focus.
            else if ([@[@"type", @"mkey", @"ukey"] containsObject:k] && !(scratchKey() || probeEditing())) note = @"typing SKIPPED: neither scratch nor probe editor has focus";
            else if ([k isEqual:@"type"]) { NSString *t = a[1]; for (NSUInteger n = 0; n < t.length; n++) { int c = codeFor([t characterAtIndex:n]); if (c >= 0) tap((CGKeyCode)c, 0, NO); } spin(0.5); }
            else if ([k isEqual:@"mkey"]) { saveBoard(); CGEventFlags f = 0; NSString *m = a[2];
                if ([m containsString:@"c"]) f |= kCGEventFlagMaskCommand; if ([m containsString:@"s"]) f |= kCGEventFlagMaskShift; if ([m containsString:@"o"]) f |= kCGEventFlagMaskAlternate;
                tap((CGKeyCode)[a[1] intValue], f, YES); releaseModifiers(); spin(0.5); }
            else if ([k isEqual:@"ukey"]) { NSString *t = a[1]; unichar buf[32]; NSUInteger len = MIN(t.length, 32); [t getCharacters:buf range:NSMakeRange(0, len)];
                CGEventRef d = CGEventCreateKeyboardEvent(NULL, 0, true); CGEventKeyboardSetUnicodeString(d, len, buf); CGEventPost(kCGHIDEventTap, d); CFRelease(d); usleep(35000);
                CGEventRef u = CGEventCreateKeyboardEvent(NULL, 0, false); CGEventKeyboardSetUnicodeString(u, len, buf); CGEventPost(kCGHIDEventTap, u); CFRelease(u); spin(0.5); }
            else if ([k isEqual:@"pdbl"]) { CGPoint p = CGPointMake(b.origin.x + [a[1] doubleValue], b.origin.y + [a[2] doubleValue]); post(kCGEventMouseMoved, p); spin(0.15);
                for (int n = 1; n <= 2; n++) { CGEventRef d = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, p, kCGMouseButtonLeft); CGEventSetIntegerValueField(d, kCGMouseEventClickState, n); CGEventPost(kCGHIDEventTap, d); CFRelease(d); usleep(40000);
                    CGEventRef u = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, p, kCGMouseButtonLeft); CGEventSetIntegerValueField(u, kCGMouseEventClickState, n); CGEventPost(kCGHIDEventTap, u); CFRelease(u); usleep(60000); } spin(0.6); }
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
        restoreBoard();
        [win close]; CGWarpMouseCursorPosition(original); [prior activateWithOptions:0]; spin(0.4);
        return 0;
    }
}
