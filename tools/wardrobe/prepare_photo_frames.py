"""Author rounded print areas strictly inside the existing front/back UV charts.
Run with Blender's Python. Geometry and image files are never edited.
"""
from pathlib import Path
from pxr import Usd, UsdGeom
import hashlib, json
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'apps/ios/OiDonation/Resources/WardrobePhotoUV'
layouts = {}

def frame(x, y, w, h):
    return dict(zip(['x', 'y', 'width', 'height', 'radius'],
                    [round(float(v), 6) for v in (x, y, w, h, min(w, h) * .14)]))

# Stay well inside the protected clothing boundary. A photo never reaches the
# polygon-level seam with skin/accessories even when dragged, scaled or rotated.
for item in json.loads((ROOT / 'tools/wardrobe/costume-photo-manifest.json').read_text()):
    result = {}
    for side, (xmin, xmax, ymin, ymax) in zip(['front', 'back'], item['regions']):
        scale = .90 / max(xmax-xmin, ymax-ymin)
        w, h = (xmax-xmin)*scale*.76, (ymax-ymin)*scale*.74
        result[side] = frame(.5-w/2, .5-h/2, w, h)
    result['sourceSHA256'] = item['sourceSHA256']
    layouts[item['id']] = result

for source in sorted(OUT.glob('*.usdz')):
    stage = Usd.Stage.Open(str(source))
    mesh = next(UsdGeom.Mesh(p) for p in stage.Traverse() if p.IsA(UsdGeom.Mesh))
    points = np.asarray(mesh.GetPointsAttr().Get())
    lo, hi = points.min(0), points.max(0)
    scale = .90 / max(hi[0]-lo[0], hi[1]-lo[1])
    # Plain tops: abdomen below the collar and above the hem, excluding sleeves.
    # Bottoms: one leg above the knee; avoid splitting a print across the crotch.
    if source.stem.endswith('-top'):
        cx, cy, width, height = 0, .64, .27, .22
    else:
        cx, cy, width, height = -.125, .35, .13, .14
    result = {}
    for side, sign in [('front', 1), ('back', -1)]:
        u = .5 + (cx-(lo[0]+hi[0])/2)*scale*sign
        v = .5 - (cy-(lo[1]+hi[1])/2)*scale
        result[side] = frame(u-width*scale/2, v-height*scale/2, width*scale, height*scale)
    result['sourceSHA256'] = hashlib.sha256(source.read_bytes()).hexdigest()
    layouts[source.stem] = result

(OUT / 'photo-print-frames.json').write_text(json.dumps(layouts, indent=2)+'\n')
print(f'PRINT_FRAMES_READY {len(layouts)} garment layouts')
