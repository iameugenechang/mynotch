"""Fraction of a screen-region capture that matches the probe's own window capture (opaque pixels only)."""
import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from px import load
w, h, ref = load(sys.argv[1])
for f in sys.argv[2:]:
    try: w2, h2, got = load(f)
    except Exception as e: print(f, 'unreadable', e); continue
    if (w2, h2) != (w, h): print(f, 'size', w2, h2, 'vs', w, h); continue
    n = ok = 0
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            r = ref(x, y)
            if r[3] < 255: continue
            n += 1; g = got(x, y); ok += max(abs(a-b) for a, b in zip(r[:3], g[:3])) <= 8
    print(f'{f}: {100*ok/n:.1f}% of {n} opaque probe pixels visible on screen')
