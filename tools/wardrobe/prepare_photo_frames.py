"""Author rounded print areas 12cm below reviewed neck/body landmarks.
Run with Blender's Python after prepare_costume_photo_uv.py.
Geometry and image files are never edited. All physical coordinates are meters.
"""
from pathlib import Path
from pxr import Usd, UsdGeom
import hashlib, json
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'apps/ios/OiDonation/Resources/WardrobePhotoUV'
anchors = json.loads((ROOT / 'tools/wardrobe/photo-print-anchors.json').read_text())
legacy = json.loads((ROOT / 'tools/wardrobe/photo-print-frames-v1.json').read_text())
NECK_GAP = .12
layouts = {}

def frame(x, y, w, h):
    return dict(zip(['x', 'y', 'width', 'height', 'radius'],
                    [round(float(v), 6) for v in (x, y, w, h, min(w, h) * .14)]))

def finish(name, result, digest):
    # Rebase existing drafts once, so moving the frame does not leave their photos behind.
    for side in ['front', 'back']:
        result['legacy'+side.title()] = legacy[name][side]
    result['sourceSHA256'] = digest
    layouts[name] = result

for item in json.loads((ROOT / 'tools/wardrobe/costume-photo-manifest.json').read_text()):
    key = item['id'].removeprefix('photo-wardrobe-costume-').removesuffix('-top')
    if key.startswith('photo-wardrobe-postech-'): key = 'postech-modular'
    anchor = anchors[key]
    result = {}
    for side, (xmin, xmax, ymin, ymax) in zip(['front', 'back'], item['regions']):
        scale = .90 / max(xmax-xmin, ymax-ymin)
        w, h = (xmax-xmin)*scale*.76, anchor['height']*scale
        top = anchor[side]-NECK_GAP
        assert ymin < top-anchor['height'] < top < ymax
        v = .5-(top-(ymin+ymax)/2)*scale
        result[side] = frame(.5-w/2, v, w, h)
    finish(item['id'], result, item['sourceSHA256'])

for source in sorted(OUT.glob('*.usdz')):
    stage = Usd.Stage.Open(str(source))
    mesh = next(UsdGeom.Mesh(p) for p in stage.Traverse() if p.IsA(UsdGeom.Mesh))
    points = np.asarray(mesh.GetPointsAttr().Get())
    lo, hi = points.min(0), points.max(0)
    scale = .90 / max(hi[0]-lo[0], hi[1]-lo[1])
    result = {}
    for side, sign in [('front', 1), ('back', -1)]:
        if source.stem.endswith('-top'):
            anchor = anchors[source.stem.split('-')[2]]
            height = anchor['height']
            cx, cy, width = 0, anchor[side]-NECK_GAP-height/2, .27
        else:
            # Standalone trousers keep their original single-leg print area.
            cx, cy, width, height = -.125, .35, .13, .14
        u = .5 + (cx-(lo[0]+hi[0])/2)*scale*sign
        v = .5 - (cy-(lo[1]+hi[1])/2)*scale
        result[side] = frame(u-width*scale/2, v-height*scale/2, width*scale, height*scale)
    finish(source.stem, result, hashlib.sha256(source.read_bytes()).hexdigest())

(OUT / 'photo-print-frames.json').write_text(json.dumps(layouts, indent=2)+'\n')
print(f'PRINT_FRAMES_READY {len(layouts)} garment layouts')
