#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>
#import "gate.h"

// Experiment-only, per-instance subclass. GPUI base classes and delegates remain untouched.
static char stateKey;
static Class gateClass;
@interface AnotchupGateState : NSObject
@property(nonatomic) BOOL editing;
@property(nonatomic, strong) id resignObserver;
@end
@implementation AnotchupGateState
- (void)dealloc { if (_resignObserver) [[NSNotificationCenter defaultCenter] removeObserver:_resignObserver]; }
@end
static AnotchupGateState *state(NSWindow *window) { return objc_getAssociatedObject(window, &stateKey); }
static BOOL canKey(id self, SEL command) { (void)command; return state(self).editing; }
static BOOL neverMain(id self, SEL command) { (void)self; (void)command; return NO; }
// This panel deliberately occupies the menu-bar region. Only our per-instance
// subclass bypasses AppKit's visible-frame constraint; ordinary CE windows do not.
static NSRect keepFrame(id self, SEL command, NSRect requested, NSScreen *screen) {
    (void)self; (void)command; (void)screen;
    return requested;
}
static NSRect topFrame(NSRect screen, NSSize size) {
    return NSMakeRect(NSMidX(screen)-size.width/2, NSMaxY(screen)-size.height, size.width, size.height);
}
static void placeAtTop(NSWindow *window, NSScreen *screen, NSSize size) {
    if (screen) [window setFrame:topFrame(screen.frame,size) display:NO];
}
static void reportPlacement(NSView *view) {
    NSWindow *window=view.window;
    NSScreen *screen=window.screen;
    if (!screen) return;
    NSRect content=[window convertRectToScreen:[view convertRect:view.bounds toView:nil]];
    fprintf(stderr,"[placement] window=%ld screen=%s target_top=%.1f window_top=%.1f content_top=%.1f gap=%.1f\n",
        (long)window.windowNumber, screen.localizedName.UTF8String, NSMaxY(screen.frame), NSMaxY(window.frame),
        NSMaxY(content), NSMaxY(screen.frame)-NSMaxY(window.frame));
}
static NSView *checkedView(void *pointer) {
    if (![NSThread isMainThread] || !pointer) return nil;
    NSView *view = (__bridge NSView *)pointer;
    if (![view isKindOfClass:NSView.class] || object_getClass(view.window) != gateClass) return nil;
    return view;
}
bool gate_install(void *pointer) {
    if (![NSThread isMainThread] || !pointer) return false;
    NSView *view = (__bridge NSView *)pointer;
    NSWindow *window = view.window;
    Class base = objc_getClass("GPUIPanel");
    if (!base || ![window isKindOfClass:NSPanel.class] || object_getClass(window) != base || window.visible || window.delegate != (id)window) return false;
    NSScreen *screen=window.screen;
    NSSize size=view.bounds.size;
    if (!screen || window.styleMask != NSWindowStyleMaskNonactivatingPanel) return false;
    Method constraint=class_getInstanceMethod(base,@selector(constrainFrameRect:toScreen:));
    if (!constraint) return false;
    if (!gateClass) {
        // Refuse an existing conflicting class, rather than trusting an arbitrary implementation.
        if (objc_getClass("AnotchupGatePanel81742184")) return false;
        Class candidate = objc_allocateClassPair(base, "AnotchupGatePanel81742184", 0);
        if (!candidate) return false;
        BOOL added = class_addMethod(candidate, @selector(canBecomeKeyWindow), (IMP)canKey, method_getTypeEncoding(class_getInstanceMethod(base,@selector(canBecomeKeyWindow)))) &&
            class_addMethod(candidate, @selector(canBecomeMainWindow), (IMP)neverMain, method_getTypeEncoding(class_getInstanceMethod(base,@selector(canBecomeMainWindow)))) &&
            class_addMethod(candidate, @selector(constrainFrameRect:toScreen:), (IMP)keepFrame, method_getTypeEncoding(constraint));
        if (!added || class_getInstanceSize(candidate) != class_getInstanceSize(base)) { objc_disposeClassPair(candidate); return false; }
        objc_registerClassPair(candidate);
        gateClass = candidate; // Registered classes intentionally live until process exit.
    }
    AnotchupGateState *value = [AnotchupGateState new];
    objc_setAssociatedObject(window,&stateKey,value,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    object_setClass(window,gateClass);
    __weak AnotchupGateState *weakValue=value;
    value.resignObserver=[[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidResignKeyNotification object:window queue:nil usingBlock:^(NSNotification *note) { (void)note; weakValue.editing=NO; }];
    window.level=NSMainMenuWindowLevel+3;
    window.collectionBehavior=NSWindowCollectionBehaviorStationary|NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorIgnoresCycle;
    window.opaque=NO; window.backgroundColor=NSColor.clearColor; window.hasShadow=NO;
    window.hidesOnDeactivate=NO;
    // The backend must create this panel borderless. Never tear down a title
    // bar after changing isa: AppKit's KVO removal can throw NSRangeException.
    placeAtTop(window,screen,size);
    return !window.canBecomeKeyWindow && !window.canBecomeMainWindow;
}
static CGPathRef createPath(const GatePathCommand *commands,size_t count, double height) {
    CGMutablePathRef path=CGPathCreateMutable();
    // CoreGraphics/CALayer coordinates are bottom-left; the Rust path uses top-left.
    for (size_t i=0;i<count;i++) {
        GatePathCommand c=commands[i];
        switch(c.kind) {
            case 0: CGPathMoveToPoint(path,NULL,c.end.x,height-c.end.y); break;
            case 1: CGPathAddLineToPoint(path,NULL,c.end.x,height-c.end.y); break;
            case 2: CGPathAddQuadCurveToPoint(path,NULL,c.control.x,height-c.control.y,c.end.x,height-c.end.y); break;
            case 3: CGPathCloseSubpath(path); break;
            default: CGPathRelease(path); return NULL;
        }
    }
    return path;
}
bool gate_path_contains(const GatePathCommand *commands,size_t count,double height,double x,double y) {
    if (!commands || !count) return false;
    CGPathRef path=createPath(commands,count,height); if (!path) return false;
    bool result=CGPathContainsPoint(path,NULL,CGPointMake(x,height-y),false);
    CGPathRelease(path); return result;
}
bool gate_mask(void *pointer,const GatePathCommand *commands,size_t count) {
    NSView *view=checkedView(pointer); if (!view || !view.layer || !commands || !count) return false;
    CGPathRef path=createPath(commands,count,view.bounds.size.height); if (!path) return false;
    CAShapeLayer *mask=[CAShapeLayer layer];
    mask.frame=view.layer.bounds; mask.path=path; mask.fillColor=NSColor.blackColor.CGColor;
    [CATransaction begin]; [CATransaction setDisableActions:YES]; view.layer.mask=mask; [CATransaction commit];
    CGPathRelease(path); return true;
}
void gate_show(void *pointer) {
    NSView *view=checkedView(pointer); if (!view) return;
    NSWindow *window=view.window;
    [window orderFrontRegardless];
    placeAtTop(window,window.screen,window.frame.size);
    reportPlacement(view);
}
bool gate_edit(void *pointer,bool editing) {
    NSView *view=checkedView(pointer); if (!view) return false;
    state(view.window).editing=editing;
    if (editing) { [view.window makeKeyAndOrderFront:nil]; [view.window makeFirstResponder:view]; }
    else if (view.window.keyWindow) { [view.window resignKeyWindow]; }
    return state(view.window).editing;
}
bool gate_is_editing(void *pointer) { NSView *view=checkedView(pointer); return view && state(view.window).editing; }
void gate_resize(void *pointer,double width,double height) {
    NSView *view=checkedView(pointer); if (!view || !isfinite(width) || !isfinite(height) || width<40 || height<40) return;
    // Never resize inside the caller's GPUI update. AppKit resizes the view
    // synchronously, and the backend's resize callback is dropped while the app
    // is already borrowed, leaving GPUI laying out at the old viewport. The
    // backend's own resize defers for the same reason.
    __weak NSView *weakView=view;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSView *live=weakView;
        NSWindow *window=live.window;
        if (!window || object_getClass(window) != gateClass) return;
        placeAtTop(window,window.screen,NSMakeSize(width,height));
        reportPlacement(live);
    });
}
void *gate_frame(size_t width,size_t height,const uint8_t *y,const uint8_t *uv) {
    if (!y || !uv || !width || !height || width%2 || height%2 || width>4096 || height>4096) return NULL;
    CVPixelBufferRef buffer=NULL;
    NSDictionary *attrs=@{(id)kCVPixelBufferIOSurfacePropertiesKey:@{},(id)kCVPixelBufferMetalCompatibilityKey:@YES};
    CVReturn result=CVPixelBufferCreate(kCFAllocatorDefault,width,height,kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,(__bridge CFDictionaryRef)attrs,&buffer);
    if (result!=kCVReturnSuccess) return NULL;
    if (CVPixelBufferLockBaseAddress(buffer,0)!=kCVReturnSuccess) { CVPixelBufferRelease(buffer); return NULL; }
    for (size_t row=0;row<height;row++) memcpy((uint8_t *)CVPixelBufferGetBaseAddressOfPlane(buffer,0)+row*CVPixelBufferGetBytesPerRowOfPlane(buffer,0),y+row*width,width);
    for (size_t row=0;row<height/2;row++) memcpy((uint8_t *)CVPixelBufferGetBaseAddressOfPlane(buffer,1)+row*CVPixelBufferGetBytesPerRowOfPlane(buffer,1),uv+row*width,width);
    CVBufferSetAttachment(buffer,kCVImageBufferYCbCrMatrixKey,kCVImageBufferYCbCrMatrix_ITU_R_601_4,kCVAttachmentMode_ShouldPropagate);
    CVPixelBufferUnlockBaseAddress(buffer,0);
    return (void *)buffer;
}
bool gate_native_contracts(void) {
    @autoreleasepool {
        // Pure AppKit-coordinate contracts, including displays above and left
        // of the primary. No NSScreen query, NSApplication or window creation.
        NSRect screens[]={NSMakeRect(0,0,1512,982),NSMakeRect(-1920,-100,1920,1080),NSMakeRect(100,982,1920,1080)};
        NSSize sizes[]={NSMakeSize(560,320),NSMakeSize(680,390)};
        for (size_t i=0;i<3;i++) for (size_t j=0;j<2;j++) {
            NSRect rect=topFrame(screens[i],sizes[j]);
            if (NSMaxY(rect)!=NSMaxY(screens[i]) || NSMidX(rect)!=NSMidX(screens[i]) || !NSEqualSizes(rect.size,sizes[j])) return false;
            if (!NSEqualRects(keepFrame(nil,@selector(constrainFrameRect:toScreen:),rect,nil),rect)) return false;
        }
        uint8_t y[32*16],uv[32*8]; memset(y,70,sizeof(y)); memset(uv,128,sizeof(uv));
        y[31]=231; uv[0]=90; uv[1]=170;
        CVPixelBufferRef b=gate_frame(32,16,y,uv); if (!b) return false;
        BOOL valid=CVPixelBufferGetPixelFormatType(b)==kCVPixelFormatType_420YpCbCr8BiPlanarFullRange && CVPixelBufferGetPlaneCount(b)==2 && CVPixelBufferGetWidth(b)==32 && CVPixelBufferGetHeight(b)==16;
        if (CVPixelBufferLockBaseAddress(b,kCVPixelBufferLock_ReadOnly)!=kCVReturnSuccess) {CVPixelBufferRelease(b); return false;}
        valid=valid && ((uint8_t *)CVPixelBufferGetBaseAddressOfPlane(b,0))[31]==231 && ((uint8_t *)CVPixelBufferGetBaseAddressOfPlane(b,1))[0]==90 && ((uint8_t *)CVPixelBufferGetBaseAddressOfPlane(b,1))[1]==170;
        CVPixelBufferUnlockBaseAddress(b,kCVPixelBufferLock_ReadOnly); CVPixelBufferRelease(b);
        GatePathCommand square[]={{0,{0,0},{0,0}},{1,{0,0},{10,0}},{1,{0,0},{10,10}},{1,{0,0},{0,10}},{3,{0,0},{0,0}}};
        CGPathRef path=createPath(square,5,10);
        valid=valid && path && CGPathContainsPoint(path,NULL,CGPointMake(5,5),false) && !CGPathContainsPoint(path,NULL,CGPointMake(20,5),false);
        if(path) CGPathRelease(path);
        return valid && gate_frame(3,16,y,uv)==NULL;
    }
}
