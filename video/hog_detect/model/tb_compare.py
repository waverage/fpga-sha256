"""Prepare hog_tb input and compare its dumps with the model.

    python tb_compare.py prep  <rundir> <png|vtest:frame> [x y w h]
    python tb_compare.py check <rundir>
"""
import os
import sys
import numpy as np
import hog_fixed as hf


def load_rgb(src):
    import cv2
    if src.startswith('vtest:'):
        cap = cv2.VideoCapture(os.environ.get('VTEST', 'E:/amd/hog_data/vtest.avi'))
        cap.set(cv2.CAP_PROP_POS_FRAMES, int(src.split(':')[1]))
        ok, f = cap.read()
        out = np.zeros((720, 1280, 3), np.uint8)
        out[72:648, 256:1024] = f
        return out[:, :, ::-1].copy()
    return cv2.imread(src)[:, :, ::-1].copy()


def prep(rundir, src, crop):
    rgb = load_rgb(src)
    if crop:
        x, y, w, h = crop
        rgb = rgb[y:y + h, x:x + w].copy()
    np.save(os.path.join(rundir, 'img.npy'), rgb)
    with open(os.path.join(rundir, 'img.hex'), 'w') as f:
        for p in rgb.reshape(-1, 3):
            f.write('%02x%02x%02x\n' % (p[0], p[2], p[1]))      # {R, B, G}
    print('image', rgb.shape[1], 'x', rgb.shape[0])


def check(rundir):
    rgb = np.load(os.path.join(rundir, 'img.npy'))
    boxes, hits, d = hf.detect(rgb)
    f, S = d['f'], d['S']
    ok = True

    rows = np.loadtxt(os.path.join(rundir, 'blocks.txt'), dtype=np.int64, ndmin=2)
    got = np.zeros_like(f) - 1
    for r in rows:
        got[r[1], r[0]] = r[2:]
    nb = (got != f).any(axis=2).sum()
    print('blocks: %d of %d differ' % (nb, f.shape[0] * f.shape[1]))
    if nb:
        ok = False
        by, bx = np.argwhere((got != f).any(axis=2))[0]
        print('  first at bx=%d by=%d\n  rtl  %s\n  model %s' % (bx, by, got[by, bx], f[by, bx]))

    rows = np.loadtxt(os.path.join(rundir, 'scores.txt'), dtype=np.int64, ndmin=2)
    gs = np.full(S.shape, -1 << 60, np.int64)
    order_ok = True
    prev = (-1, -1)
    for x0, y0, s in rows:
        gs[y0, x0] = s
        if (y0, x0) <= prev:
            order_ok = False
        prev = (y0, x0)
    ns = (gs != S).sum()
    print('scores: %d of %d differ, raster order %s' % (ns, S.size, order_ok))
    if ns:
        ok = False
        y0, x0 = np.argwhere(gs != S)[0]
        print('  first at x0=%d y0=%d rtl %d model %d' % (x0, y0, gs[y0, x0], S[y0, x0]))

    lines = open(os.path.join(rundir, 'boxes.txt')).read().split('\n')
    rhits = int(lines[0])
    rb = [tuple(map(int, l.split())) for l in lines[1:9]]
    rboxes = [(x, y) for okb, x, y in rb if okb]
    print('hits rtl %d model %d' % (rhits, hits))
    print('boxes rtl %s\n      model %s' % (rboxes, boxes))
    if rhits != hits or rboxes != boxes:
        ok = False
    print('HOG MATCH' if ok else 'HOG MISMATCH')


if __name__ == '__main__':
    cmd, rundir = sys.argv[1], sys.argv[2]
    if cmd == 'prep':
        prep(rundir, sys.argv[3], [int(v) for v in sys.argv[4:8]] if len(sys.argv) > 4 else None)
    else:
        check(rundir)
