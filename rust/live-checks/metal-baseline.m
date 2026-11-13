// Minimal Metal app with no GPUI: one panel, one render pass per frame. It shows how much
// graphics footprint any process that renders with Metal carries on this machine.
// No input events. Build:
//   clang -fobjc-arc -framework AppKit -framework Metal -framework QuartzCore -framework IOSurface -o /tmp/metal-baseline metal-baseline.m
// usage: metal-baseline <passes> <msaa 0|1> <fps> <pipelines> <mode>, then `footprint -p <pid>`
//   mode 0 presents a CAMetalLayer drawable, 1 renders offscreen only, 2 creates a device and queue
//   but never renders, 3 renders into an IOSurface shown by a plain CALayer.
//   STOP_AFTER=<frames> stops rendering; MAXCB=<n> limits the queue's command buffers.
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <IOSurface/IOSurface.h>
int main(int argc, const char **argv) { @autoreleasepool {
    int mode = argc > 5 ? atoi(argv[5]) : 0; int passes = argc > 1 ? atoi(argv[1]) : 1, msaa = argc > 2 ? atoi(argv[2]) : 0, fps = argc > 3 ? atoi(argv[3]) : 60, pipelines = argc > 4 ? atoi(argv[4]) : 0;
    NSApplication *app = NSApplication.sharedApplication; [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSRect s = NSScreen.mainScreen.frame;
    NSPanel *w = [[NSPanel alloc] initWithContentRect:NSMakeRect(NSMidX(s) - 280, NSMaxY(s) - 360, 560, 320) styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    id<MTLDevice> device = MTLCreateSystemDefaultDevice(); id<MTLCommandQueue> queue = getenv("MAXCB") ? [device newCommandQueueWithMaxCommandBufferCount:atoi(getenv("MAXCB"))] : [device newCommandQueue];
    int stopAfter = getenv("STOP_AFTER") ? atoi(getenv("STOP_AFTER")) : 0; __block int frames = 0;
    CAMetalLayer *layer = [CAMetalLayer layer]; layer.device = device; layer.pixelFormat = MTLPixelFormatBGRA8Unorm; layer.maximumDrawableCount = 3;
    layer.contentsScale = 2; layer.drawableSize = CGSizeMake(1120, 640);
    CALayer *plain = [CALayer layer]; plain.contentsScale = 2;
    w.contentView.wantsLayer = YES; w.contentView.layer = mode == 3 ? plain : layer; [w orderFrontRegardless];
    NSDictionary *props = @{(id)kIOSurfaceWidth: @1120, (id)kIOSurfaceHeight: @640, (id)kIOSurfaceBytesPerElement: @4, (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA')};
    IOSurfaceRef surfaceA = IOSurfaceCreate((__bridge CFDictionaryRef)props), surfaceB = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    MTLTextureDescriptor *sd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1120 height:640 mipmapped:NO]; sd.usage = MTLTextureUsageRenderTarget;
    NSArray *surfaceTextures = @[[device newTextureWithDescriptor:sd iosurface:surfaceA plane:0], [device newTextureWithDescriptor:sd iosurface:surfaceB plane:0]];
    __block int flip = 0;
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1120 height:640 mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead; td.storageMode = MTLStorageModePrivate;
    id<MTLTexture> offscreen = [device newTextureWithDescriptor:td];
    id<MTLTexture> ms = nil;
    if (msaa) { td.textureType = MTLTextureType2DMultisample; td.sampleCount = 4; td.storageMode = MTLStorageModeMemoryless; td.usage = MTLTextureUsageRenderTarget; ms = [device newTextureWithDescriptor:td]; }
    NSMutableArray *keep = [NSMutableArray array];
    if (pipelines) {
        NSString *src = @"#include <metal_stdlib>\nusing namespace metal;\nstruct V { float4 p [[position]]; };\nvertex V vs(uint i [[vertex_id]]) { V v; v.p = float4(float(i) - 1.0, float(i & 1) * 2.0 - 1.0, 0, 1); return v; }\nfragment float4 fs() { return float4(0.2, 0.3, 0.5, 1); }\n";
        id<MTLLibrary> lib = [device newLibraryWithSource:src options:nil error:nil];
        for (int i = 0; i < pipelines; i++) { MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new]; d.vertexFunction = [lib newFunctionWithName:@"vs"]; d.fragmentFunction = [lib newFunctionWithName:@"fs"]; d.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm; d.colorAttachments[0].blendingEnabled = i & 1; id<MTLRenderPipelineState> p = [device newRenderPipelineStateWithDescriptor:d error:nil]; if (p) [keep addObject:p]; }
    }
    [NSTimer scheduledTimerWithTimeInterval:1.0 / fps repeats:YES block:^(NSTimer *t) { @autoreleasepool {
        if (mode == 2) return;
        if (stopAfter && frames++ >= stopAfter) return;
        id<CAMetalDrawable> drawable = mode == 0 ? [layer nextDrawable] : nil; if (mode == 0 && !drawable) return;
        flip ^= 1; id<MTLTexture> target = mode == 0 ? drawable.texture : (mode == 3 ? surfaceTextures[flip] : offscreen);
        id<MTLCommandBuffer> cb = [queue commandBuffer];
        for (int i = 0; i < passes; i++) {
            MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor]; BOOL last = i == passes - 1;
            if (ms && !last) { rp.colorAttachments[0].texture = ms; rp.colorAttachments[0].resolveTexture = offscreen; rp.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve; }
            else { rp.colorAttachments[0].texture = last ? target : offscreen; rp.colorAttachments[0].storeAction = MTLStoreActionStore; }
            rp.colorAttachments[0].loadAction = MTLLoadActionClear; rp.colorAttachments[0].clearColor = MTLClearColorMake(0.13, 0.2, 0.33, 1);
            id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
            if (keep.count) { [enc setRenderPipelineState:keep[i % keep.count]]; [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; }
            [enc endEncoding];
        }
        if (mode == 0) [cb presentDrawable:drawable];
        if (mode == 3) { IOSurfaceRef done = flip ? surfaceB : surfaceA; [cb addCompletedHandler:^(id<MTLCommandBuffer> b) { (void)b; dispatch_async(dispatch_get_main_queue(), ^{ [CATransaction begin]; [CATransaction setDisableActions:YES]; plain.contents = (__bridge id)done; [CATransaction commit]; }); }]; }
        [cb commit];
    } }];
    [app run];
} return 0; }
