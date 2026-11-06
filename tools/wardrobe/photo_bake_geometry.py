"""UV-space inverse maps for wardrobe photos; no geometry or normal edits."""
import numpy as np


def depth_sides(points, triangles):
    """Classify the cloth volume, never discard steep faces inside its folds."""
    lo, hi = points.min(0), points.max(0)
    span = np.maximum(hi - lo, 1e-6)
    cells = np.clip(((points[:, :2] - lo[:2]) / span[:2] * 23).astype(int), 0, 23)
    mids = np.zeros((24, 24))
    for y in range(24):
        for x in range(24):
            z = points[(abs(cells[:, 0] - x) <= 1) & (abs(cells[:, 1] - y) <= 1), 2]
            mids[y, x] = (z.min() + z.max()) / 2 if len(z) else (lo[2] + hi[2]) / 2
    centers = points[triangles].mean(1)
    c = np.clip(((centers[:, :2] - lo[:2]) / span[:2] * 23).astype(int), 0, 23)
    return (centers[:, 2] < mids[c[:, 1], c[:, 0]]).astype(int)


def raster_triangle(uv, size, conservative=False):
    """Texture rows use top-left origin, matching the editor and Metal samples."""
    p = uv * [size, -size] + [0, size]
    low = np.maximum(np.floor(p.min(0) - (1 if conservative else 0)).astype(int), 0)
    high = np.minimum(np.ceil(p.max(0) + (1 if conservative else 0)).astype(int), size - 1)
    if np.any(low > high):
        return None
    yy, xx = np.mgrid[low[1]:high[1]+1, low[0]:high[0]+1]
    a, b, c = p
    det = (b[1]-c[1])*(a[0]-c[0]) + (c[0]-b[0])*(a[1]-c[1])
    if abs(det) < 1e-9:
        return None
    u = ((b[1]-c[1])*(xx+.5-c[0]) + (c[0]-b[0])*(yy+.5-c[1])) / det
    v = ((c[1]-a[1])*(xx+.5-c[0]) + (a[0]-c[0])*(yy+.5-c[1])) / det
    if conservative:
        # Include every texel whose bilinear footprint touches this triangle, even thin
        # protected triangles with no texel center. Otherwise print colors leak onto skin.
        du = (abs(b[1]-c[1]) + abs(c[0]-b[0])) / abs(det)
        dv = (abs(c[1]-a[1]) + abs(a[0]-c[0])) / abs(det)
        dw = (abs(a[1]-b[1]) + abs(b[0]-a[0])) / abs(det)
        valid = (u >= -du) & (v >= -dv) & (1-u-v >= -dw)
    else:
        valid = (u >= -1e-6) & (v >= -1e-6) & (u+v <= 1+1e-6)
    return yy[valid], xx[valid], np.stack([u[valid], v[valid], 1-u[valid]-v[valid]], axis=1)


def projection(points, side, region):
    xmin, xmax, ymin, ymax = region
    scale = .90 / max(xmax-xmin, ymax-ymin)
    u = .5 + (points[:, 0] - (xmin+xmax)/2) * scale * (1 if side == 0 else -1)
    v = .5 - (points[:, 1] - (ymin+ymax)/2) * scale
    return np.stack([(side + u)/2, v], axis=1)


def bake_map(points, triangles, uv_triangles, sides, regions, size=2048, excluded=None):
    mapping = np.full((size, size, 2), 65535, dtype='<u2')
    occupied = np.zeros((size, size), dtype=bool)
    protected = np.zeros((size, size), dtype=bool)
    selected = []
    if excluded is None: excluded = np.zeros(len(triangles), dtype=bool)
    for ids, uv, side, skip in zip(triangles, uv_triangles, sides, excluded):
        xmin, xmax, ymin, ymax = regions[side]
        footprint = raster_triangle(uv, size, conservative=True)
        if footprint is not None:
            fy, fx, fw = footprint
            # Clamp extrapolated barycentrics to the triangle for a conservative
            # region test. Even triangles narrower than one texel need protection.
            fw = np.maximum(fw, 0)
            fw /= fw.sum(axis=1, keepdims=True)
            fp = np.einsum('ij,jk->ik', fw, points[ids])
            outside = ((fp[:, 0] < xmin) | (fp[:, 0] > xmax) |
                       (fp[:, 1] < ymin) | (fp[:, 1] > ymax) | skip)
            protected[fy[outside], fx[outside]] = True
        raster = raster_triangle(uv, size)
        if raster is None:
            continue
        y, x, weights = raster
        occupied[y, x] = True
        world = np.einsum('ij,jk->ik', weights, points[ids])
        inside = ((world[:, 0] >= xmin) & (world[:, 0] <= xmax) &
                  (world[:, 1] >= ymin) & (world[:, 1] <= ymax) & (not skip))
        protected[y[~inside], x[~inside]] = True
        if inside.any():
            value = projection(world[inside], int(side), regions[side])
            mapping[y[inside], x[inside]] = np.round(np.clip(value, 0, 1) * 65534).astype('<u2')
            selected.append(ids)
    # A shared UV texel must never transfer a photo to an excluded body/accessory face.
    overlap = protected & (mapping[:, :, 0] != 65535)
    mapping[overlap] = 65535
    # Extend ONLY into unused UV gutters, never across protected body islands.
    filled = mapping[:, :, 0] != 65535
    for _ in range(3):
        old = mapping.copy(); previous = filled.copy()
        for dy, dx in [(0, 1), (0, -1), (1, 0), (-1, 0)]:
            dest_y = slice(max(0, dy), min(size, size+dy)); src_y = slice(max(0, -dy), min(size, size-dy))
            dest_x = slice(max(0, dx), min(size, size+dx)); src_x = slice(max(0, -dx), min(size, size-dx))
            take = ~protected[dest_y, dest_x] & ~occupied[dest_y, dest_x] & ~filled[dest_y, dest_x] & previous[src_y, src_x]
            mapping[dest_y, dest_x][take] = old[src_y, src_x][take]
            filled[dest_y, dest_x][take] = True
    return mapping, dict(mappedPixels=int(filled.sum()), protectedOverlapPixels=int(overlap.sum()),
                         selectedTriangles=len(selected))
