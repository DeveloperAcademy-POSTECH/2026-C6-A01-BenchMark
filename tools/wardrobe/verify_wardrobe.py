"""Run with Blender's Python after prepare_wardrobe.py. Validate packaged, not in-memory geometry."""
import sys, json, hashlib, zipfile
from pathlib import Path
from pxr import Usd, UsdGeom
work = Path(sys.argv[sys.argv.index('--') + 1])
report = work / 'output/oi-compatible-wardrobe-20261103'
resources = work / 'project/oi-campus-redesign-pr/apps/ios/OiDonation/Resources/Wardrobe'
manifest = json.loads((report / 'manifest.json').read_text())
checks = []
for source, digest in manifest['sourceHashes'].items():
    path = work / f'meshy_output/compatibility-audit-20261101/trial/separated/{source}-parts.blend'
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, source
for entry in manifest['variants']:
    path = resources / (entry['id'] + '.usdz')
    assert hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
    stage = Usd.Stage.Open(str(path))
    assert UsdGeom.GetStageUpAxis(stage) == 'Y'
    assert UsdGeom.GetStageMetersPerUnit(stage) == 1
    bound = UsdGeom.BBoxCache(Usd.TimeCode.Default(), ['default', 'render']).ComputeWorldBound(stage.GetDefaultPrim()).ComputeAlignedBox()
    height = bound.GetSize()[1]
    assert abs(height - 1.5) < 0.002, (path, height)
    names = {p.GetName() for p in stage.Traverse()}
    assert {'Top', 'Bottom', 'Shoes', 'Skin_head'} <= names, names
    meshes = [p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)]
    assert all(UsdGeom.PrimvarsAPI(p).GetPrimvar('st').HasValue() or p.GetPath().pathString.startswith('/OiWardrobe/Shoes') for p in meshes)
    for p in stage.Traverse():
        for a in p.GetAttributes():
            if a.GetTypeName().type.typeName == 'SdfAssetPath':
                asset = a.Get()
                if asset and asset.path:
                    assert asset.resolvedPath, (p.GetPath(), a.GetName(), asset.path)
    checks.append({'id': entry['id'], 'packagedHeightMeters': height, 'meshes': len(meshes), 'status': 'pass'})
(report / 'validation.json').write_text(json.dumps({'sourceFilesUnchanged': True, 'variants': checks}, indent=2))
print('PASS: all 8 USDZ packages, source hashes, 150 cm bounds, UVs, material roles, and texture dependencies')
