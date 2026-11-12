// SwiftUI twin of the GPUI-CE gate probe, for like-for-like measurement only.
// Same panel style, size, placement, content, timed steps and log lines.
// No camera, preferences, private API or installed-app integration.
import AppKit
import CoreVideo
import SwiftUI

let plainBackdrop = ProcessInfo.processInfo.environment["TWIN_PLAIN_BACKDROP"] == "1"
func log(_ line: String) { FileHandle.standardError.write((line + "\n").data(using: .utf8)!) }

// Port of Nv12Frame::new in rust/src/lib.rs: the same planes, built on the CPU per frame.
func makeFrame(phase: Int, mirrored: Bool) -> CVPixelBuffer {
    let w = 320, h = 240
    var y = [UInt8](repeating: 0, count: w * h)
    var uv = [UInt8](repeating: 0, count: w * h / 2)
    for row in 0..<h {
        for col in 0..<w {
            let x = mirrored ? w - 1 - col : col
            y[row * w + col] = abs(x - phase % w) < 8 ? 235 : (x < w / 2 ? 70 : 180)
        }
    }
    for row in 0..<h / 2 {
        for pair in 0..<w / 2 {
            let x = mirrored ? w / 2 - 1 - pair : pair
            uv[row * w + pair * 2] = x < w / 4 ? 90 : 170
            uv[row * w + pair * 2 + 1] = row < h / 4 ? 90 : 180
        }
    }
    var buffer: CVPixelBuffer?
    let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any], kCVPixelBufferMetalCompatibilityKey: true]
    CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attrs as CFDictionary, &buffer)
    let b = buffer!
    CVPixelBufferLockBaseAddress(b, [])
    let yBase = CVPixelBufferGetBaseAddressOfPlane(b, 0)!, yStride = CVPixelBufferGetBytesPerRowOfPlane(b, 0)
    let uvBase = CVPixelBufferGetBaseAddressOfPlane(b, 1)!, uvStride = CVPixelBufferGetBytesPerRowOfPlane(b, 1)
    y.withUnsafeBytes { src in for row in 0..<h { memcpy(yBase + row * yStride, src.baseAddress! + row * w, w) } }
    uv.withUnsafeBytes { src in for row in 0..<h / 2 { memcpy(uvBase + row * uvStride, src.baseAddress! + row * w, w) } }
    CVBufferSetAttachment(b, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4, .shouldPropagate)
    CVPixelBufferUnlockBaseAddress(b, [])
    return b
}

final class TwinPanel: NSPanel {
    var editing = false
    override var canBecomeKey: Bool { editing }
    override var canBecomeMain: Bool { false }
    // Occupies the menu-bar region, like the gate panel.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

func topFrame(_ screen: NSRect, _ size: NSSize) -> NSRect {
    NSRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height, width: size.width, height: size.height)
}

final class Model: ObservableObject {
    @Published var frame = makeFrame(phase: 0, mirrored: false)
    @Published var mirrored = false
    @Published var pulsing = false
    @Published var editing = false
    @Published var text = "" { didSet { if text != oldValue { log("[text] \"\(text)\"") } } }
    var phase = 0
    var expanded = false
    weak var panel: TwinPanel?

    func nextFrame() {
        phase = (phase + 24) % 320
        log("[action] frame phase=\(phase)")
        frame = makeFrame(phase: phase, mirrored: mirrored)
    }
    func toggleMirror() {
        mirrored.toggle()
        log("[action] mirror mirrored=\(mirrored)")
        frame = makeFrame(phase: phase, mirrored: mirrored)
    }
    func toggleSize() {
        expanded.toggle()
        log("[action] resize expanded=\(expanded)")
        guard let panel, let screen = panel.screen else { return }
        let size = expanded ? NSSize(width: 680, height: 390) : NSSize(width: 560, height: 320)
        panel.setFrame(topFrame(screen.frame, size), display: true)
        log("[resize] swiftui viewport=\(Int(size.width))x\(Int(size.height))")
        reportPlacement()
    }
    func reportPlacement() {
        guard let panel, let screen = panel.screen else { return }
        log(String(format: "[placement] window=%ld screen=%@ target_top=%.1f window_top=%.1f content_top=%.1f gap=%.1f",
                   panel.windowNumber, screen.localizedName, screen.frame.maxY, panel.frame.maxY, panel.frame.maxY, screen.frame.maxY - panel.frame.maxY))
    }
    func begin() {
        guard let panel, !editing else { return }
        panel.editing = true; editing = true
        panel.makeKeyAndOrderFront(nil)
        log("[edit] on native=true")
    }
    func end() {
        guard let panel, editing else { return }
        panel.editing = false; editing = false
        if panel.isKeyWindow { panel.resignKey() }
        panel.makeFirstResponder(nil)
        log("[edit] off end")
    }
    func step(_ name: String) {
        log("[step] \(name)")
        switch name {
        case "frame": nextFrame()
        case "mirror": toggleMirror()
        case "resize": toggleSize()
        case "pulse": pulsing.toggle()
        case "remove": panel?.close(); NSApp.terminate(nil)
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }
}

// Port of notch_path in rust/src/lib.rs (after NotchShape.swift), top 6, bottom 14.
struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, top: CGFloat = 6, bottom: CGFloat = 14
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: top, y: top), control: CGPoint(x: top, y: 0))
        p.addLine(to: CGPoint(x: top, y: h - bottom))
        p.addQuadCurve(to: CGPoint(x: top + bottom, y: h), control: CGPoint(x: top, y: h))
        p.addLine(to: CGPoint(x: w - top - bottom, y: h))
        p.addQuadCurve(to: CGPoint(x: w - top, y: h - bottom), control: CGPoint(x: w - top, y: h))
        p.addLine(to: CGPoint(x: w - top, y: top))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - top, y: 0))
        p.closeSubpath()
        return p
    }
}

// The frame is shown as layer contents with aspect-fill, the cheapest native route for a pixel buffer.
final class VideoNSView: NSView {
    private var reported = NSRect.zero
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }
    func show(_ buffer: CVPixelBuffer) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.contents = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue()
        CATransaction.commit()
    }
    override func layout() {
        super.layout()
        guard let window else { return }
        let r = convert(bounds, to: nil), box = NSRect(x: r.minX, y: window.frame.height - r.maxY, width: r.width, height: r.height)
        if box != reported { reported = box; log(String(format: "[video] box=%.1f,%.1f,%.1f,%.1f", box.minX, box.minY, box.width, box.height)) }
    }
}
struct VideoBox: NSViewRepresentable {
    let buffer: CVPixelBuffer
    func makeNSView(context: Context) -> VideoNSView { VideoNSView(frame: .zero) }
    func updateNSView(_ view: VideoNSView, context: Context) { view.show(buffer) }
}

// TWIN_NO_CLIP=1 drops the notch clip, to isolate its compositing cost.
let noClip = ProcessInfo.processInfo.environment["TWIN_NO_CLIP"] == "1"
extension View {
    @ViewBuilder func notchClipped() -> some View {
        if noClip { self } else { self.clipShape(NotchShape()) }
    }
}

struct PulseDot: View {
    @State private var on = false
    var body: some View {
        Rectangle().fill(Color(red: 1, green: 0xd0 / 255.0, blue: 0)).frame(width: 14, height: 14)
            .opacity(on ? 1 : 0.2)
            .onAppear { withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) { on = true } }
    }
}

struct ProbeButton: View {
    let title: String
    var color = Color(red: 0x45 / 255.0, green: 0x60 / 255.0, blue: 0x80 / 255.0)
    var hoverColor: Color? = nil
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Text(title).padding(.horizontal, 8)
            .background(hovered ? (hoverColor ?? color) : color)
            .onHover { hovered = $0 }
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
    }
}

struct Content: View {
    @ObservedObject var m: Model
    @FocusState private var fieldFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SwiftUI twin | \(m.editing ? "KEY" : "non-key") | synthetic only")
            HStack(spacing: 8) {
                ProbeButton(title: "Begin typing probe") { m.begin(); fieldFocused = true }
                ProbeButton(title: "End / Esc") { m.end() }
                ProbeButton(title: "Quit", color: Color(red: 0x80 / 255.0, green: 0x30 / 255.0, blue: 0x50 / 255.0)) { NSApp.terminate(nil) }
            }
            HStack(spacing: 8) {
                Text("Text:")
                TextField("Click to type", text: $m.text).textFieldStyle(.plain).focused($fieldFocused)
                    .frame(width: 300).padding(.horizontal, 4).background(Color.black.opacity(0.31))
                    .simultaneousGesture(TapGesture().onEnded { m.begin(); fieldFocused = true })
                    .onSubmit { log("[commit] \"\(m.text)\""); m.end() }
                    .onExitCommand { m.end() }
            }
            HStack(alignment: .top, spacing: 16) {
                VideoBox(buffer: m.frame).frame(width: 210, height: 130).clipped()
                VStack(alignment: .leading, spacing: 12) {
                    Text("SwiftUI subtree blur fixture").blur(radius: 2)
                    Group {
                        // TWIN_PLAIN_BACKDROP=1 swaps the system material for a flat tint, to isolate its cost.
                        if plainBackdrop { Text("Backdrop fixture").padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.19)) }
                        else { Text("Backdrop fixture").padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.ultraThinMaterial) }
                    }
                    Text("Video corners deliberately square: separate camera mask still open.").fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                ProbeButton(title: "Next frame", hoverColor: Color(red: 0x9f / 255.0, green: 0xd0 / 255.0, blue: 1)) { m.nextFrame() }
                ProbeButton(title: m.mirrored ? "Mirrored" : "Mirror") { m.toggleMirror() }
                ProbeButton(title: "Resize") { m.toggleSize() }
                ProbeButton(title: "Remove display probe") { m.panel?.close(); NSApp.terminate(nil) }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .font(.custom("Helvetica Neue", size: 16)).foregroundColor(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [Color(red: 0x21 / 255.0, green: 0x35 / 255.0, blue: 0x54 / 255.0), Color(red: 0x75 / 255.0, green: 0x27 / 255.0, blue: 0x52 / 255.0)], startPoint: .leading, endPoint: .trailing))
        .overlay(alignment: .top) { Rectangle().fill(Color(red: 0, green: 1, blue: 0xb3 / 255.0)).frame(height: 8) }
        .overlay(alignment: .topTrailing) { if m.pulsing { PulseDot().padding(.top, 12).padding(.trailing, 16) } }
        .notchClipped()
        .onChange(of: m.editing) { _, editing in if !editing { fieldFocused = false } }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = Model()
    var steps: [String] = []
    var interval = 3.0
    var timer: Timer?
    func applicationDidFinishLaunching(_ note: Notification) {
        log("[startup] opening probes on 1 display(s)")
        guard let screen = NSScreen.main else { exit(1) }
        let size = NSSize(width: 560, height: 320)
        let panel = TwinPanel(contentRect: topFrame(screen.frame, size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isMovable = false; panel.isReleasedWhenClosed = false
        panel.delegate = self
        model.panel = panel
        let host = NSHostingView(rootView: Content(m: model))
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(topFrame(screen.frame, size), display: false)
        panel.orderFrontRegardless()
        model.reportPlacement()
        log("[startup] display 0 probe ready")
        var index = 0
        if !steps.isEmpty {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
                guard let self, index < self.steps.count else { timer.invalidate(); return }
                self.model.step(self.steps[index]); index += 1
            }
        }
    }
    func windowDidResignKey(_ note: Notification) {
        if model.editing { model.panel?.editing = false; model.editing = false; log("[edit] off resigned") }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
let delegate = AppDelegate()
var valid = args.first == "--show"
var rest = Array(args.dropFirst())
while rest.count >= 2 {
    switch rest[0] {
    case "--steps": delegate.steps = rest[1].split(separator: ",").map(String.init)
    case "--step-ms": if let ms = Double(rest[1]), ms >= 10 { delegate.interval = ms / 1000 } else { valid = false }
    default: valid = false
    }
    rest.removeFirst(2)
}
let known: Set<String> = ["frame", "mirror", "resize", "pulse", "remove", "quit"]
if !valid || !rest.isEmpty || !delegate.steps.allSatisfy(known.contains) {
    print("anotchup-twin\n  --show [--steps frame,mirror,resize,pulse,remove,quit] [--step-ms N]\nSwiftUI twin of the GPUI-CE gate probe. No installed app, preferences, camera or permissions.")
    exit(args.isEmpty ? 0 : 2)
}
log("[startup] entering AppKit event loop")
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
