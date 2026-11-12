// Prints the probe's accessibility tree, or presses an element by title. No pointer or key events.
// Needs Accessibility access. The tree is built lazily: the first query after launch may be incomplete.
#import <AppKit/AppKit.h>
static void walk(AXUIElementRef e, int depth, int *count) {
    if (depth > 12 || *count > 200) return; (*count)++;
    CFTypeRef role = NULL, title = NULL, value = NULL, desc = NULL, focused = NULL; CFArrayRef kids = NULL;
    AXUIElementCopyAttributeValue(e, kAXRoleAttribute, &role); AXUIElementCopyAttributeValue(e, kAXTitleAttribute, &title);
    AXUIElementCopyAttributeValue(e, kAXValueAttribute, &value); AXUIElementCopyAttributeValue(e, kAXDescriptionAttribute, &desc);
    AXUIElementCopyAttributeValue(e, kAXFocusedAttribute, &focused);
    CFArrayRef actions = NULL; AXUIElementCopyActionNames(e, &actions);
    printf("%*s%s title=%s value=%s desc=%s focused=%s actions=%s\n", depth * 2, "", [[(__bridge id)role description] UTF8String] ?: "?",
        [[(__bridge id)title description] UTF8String] ?: "-", [[(__bridge id)value description] UTF8String] ?: "-", [[(__bridge id)desc description] UTF8String] ?: "-",
        [[(__bridge id)focused description] UTF8String] ?: "-", [[[(__bridge NSArray *)actions componentsJoinedByString:@","] description] UTF8String] ?: "-");
    if (AXUIElementCopyAttributeValue(e, kAXChildrenAttribute, (CFTypeRef *)&kids) == kAXErrorSuccess && kids)
        for (CFIndex i = 0; i < CFArrayGetCount(kids); i++) walk(CFArrayGetValueAtIndex(kids, i), depth + 1, count);
}
// ax-dump <title> performs AXPress on the first element with that title, as VoiceOver would.
static BOOL press(AXUIElementRef e, NSString *title, int depth) {
    if (depth > 12) return NO; CFTypeRef t = NULL; AXUIElementCopyAttributeValue(e, kAXTitleAttribute, &t);
    if ([(__bridge id)t isEqual:title]) { AXError r = AXUIElementPerformAction(e, kAXPressAction); printf("AXPress on '%s' -> %d\n", title.UTF8String, (int)r); return r == kAXErrorSuccess; }
    CFArrayRef kids = NULL;
    if (AXUIElementCopyAttributeValue(e, kAXChildrenAttribute, (CFTypeRef *)&kids) == kAXErrorSuccess && kids)
        for (CFIndex i = 0; i < CFArrayGetCount(kids); i++) if (press(CFArrayGetValueAtIndex(kids, i), title, depth + 1)) return YES;
    return NO;
}
int main(int argc, const char **argv) { @autoreleasepool {
    if (!AXIsProcessTrusted()) { printf("no Accessibility access\n"); return 2; }
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
        if (![app.localizedName isEqual:@"anotchup-gates"]) continue;
        AXUIElementRef root = AXUIElementCreateApplication(app.processIdentifier); int count = 0;
        if (argc > 1) return press(root, [NSString stringWithUTF8String:argv[1]], 0) ? 0 : 4;
        walk(root, 0, &count); printf("elements=%d\n", count); return 0;
    }
    printf("probe not running\n"); return 1;
} }
