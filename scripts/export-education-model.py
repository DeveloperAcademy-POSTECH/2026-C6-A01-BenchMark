"""Blender 4.5: export the supplied Meshy surface for web + native campus.

blender --background --factory-startup SOURCE.blend --python THIS.py -- OUTPUT.bin
The source .blend is read-only. No volume fill, reconstruction or mesh fitting.
"""
import bpy
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import numpy as np

COUNT = 96_000
WIDTH = 12.8
REVISION = "meshy-building-surface-20261112-v1"
out = Path(sys.argv[sys.argv.index("--") + 1])
out.parent.mkdir(parents=True, exist_ok=True)
objects = [o for o in bpy.context.scene.objects if o.type == "MESH"]
assert len(objects) == 1, "Review multi-object sources before exporting"
obj = objects[0]
mesh = obj.data
mesh.calc_loop_triangles()
vertices = np.empty((len(mesh.vertices), 3), dtype=np.float32)
mesh.vertices.foreach_get("co", vertices.ravel())
matrix = np.array(obj.matrix_world, dtype=np.float64)
vertices = np.einsum('ij,kj->ki', matrix[:3, :3], vertices) + matrix[:3, 3]
indices = np.empty((len(mesh.loop_triangles), 3), dtype=np.int32)
mesh.loop_triangles.foreach_get("vertices", indices.ravel())
normals = np.empty((len(mesh.vertices), 3), dtype=np.float32)
mesh.vertices.foreach_get("normal", normals.ravel())
normals = np.einsum('ij,jk->ik', normals, np.linalg.inv(matrix[:3, :3]))
normals /= np.maximum(np.linalg.norm(normals, axis=1)[:, None], 1e-12)
lo, hi = vertices.min(axis=0), vertices.max(axis=0)
center = (lo + hi) / 2
factor = WIDTH / (hi[0] - lo[0])


def convex_hull(points):
    # Rounded to 0.1 mm in source units, solely for the planning-area estimate.
    pts = sorted(set(map(tuple, np.round(points, 4))))
    def cross(o, a, b):
        return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0: lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0: upper.pop()
        upper.append(p)
    return np.array(lower[:-1]+upper[:-1])


hull = convex_hull(vertices[:, :2])
source_area = abs(np.sum(hull[:, 0]*np.roll(hull[:, 1], -1)-hull[:, 1]*np.roll(hull[:, 0], -1)))/2
# This is an approximate gross envelope calibration, not an architectural survey.
meters_per_source_unit = math.sqrt(13_054.01 / source_area)
dimensions_m = (hi-lo)*meters_per_source_unit


def orient(p):
    # Blender -Y facade becomes +Z; keep the raised hall on the viewer's left.
    q = (p-center)*factor
    return np.stack([q[:, 0], q[:, 2], -q[:, 1]], axis=1)


a, b, c = (vertices[indices[:, i]] for i in range(3))
crosses = np.cross(b-a, c-a)
areas = np.linalg.norm(crosses, axis=1)/2
# The sealed underside is not an architectural surface seen on the campus.
bottom = ((a[:, 2]+b[:, 2]+c[:, 2])/3 < lo[2]+0.012) & (crosses[:, 2] < 0)
areas[bottom] = 0
cumulative = np.cumsum(areas)
rng = np.random.default_rng(20261112)
candidate_count = 1_200_000
tri = np.searchsorted(cumulative, (np.arange(candidate_count)+rng.random(candidate_count))/candidate_count*cumulative[-1])
u = np.sqrt(rng.random(candidate_count))
v = rng.random(candidate_count)
weights = np.stack([1-u, u*(1-v), u*v], axis=1)
raw = (vertices[indices[tri]]*weights[:, :, None]).sum(axis=1)
candidate_points = orient(raw)
candidate_normals = (normals[indices[tri]]*weights[:, :, None]).sum(axis=1)
candidate_normals = candidate_normals[:, [0, 2, 1]] * np.array([1, 1, -1])
candidate_normals /= np.maximum(np.linalg.norm(candidate_normals, axis=1)[:, None], 1e-12)
del a, b, c, crosses, tri, weights, raw


def cells(size):
    cell = np.floor(candidate_points/size).astype(np.int64)
    key = ((cell[:, 0]+1024) << 22) | ((cell[:, 1]+1024) << 11) | (cell[:, 2]+1024)
    return key, cell


# One source-surface point per voxel eliminates clumps. Tune the voxel spacing
# before selecting the fixed GPU budget, rather than randomly striding vertices.
low, high = 0.015, 0.12
for _ in range(18):
    mid = (low+high)/2
    number = len(np.unique(cells(mid)[0]))
    if number > COUNT*1.01: low = mid
    else: high = mid
spacing = low
keys, cell = cells(spacing)
distance = np.sum((candidate_points-(cell+.5)*spacing)**2, axis=1)
order = np.lexsort((distance, keys))
sorted_keys = keys[order]
selected = order[np.r_[True, sorted_keys[1:] != sorted_keys[:-1]]]
selected = selected[np.linspace(0, len(selected)-1, COUNT).astype(int)]
p = candidate_points[selected]
n = candidate_normals[selected]

# Morton order + four interleaved phases: every 24k prefix covers the full model.
q = np.clip(((p-p.min(axis=0))/(p.max(axis=0)-p.min(axis=0))*1023).astype(np.uint32), 0, 1023)
morton = np.zeros(COUNT, dtype=np.uint32)
for bit in range(10):
    for axis in range(3): morton |= ((q[:, axis] >> bit) & 1) << (bit*3+axis)
ordered = np.argsort(morton, kind="stable")
lod_order = np.concatenate([ordered[phase::4] for phase in [0, 2, 1, 3]])
p, n = p[lod_order], n[lod_order]
brightness = .78+.18*np.clip((n[:, 1]+1)/2, 0, 1)
records = np.column_stack([p, n, brightness]).astype("<f4")
assert np.isfinite(records).all()
assert np.allclose(np.linalg.norm(n, axis=1), 1, atol=1e-5)

# A lightweight copy supplies the WEB depth-only pass. The iOS map never draws
# this shell; both visible renderers consist exclusively of surface pearls.
copy = obj.copy()
copy.data = obj.data.copy()
bpy.context.collection.objects.link(copy)
modifier = copy.modifiers.new("Depth-only proxy", "DECIMATE")
modifier.ratio = min(1, 40_000/len(mesh.loop_triangles))
evaluated = copy.evaluated_get(bpy.context.evaluated_depsgraph_get())
proxy = evaluated.to_mesh()
proxy.calc_loop_triangles()
pv = np.empty((len(proxy.vertices), 3), dtype=np.float32)
proxy.vertices.foreach_get("co", pv.ravel())
pv = np.einsum('ij,kj->ki', matrix[:3, :3], pv) + matrix[:3, 3]
pt = np.empty((len(proxy.loop_triangles), 3), dtype=np.int32)
proxy.loop_triangles.foreach_get("vertices", pt.ravel())
shell = orient(pv)[pt].reshape(-1, 3).astype("<f4")
assert np.isfinite(shell).all()
ground = float((hi[2]-lo[2])*factor/2)
blob = b"OIEDU002"+struct.pack("<IIf", COUNT, len(shell), ground)+records.tobytes()+shell.tobytes()
out.write_bytes(blob)
bridge = vertices[vertices[:, 0] < lo[0]+.008]
bridge_center = orient(((bridge.min(axis=0)+bridge.max(axis=0))/2)[None, :])[0]
bridge_center[1] += ground
report = {
    "revision": REVISION,
    "sourceFile": Path(bpy.data.filepath).name,
    "sourceSHA256": hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),
    "sourceVertexCount": len(vertices), "sourceTriangleCount": len(mesh.loop_triangles),
    "assetSHA256": hashlib.sha256(blob).hexdigest(),
    "pointCount": COUNT, "shellVertexCount": len(shell), "byteCount": len(blob),
    "groundOffset": ground, "surfaceSpacing": float(spacing),
    "bounds": {"min": orient(vertices).min(axis=0).tolist(), "max": orient(vertices).max(axis=0).tolist()},
    "bridgeAnchor": bridge_center.tolist(),
    "planningScale": {
        "officialBuildingAreaM2": 13_054.01,
        "sourceEnvelopeArea": float(source_area),
        "metersPerLocalUnit": float(meters_per_source_unit/factor),
        "mapScale": float(meters_per_source_unit/factor*.12),
        "estimatedWidthDepthHeightM": dimensions_m.tolist(),
        "method": "Uniform Meshy envelope-area calibration; dimensions and height estimated, not surveyed.",
        "source": "https://www.postech.ac.kr/kor/innovation/education_district_cp.do"
    },
    "footprint": np.column_stack([(hull[:, 0]-center[0])*factor, -(hull[:, 1]-center[1])*factor]).tolist(),
    "lod": {"mapFar": 24_000, "mapNear": COUNT, "webMobile": 48_000},
    "groups": {"provided Meshy model surface": COUNT},
}
out.with_name("education-district-geometry.json").write_text(json.dumps(report, indent=2)+"\n")
print(json.dumps({k:v for k,v in report.items() if k not in ["footprint", "sourceSHA256"]}, indent=2))
