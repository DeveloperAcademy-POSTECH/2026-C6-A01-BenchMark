"""Bake front/back photo coordinates into each costume's ORIGINAL material UVs.
Run: Blender -b --python tools/wardrobe/prepare_costume_photo_uv.py -- REPORT [ID ...]
No meshes, normals or source USDZ files are changed. Regenerate after replacing a model.
"""
from pathlib import Path
from pxr import Usd, UsdGeom, UsdShade, Gf
import numpy as np
import json, hashlib, sys, zipfile, zlib
sys.path.insert(0, str(Path(__file__).resolve().parent))
from photo_bake_geometry import depth_sides, bake_map, projection
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'apps/ios/OiDonation/Resources/WardrobePhotoUV'
REPORT = Path(sys.argv[sys.argv.index('--')+1]); REPORT.mkdir(parents=True, exist_ok=True)
selectedIDs = set(sys.argv[sys.argv.index('--')+2:])
# Reviewed clothing-only windows in meters; +Z is front. Accessories stay untouched.
REGIONS={
 'dinosaur':(-.20,.20,.32,.72), 'raincoat':(-.22,.22,.34,.75),
 'bee':(-.22,.22,.40,.63), 'cat':(-.20,.20,.32,.72),
 'astronaut':(-.18,.18,.38,.75), 'scientist':(-.18,.18,.38,.77),
 'cat-bear':(-.19,.02,.32,.72), 'postech-selfie':(-.18,.18,.53,.78),
 'baseball':(-.16,.05,.43,.65), 'cowboy':(-.18,.18,.43,.67),
 'farmer':(-.18,.18,.35,.65), 'sportswear':(-.18,.18,.43,.65),
 'martial-arts':(-.18,.18,.35,.66), 'school-uniform':(-.18,.18,.43,.65),
 'school-uniform-trousers':(-.18,.18,.43,.65),
 'astronaut-navy':(-.18,.18,.38,.75), 'scientist-goggles':(-.18,.18,.38,.70)
}
BACK_OVERRIDES={'cat-bear':(-.19,.19,.32,.72),'baseball':(-.18,.18,.43,.65)}
ANCHORS=json.loads((ROOT/'tools/wardrobe/photo-print-anchors.json').read_text())

records = []
sources = [(ROOT/'apps/ios/OiDonation/Resources/Wardrobe'/('wardrobe-costume-'+k+'.usdz'), k) for k in REGIONS]
sources += [(ROOT/'apps/ios/OiDonation/Resources/Wardrobe'/('wardrobe-postech-'+b+'.usdz'),'postech-modular') for b in ['long','shorts']]
for source, key in sources:
    if selectedIDs and key not in selectedIDs: continue
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    stage = Usd.Stage.Open(str(source)); cache = UsdGeom.XformCache()
    assert UsdGeom.GetStageUpAxis(stage) == UsdGeom.Tokens.y
    assert UsdGeom.GetStageMetersPerUnit(stage) == 1
    groups = {}
    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh): continue
        if key == 'postech-modular' and '/Top/' not in str(prim.GetPath()): continue
        if key == 'cat-bear' and '/CenteredTail' in str(prim.GetPath()): continue
        m = UsdGeom.Mesh(prim)
        assert not UsdGeom.Subset.GetAllGeomSubsets(m), 'Material subsets need explicit binding support'
        mat = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0]
        surface = mat.ComputeSurfaceSource()[0]
        connection = surface.GetInput('diffuseColor').GetConnectedSource()
        shader = UsdShade.Shader(connection[0].GetPrim())
        assert shader.GetIdAttr().Get() == 'UsdUVTexture'
        image = shader.GetInput('file').Get().path
        # Different meshes may reuse the same material/UVs at different positions
        # (for example the repaired rear cloth). Each needs its own inverse map.
        group = groups.setdefault(str(prim.GetPath()), dict(points=[], triangles=[], uv=[], excluded=[], paths=[], image=image,
            backOnly=key == 'cat-bear' and '/RestoredRearFabric' in str(prim.GetPath())))
        matrix = cache.GetLocalToWorldTransform(prim)
        base = len(group['points'])
        group['points'].extend([tuple(matrix.Transform(Gf.Vec3d(p))) for p in m.GetPointsAttr().Get()])
        st = UsdGeom.PrimvarsAPI(m).GetPrimvar('st')
        assert st.GetInterpolation() in ('faceVarying', 'vertex', 'varying')
        uv = np.asarray(st.ComputeFlattened())
        indices = m.GetFaceVertexIndicesAttr().Get(); cursor = 0
        excluded = False
        for count in m.GetFaceVertexCountsAttr().Get():
            for j in range(1, count-1):
                corners = [cursor, cursor+j, cursor+j+1]
                ids = [indices[c] for c in corners]
                group['triangles'].append([base+i for i in ids])
                group['uv'].append(uv[corners if st.GetInterpolation() == 'faceVarying' else ids])
                group['excluded'].append(excluded)
            cursor += count
        if not excluded: group['paths'].append(str(prim.GetPath()).strip('/').split('/')[1:])
    name = 'photo-'+source.stem+'-top'
    regions = [REGIONS.get(key, (-.18,.18,.55,.78)), BACK_OVERRIDES.get(key, REGIONS.get(key, (-.18,.18,.55,.78)))]
    # The fixed print starts 12cm below the reviewed neck/body landmark.
    # Extend the bake window upward where needed; retain its protected side bounds.
    regions = [(*r[:3], max(r[3], ANCHORS[key][side]-.12+.03))
               for r, side in zip(regions, ['front', 'back'])]
    bindings=[]; stats=[]; guides=[[],[]]
    for index, group in enumerate(groups.values()):
        points=np.asarray(group['points']); triangles=np.asarray(group['triangles'])
        sides=np.ones(len(triangles), dtype=int) if group['backOnly'] else depth_sides(points, triangles)
        mapping, report=bake_map(points, triangles, np.asarray(group['uv']), sides, regions,
                                 excluded=np.asarray(group['excluded']))
        assert report['mappedPixels'] > 1000
        prefix=name+'-material-'+str(index)
        compressor=zlib.compressobj(level=9, wbits=-15)
        data=compressor.compress(mapping.tobytes())+compressor.flush()
        (OUT/(prefix+'.uvmap')).write_bytes(data)
        with zipfile.ZipFile(source) as archive:
            entry=next(n for n in archive.namelist() if n.endswith(group['image'].lstrip('./')))
            imageData=archive.read(entry)
        imageName=prefix+Path(group['image']).suffix
        (OUT/imageName).write_bytes(imageData)
        bindings.append(dict(paths=group['paths'], baseImage=imageName, map=prefix+'.uvmap', size=2048))
        stats.append(dict(**report, compressedBytes=len(data)))
        # Boundary of the front/back printable volume, including steep wrinkle faces.
        for side in [0,1]:
            r=regions[side]; verts=points[triangles]; centers=verts.mean(1)
            inside=(sides==side)&~np.asarray(group['excluded'])&(centers[:,0]>=r[0])&(centers[:,0]<=r[1])&(centers[:,1]>=r[2])&(centers[:,1]<=r[3])
            edges={}
            for tri in triangles[inside]:
                for a,b in zip(tri,np.roll(tri,-1)):
                    edge=tuple(sorted((int(a),int(b)))); edges[edge]=edges.get(edge,0)+1
            for edge,count in edges.items():
                if count != 1: continue
                p=projection(points[list(edge)],side,r); p[:,0]=p[:,0]*2-side
                guides[side].append(np.round(p,5).tolist())
    (OUT/(name+'-bake.json')).write_text(json.dumps(dict(version=1, sourceSHA256=before, bindings=bindings),separators=(',',':'))+'\n')
    for side,label in enumerate(['front','back']):
        (OUT/(name+'-'+label+'.json')).write_text(json.dumps(guides[side],separators=(',',':'))+'\n')
    assert hashlib.sha256(source.read_bytes()).hexdigest()==before
    records.append(dict(id=name, sourceSHA256=before, regions=regions, materials=stats))
    print('BAKE_READY',key,stats,flush=True)
manifest=ROOT/'tools/wardrobe/costume-photo-manifest.json'
if selectedIDs and manifest.exists():
    updated={r['id']:r for r in records}
    records=[updated.pop(r['id'],r) for r in json.loads(manifest.read_text())]+list(updated.values())
manifest.write_text(json.dumps(records,indent=2)+'\n')
(REPORT/'manifest.json').write_text(json.dumps(records,indent=2)+'\n')
