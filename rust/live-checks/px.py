"""Minimal PNG reader (8-bit RGB/RGBA, non-interlaced) for probe captures. Usage: px.py file x,y ..."""
import sys, zlib, struct
def load(path):
    d = open(path, 'rb').read(); assert d[:8] == b'\x89PNG\r\n\x1a\n'
    i = 8; idat = b''
    while i < len(d):
        n, t = struct.unpack('>I4s', d[i:i+8]); body = d[i+8:i+8+n]; i += 12 + n
        if t == b'IHDR': w, h, depth, ct, _, _, il = struct.unpack('>IIBBBBB', body)
        elif t == b'IDAT': idat += body
    assert depth in (8, 16) and ct in (2, 6) and il == 0, (depth, ct, il)
    bpp = (3 if ct == 2 else 4) * depth // 8; raw = zlib.decompress(idat); rows = []; prev = bytearray(w * bpp); p = 0
    for _ in range(h):
        f = raw[p]; line = bytearray(raw[p+1:p+1+w*bpp]); p += 1 + w * bpp
        for x in range(len(line)):
            a = line[x-bpp] if x >= bpp else 0; b = prev[x]; c = prev[x-bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                q = a + b - c; pa, pb, pc = abs(q-a), abs(q-b), abs(q-c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line); prev = line
    step = depth // 8
    def get(x, y):
        o = x * bpp; v = [rows[y][o + k*step] for k in range(bpp // step)]
        return tuple(v if len(v) == 4 else v + [255])
    return w, h, get
if __name__ == '__main__':
    w, h, get = load(sys.argv[1]); print(sys.argv[1], w, h)
    for a in sys.argv[2:]:
        x, y = map(int, a.split(',')); print(f'  ({x},{y}) rgba={get(x, y)}')
