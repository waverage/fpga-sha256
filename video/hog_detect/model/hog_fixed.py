"""Bit-exact model of the HOG person detector in hdl/.

Every integer operation here is mirrored in the Verilog; testbenches compare
against dumps from this file. Image: 1280x720, single scale, 64x128 window,
8x8 cells, 16x16 blocks, stride 8, 9 unsigned orientation bins, OpenCV's
default people detector weights.
"""
import numpy as np

W_IMG, H_IMG = 1280, 720
CW, CH = W_IMG // 8, H_IMG // 8          # 160 x 90 cells
BW, BH = CW - 1, CH - 1                  # 159 x 89 blocks
NX, NY = CW - 7, CH - 15                 # 153 x 75 windows

# ---- constants shared with the RTL -------------------------------------------
CORDIC_N = 10
ANG_BIN = 256                            # angle units per 20 degree bin
ATAN = [int(round(np.degrees(np.arctan(2.0 ** -i)) / 20 * ANG_BIN)) for i in range(CORDIC_N)]
EPS1 = 190                               # 3.6 in feature units (16 * K * 2 * 3.6)
EPS2 = 66                                # 1e-3 * 2^16
CLIP = 13107                             # 0.2 * 2^16
W_SHIFT = 15                             # weights scaled by 2^15, features by 2^8


def gamma_lut():
    return np.minimum(255, np.round(16 * np.sqrt(np.arange(256)))).astype(np.int64)


def sqrt_lut():
    """4096 entries, round(sqrt(m) * 64)."""
    return np.round(np.sqrt(np.arange(4096)) * 64).astype(np.int64)


def recip_lut():
    """2048 entries for m in [2048, 4096): round(2^23 / m)."""
    return np.round(2.0 ** 23 / np.arange(2048, 4096)).astype(np.int64)


SQRT_LUT, RECIP_LUT, GAMMA_LUT = sqrt_lut(), recip_lut(), gamma_lut()


def bitlen(a):
    """floor(log2(a)) + 1 for a >= 1, 0 for 0, elementwise on int64 arrays."""
    a = np.asarray(a, dtype=np.int64)
    out = np.zeros(a.shape, np.int64)
    v = a.copy()
    for s in (32, 16, 8, 4, 2, 1):
        big = v >= (1 << s)
        out[big] += s
        v[big] >>= s
    return np.where(a > 0, out + 1, 0)


def fsqrt(a):
    """sqrt via 4096-entry LUT: shift right by an even k so a >> k < 4096."""
    a = np.asarray(a, dtype=np.int64)
    k = np.maximum(0, bitlen(a) - 12)
    k = k + (k & 1)
    return (SQRT_LUT[a >> k] << (k >> 1)) >> 6


def frecip(n, p):
    """~2^p / n for n >= 1 via 2048-entry LUT on the 12-bit mantissa."""
    n = np.asarray(n, dtype=np.int64)
    e = bitlen(n) - 1                                # floor(log2 n)
    m = np.where(e >= 11, n >> np.maximum(e - 11, 0), n << np.maximum(11 - e, 0))
    r = RECIP_LUT[m - 2048]
    s = p - 12 - e
    return np.where(s >= 0, r << np.maximum(s, 0), r >> np.maximum(-s, 0))


# ---- pixel stages ---------------------------------------------------------------
def luma(rgb):
    rgb = rgb.astype(np.int64)
    return (77 * rgb[..., 0] + 150 * rgb[..., 1] + 29 * rgb[..., 2]) >> 8


def gradients(g):
    """Central differences, zero on the image border."""
    dx = np.zeros_like(g); dy = np.zeros_like(g)
    dx[:, 1:-1] = g[:, 2:] - g[:, :-2]
    dy[1:-1, :] = g[2:, :] - g[:-2, :]
    dx[0, :] = dx[-1, :] = 0; dy[:, 0] = dy[:, -1] = 0
    dx[:, 0] = dx[:, -1] = 0; dy[0, :] = dy[-1, :] = 0
    return dx, dy


def cordic(dx, dy):
    """Unsigned orientation and magnitude. Returns (mag, h0, frac)."""
    flip = (dy < 0) | ((dy == 0) & (dx < 0))
    dx = np.where(flip, -dx, dx); dy = np.where(flip, -dy, dy)
    # rotate by -90 degrees so the angle is in [-90, 90), scale up by 16
    x = dy << 4
    y = -dx << 4
    z = np.zeros_like(x)
    for i in range(CORDIC_N):
        neg = y < 0
        x, y, z = (np.where(neg, x - (y >> i), x + (y >> i)),
                   np.where(neg, y + (x >> i), y - (x >> i)),
                   np.where(neg, z - ATAN[i], z + ATAN[i]))
    theta = z + 9 * ANG_BIN // 2                     # [0, 2304)
    q = theta - ANG_BIN // 2
    h0 = q >> 8                                      # floor
    frac = q & 0xFF
    h0 = np.where(h0 < 0, h0 + 9, h0)
    h0 = np.where(h0 > 8, h0 - 9, h0)
    mag = x >> 3
    return mag, h0, frac


def cell_hist(rgb):
    H, W = rgb.shape[:2]
    g = GAMMA_LUT[luma(rgb)]
    dx, dy = gradients(g)
    mag, h0, frac = cordic(dx, dy)
    v1 = (mag * frac) >> 8
    v0 = mag - v1
    h1 = np.where(h0 == 8, 0, h0 + 1)
    cells = np.zeros((H // 8, W // 8, 9), np.int64)
    ys, xs = np.mgrid[0:H, 0:W]
    np.add.at(cells, (ys >> 3, xs >> 3, h0), v0)
    np.add.at(cells, (ys >> 3, xs >> 3, h1), v1)
    return cells


# ---- blocks ---------------------------------------------------------------------
def blocks(cells):
    """Normalised block features, shape (BH, BW, 36), uint8 range."""
    v = np.concatenate([cells[:-1, :-1], cells[1:, :-1], cells[:-1, 1:], cells[1:, 1:]], axis=2)
    ss = (v * v).sum(axis=2)
    n1 = fsqrt(ss) + EPS1
    r1 = frecip(n1, 31)
    u = np.minimum(CLIP, (v * r1[..., None]) >> 15)
    ss2 = (u * u).sum(axis=2)
    n2 = fsqrt(ss2) + EPS2
    r2 = frecip(n2, 30)
    f = np.minimum(255, (u * r2[..., None]) >> 22)
    return f, dict(ss=ss, r1=r1, ss2=ss2, r2=r2)


# ---- SVM ------------------------------------------------------------------------
def weights():
    import cv2
    w = cv2.HOGDescriptor_getDefaultPeopleDetector().reshape(-1)
    wq = np.round(w[:3780] * (1 << W_SHIFT)).astype(np.int64).reshape(7, 15, 36)
    rho = int(round(float(w[3780]) * (1 << (W_SHIFT + 8))))
    return wq, rho


def scores(f, wq, rho):
    ny, nx = f.shape[0] - 14, f.shape[1] - 6
    S = np.full((ny, nx), rho, np.int64)
    for i in range(7):
        for j in range(15):
            S += f[j:j + ny, i:i + nx] @ wq[i, j]
    return S


def thr_q(thr):
    return int(round(thr * (1 << (W_SHIFT + 8))))


def group(S, thr, K=8, reach=2, min_hits=2):
    """Raster-order clustering, see README. Returns boxes (x, y) in pixels and hits."""
    t = thr_q(thr)
    cl, hits = [], 0
    for y0 in range(S.shape[0]):
        for x0 in range(S.shape[1]):
            if S[y0, x0] <= t:
                continue
            hits += 1
            for c in cl:
                if abs(x0 - c[0]) <= reach and abs(y0 - c[1]) <= reach:
                    c[2] += x0; c[3] += y0; c[4] += 1
                    break
            else:
                if len(cl) < K:
                    cl.append([x0, y0, x0, y0, 1])
    boxes = [((c[2] * 8) // c[4], (c[3] * 8) // c[4]) for c in cl if c[4] >= min_hits]
    return boxes, hits


def detect(rgb, thr=0.0):
    cells = cell_hist(rgb)
    f, _ = blocks(cells)
    wq, rho = weights()
    S = scores(f, wq, rho)
    boxes, hits = group(S, thr)
    return boxes, hits, dict(cells=cells, f=f, S=S)
