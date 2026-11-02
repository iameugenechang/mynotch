import AppKit
import ApplicationServices

// Optional native smoke test: xcrun swift Tests/OneGoalUISmoke.swift /path/to/mynotch.app
// Requires Accessibility access. Refuses to overwrite an existing saved goal.
let appID = ProcessInfo.processInfo.environment["MYNOTCH_UI_BUNDLE_ID"] ?? "com.iameugenechang.mynotch"
let storageKey = "oneGoal.current"
let appPath = CommandLine.arguments.dropFirst().first ?? "/tmp/mynotch-build/Build/Products/Debug/mynotch.app"
let goalText = "Send the proposal to Maya"
var checks = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
    print("PASS: \(message)")
}
func waitUntil(_ message: String, _ condition: () -> Bool) {
    for _ in 0..<60 {
        if condition() { return }
        Thread.sleep(forTimeInterval: 0.1)
    }
    fatalError("Timed out: \(message)")
}
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &result)
    return result
}
func text(_ element: AXUIElement, _ name: String) -> String {
    attribute(element, name) as? String ?? ""
}
func runningApp() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: appID).first
}
func descendants(_ element: AXUIElement) -> [AXUIElement] {
    let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    return children.flatMap { [$0] + descendants($0) }
}
func elements() -> [AXUIElement] {
    guard let app = runningApp() else { return [] }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
    return windows.flatMap { descendants($0) }
}
func find(_ role: String, _ label: String) -> AXUIElement? {
    elements().first {
        text($0, kAXRoleAttribute) == role &&
        (text($0, kAXDescriptionAttribute) == label || text($0, kAXTitleAttribute) == label)
    }
}
func identified(_ identifier: String) -> AXUIElement? {
    elements().first { text($0, kAXIdentifierAttribute) == identifier }
}
func contextMenuItems() -> [AXUIElement] {
    guard let app = runningApp() else { return [] }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    let children = attribute(root, kAXChildrenAttribute) as? [AXUIElement] ?? []
    return children.filter { text($0, kAXRoleAttribute) != kAXMenuBarRole }
        .flatMap { [$0] + descendants($0) }
        .filter { text($0, kAXRoleAttribute) == kAXMenuItemRole }
}
func press(_ label: String) {
    waitUntil("button \(label)") { find(kAXButtonRole, label) != nil }
    expect(AXUIElementPerformAction(find(kAXButtonRole, label)!, kAXPressAction as CFString) == .success, "press \(label)")
    Thread.sleep(forTimeInterval: 0.3)
}
func sendKey(_ key: CGKeyCode, flags: CGEventFlags = []) {
    guard let app = runningApp() else { fatalError("App exited") }
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)!
        event.flags = flags
        event.postToPid(app.processIdentifier)
    }
    Thread.sleep(forTimeInterval: 0.2)
}
func typeText(_ string: String) {
    guard let app = runningApp() else { fatalError("App exited") }
    let utf16 = Array(string.utf16)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
        event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        event.postToPid(app.processIdentifier)
    }
    Thread.sleep(forTimeInterval: 0.3)
}
func frame(_ element: AXUIElement) -> CGRect {
    var point = CGPoint.zero
    var size = CGSize.zero
    if let position = attribute(element, kAXPositionAttribute) {
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
    }
    if let dimensions = attribute(element, kAXSizeAttribute) {
        AXValueGetValue(dimensions as! AXValue, .cgSize, &size)
    }
    return CGRect(origin: point, size: size)
}
func movePointer(to point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.6)
}
func savedGoal() -> Data? {
    CFPreferencesAppSynchronize(appID as CFString)
    return CFPreferencesCopyAppValue(storageKey as CFString, appID as CFString) as? Data
}
func launch() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-n", appPath, "--args", "-firstLaunch", "NO", "-showWhatsNew", "NO"]
    try! process.run()
    process.waitUntilExit()
    expect(process.terminationStatus == 0, "launch app")
    waitUntil("collapsed ring") { find(kAXButtonRole, "Edit One Goal") != nil }
    Thread.sleep(forTimeInterval: 2) // Let startup media/battery activity settle.
}
func restart() {
    runningApp()!.terminate()
    waitUntil("app quit") { runningApp() == nil }
    launch()
}

expect(AXIsProcessTrusted(), "Accessibility automation available")
expect(savedGoal() == nil, "no saved goal will be overwritten")
if runningApp() == nil { launch() }

let ringFrame = frame(find(kAXButtonRole, "Edit One Goal")!)
movePointer(to: CGPoint(x: ringFrame.midX, y: ringFrame.midY))
expect(find(kAXButtonRole, "Home") == nil, "hovering ring does not expand notch")
let screen = NSScreen.screens.first!
movePointer(to: CGPoint(x: screen.frame.midX, y: 20))
waitUntil("normal hover expansion") { find(kAXButtonRole, "Home") != nil }
expect(true, "moving from ring to notch preserves hover expansion")
movePointer(to: CGPoint(x: 40, y: 400))
waitUntil("hover collapse") { find(kAXButtonRole, "Home") == nil }
waitUntil("notch body geometry") { identified("notch-body") != nil }
let emptyBodyFrame = frame(identified("notch-body")!)
let emptyBodySize = emptyBodyFrame.size
expect(emptyBodyFrame.contains(ringFrame), "countdown ring is inside the notch silhouette")
if let leftArea = screen.auxiliaryTopLeftArea {
    expect(ringFrame.maxX <= screen.frame.minX + leftArea.width + 2, "countdown ring stays clear of the camera")
}

press("Edit One Goal")
waitUntil("goal field") { find(kAXTextFieldRole, "Goal") != nil }
expect(find(kAXButtonRole, "One Goal") != nil, "One Goal tab exists")
expect(find(kAXButtonRole, "Shelf") != nil, "Shelf tab remains available")
expect(frame(find(kAXButtonRole, "Home")!).minY < 10, "editor stays anchored to screen top")
expect(frame(identified("notch-body")!).height <= 190, "expanded notch keeps its original height")

// Move outside the notch, then use real keyboard events rather than setting a binding.
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: 40, y: 400), mouseButton: .left)?.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.5)
expect(find(kAXTextFieldRole, "Goal") != nil, "editor survives pointer leaving")
typeText("Discard this draft")
expect(text(find(kAXTextFieldRole, "Goal")!, kAXValueAttribute) == "Discard this draft", "editor receives keyboard input")
sendKey(53) // Escape
waitUntil("cancel collapsed") { find(kAXTextFieldRole, "Goal") == nil }
expect(savedGoal() == nil, "Escape discards draft")

press("Edit One Goal")
waitUntil("goal field") { find(kAXTextFieldRole, "Goal") != nil }
typeText(goalText)
sendKey(36) // Return
waitUntil("saved label") { find(kAXButtonRole, "Edit goal: \(goalText)") != nil && find(kAXTextFieldRole, "Goal") == nil }
waitUntil("persisted goal") { savedGoal() != nil }
expect(true, "Return saves and collapses")
waitUntil("unchanged collapsed body") { frame(identified("notch-body")!).size == emptyBodySize }
expect(true, "saving a goal does not change notch body size")
let shortLabelFrame = frame(find(kAXButtonRole, "Edit goal: \(goalText)")!)
expect(shortLabelFrame.width < emptyBodySize.width, "short goal label hugs its text")
expect(abs(shortLabelFrame.minY - frame(identified("notch-body")!).maxY) < 0.5, "goal tab joins the notch with no gap")

press("Edit goal: \(goalText)")
waitUntil("saved text restored") { find(kAXTextFieldRole, "Goal").map { text($0, kAXValueAttribute) == goalText } ?? false }
expect(abs(frame(find(kAXButtonRole, "Edit goal: \(goalText)")!).minY - frame(identified("notch-body")!).maxY) < 0.5, "goal tab stays attached when expanded")
let minutesField = find(kAXTextFieldRole, "Countdown minutes")!
expect(AXUIElementSetAttributeValue(minutesField, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success, "focus countdown duration")
sendKey(0, flags: .maskCommand) // Select all
// A one-minute timer is enough to check the live state without waiting for expiry.
typeText("1")
press("Start")
expect(find(kAXButtonRole, "Clear") != nil, "countdown starts")
press("Save")
restart()
expect(find(kAXButtonRole, "Edit goal: \(goalText)") != nil, "goal survives app restart")
press("Edit One Goal")
waitUntil("restored countdown") { find(kAXButtonRole, "Clear") != nil }
expect(true, "countdown survives app restart")
press("Clear")
expect(find(kAXButtonRole, "Clear") == nil, "countdown clears independently")
press("Save")
press("Edit One Goal")
press("Home")
expect(find(kAXTextFieldRole, "Goal") == nil, "switching tabs exits editor")
press("Shelf")
expect(find(kAXButtonRole, "One Goal") != nil, "Shelf remains navigable")
press("One Goal")
press("Complete")
waitUntil("completed goal removed") { savedGoal() == nil && find(kAXButtonRole, "Edit goal: \(goalText)") == nil }
expect(true, "completion removes text and saved state")
restart()
expect(find(kAXTextFieldRole, "Goal") == nil && savedGoal() == nil, "completion survives app restart")
expect(find(kAXButtonRole, "Edit One Goal") != nil, "empty state retains ring only")

let longGoal = "Finish the proposal with a clear outcome for Maya and send the final reviewed version before starting another piece of work"
press("Edit One Goal")
waitUntil("long-goal editor") { find(kAXTextFieldRole, "Goal") != nil }
typeText(longGoal)
press("Save")
let label = find(kAXButtonRole, "Edit goal: \(longGoal)")!
let labelFrame = frame(label)
expect(labelFrame.width <= 220, "long goal stays bounded to notch width")
expect(labelFrame.width > shortLabelFrame.width, "label width follows text length")
expect(frame(identified("notch-body")!).size == emptyBodySize, "long goal does not enlarge notch body")
expect(labelFrame.height <= 20, "goal keeps a small click target below notch")
expect(abs(labelFrame.minY - frame(identified("notch-body")!).maxY) < 0.5, "long goal tab has no gap below notch")
expect(labelFrame.minY >= screen.safeAreaInsets.top, "goal stays below camera")
expect(abs(labelFrame.midX - screen.frame.midX) < 1, "goal is centered below notch")
press("Edit goal: \(longGoal)")
expect(text(find(kAXTextFieldRole, "Goal")!, kAXValueAttribute) == longGoal, "truncation does not lose saved text")
sendKey(0, flags: .maskCommand)
typeText("Unsaved draft that must be discarded")
let otherApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first!
otherApp.activate(options: [])
waitUntil("editor dismissed by another app") { find(kAXTextFieldRole, "Goal") == nil }
expect(find(kAXButtonRole, "Edit goal: \(longGoal)") != nil, "clicking another app discards unsaved draft")
press("Edit One Goal")
press("Complete")
waitUntil("smoke state cleared") { savedGoal() == nil }
expect(true, "smoke test leaves no saved goal")

let body = frame(identified("notch-body")!)
let click = CGPoint(x: body.midX, y: min(16, body.midY))
for eventType in [CGEventType.rightMouseDown, .rightMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: click, mouseButton: .right)?.post(tap: .cghidEventTap)
}
waitUntil("notch quit context menu") {
    contextMenuItems().contains { text($0, kAXTitleAttribute) == "Quit mynotch" }
}
expect(contextMenuItems().contains { text($0, kAXTitleAttribute) == "Settings" }, "right-click menu retains Settings")
let quit = contextMenuItems().first { text($0, kAXTitleAttribute) == "Quit mynotch" }!
expect(AXUIElementPerformAction(quit, kAXPressAction as CFString) == .success, "right-click menu offers Quit mynotch")
waitUntil("quit from notch menu") { runningApp() == nil }
expect(true, "Quit from notch menu terminates app")
print("One Goal native smoke: \(checks) checks passed")
