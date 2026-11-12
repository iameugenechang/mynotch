"""Compare captured video pixels with the synthetic NV12 frame, cover crop and mirror arithmetic."""
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from px import load
def lin(c): c /= 255; return c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4
def enc(v): v = min(max(v, 0), 1); return round(255*(12.92*v if v <= 0.0031308 else 1.055*v**(1/2.4)-0.055))
M = [[0.8225, 0.1774, 0.0], [0.0332, 0.9669, 0.0], [0.0171, 0.0724, 0.9108]]
def p3(rgb): l = [lin(c) for c in rgb]; return tuple(enc(sum(M[i][j]*l[j] for j in range(3))) for i in range(3))
def rgb(y, u, v): return tuple(min(255, max(0, round(c))) for c in (y+1.402*(v-128), y-0.344136*(u-128)-0.714136*(v-128), y+1.772*(u-128)))
W, H, BW, BH, X0, Y0 = 320, 240, 210.0, 130.0, 16.0, 118.0   # source px; element box in points
scale = max(BW/W, BH/H); ox = (W*scale-BW)/2; oy = (H*scale-BH)/2
def expect(px_, py_, phase, mirrored):
    sx = int((px_/2 - X0 + ox)/scale); sy = int((py_/2 - Y0 + oy)/scale)   # displayed column/row in the buffer
    x = W-1-sx if mirrored else sx                                        # generator's source_x
    y = 235 if abs(x - phase % W) < 8 else (70 if x < W//2 else 180)
    cx = (W//2-1-sx//2) if mirrored else sx//2
    return rgb(y, 90 if cx < W//4 else 170, 90 if sy//2 < H//4 else 180)
if sys.argv[1] == '--state':
    phase, m = map(int, sys.argv[2].split(',')); mirrored = bool(m); steps = []; files = [sys.argv[3]]
else:
    steps = sys.argv[1].split(','); phase = 0; mirrored = False; files = [f'cam-{n}.png' for n in range(len(steps)+1)]
bad = 0
for n in range(len(files)):
    if n:
        if steps[n-1] == 'frame': phase = (phase+24) % 320
        if steps[n-1] == 'mirror': mirrored = not mirrored
    w, h, get = load(files[n]); worst = 0; count = 0
    for py_ in range(240, 494, 6):
        for px_ in range(36, 450, 3):
            sxf = (px_/2 - X0 + ox)/scale; syf = (py_/2 - Y0 + oy)/scale
            x = W-1-sxf if mirrored else sxf
            # skip samples within 3 source px of a colour boundary (bilinear filtering)
            if min(abs(x-(phase-8)), abs(x-(phase+8)), abs(sxf-W/2), abs(syf-H/2)) < 3: continue
            e = p3(expect(px_, py_, phase, mirrored)); c = get(px_, py_)[:3]
            d = max(abs(a-b) for a, b in zip(e, c)); worst = max(worst, d); count += 1
    # just outside the box must be background, not video
    outside = [get(28, 366)[:3], get(456, 366)[:3], get(240, 232)[:3], get(240, 500)[:3]]
    leak = any(abs(c[1]-0x35) > 16 or c[0] > 0x80 for c in outside)
    ok = worst <= 6 and not leak; bad += not ok
    print(f'{files[n]} {w}x{h} phase={phase} mirrored={int(mirrored)} samples={count} worst_channel_error={worst} outside_is_background={int(not leak)} {"PASS" if ok else "FAIL"}')
sys.exit(1 if bad else 0)
