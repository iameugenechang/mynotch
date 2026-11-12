#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
typedef struct { double x, y; } GatePoint;
typedef struct { uint32_t kind; GatePoint control, end; } GatePathCommand;
// All view functions require a borrowed live GPUI NSView and the main thread.
bool gate_install(void *view);
bool gate_mask(void *view, const GatePathCommand *commands, size_t count);
void gate_show(void *view);
bool gate_edit(void *view, bool editing);
bool gate_is_editing(void *view);
void gate_resize(void *view, double width, double height);
// Returns a +1 CoreVideo pixel buffer. Caller must CFRelease it.
void *gate_frame(size_t width, size_t height, const uint8_t *y, const uint8_t *uv);
bool gate_path_contains(const GatePathCommand *commands, size_t count, double height, double x, double y);
// Headless placement arithmetic, constraint and CoreVideo/CoreGraphics contracts.
// Never constructs a window.
bool gate_native_contracts(void);
