"""Package the four existing card characters; preserve geometry, UVs and source files.

Run: Blender -b --python package_card_costumes.py -- WORKSPACE
No generation, mesh editing, or paid service calls. Only copied textures are resized.
"""
import hashlib
import json
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from pxr import Sdf, Usd, UsdGeom, UsdUtils

work = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
repo = Path(__file__).resolve().parents[2]
source = work / 'meshy_output/oi-five-characters-20261102'
out = repo / 'apps/ios/OiDonation/Resources/Wardrobe'
thumbs = repo / 'apps/ios/OiDonation/Resources/WardrobeThumbnails'
report = work / 'output/oi-card-costumes-20261104'
report.mkdir(parents=True, exist_ok=True)
characters = [
    ('astronaut', '03-astronaut', '20261102_200402_oi-five-astronaut_01a19bee'),
    ('scientist', '04-scientist', '20261102_200412_oi-five-scientist_01a19bee'),
    ('cat-bear', '05-cat', '20261102_200426_oi-five-cat_01a19bee'),
    ('postech-selfie', '01-postech', '20261102_200311_oi-five-postech_01a19bed'),
]

records = []
for name, stem, folder in characters:
    src = source / f'{stem}-150cm.usdz'
    dest = out / f'wardrobe-costume-{name}.usdz'
    before = hashlib.sha256(src.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='oi-card-costume-') as temporary:
        scratch = Path(temporary)
        with zipfile.ZipFile(src) as archive:
            root = archive.namelist()[0]
            archive.extractall(scratch)
            geometry = archive.read(root)
        for image in scratch.rglob('*'):
            if image.suffix.lower() in ('.jpg', '.jpeg', '.png'):
                subprocess.run(['sips', '-Z', '1024', str(image)], check=True, stdout=subprocess.DEVNULL)
        packaged = scratch / 'packaged.usdz'
        assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(scratch/root)), str(packaged))
        stage = Usd.Stage.Open(str(packaged))
        box = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_, UsdGeom.Tokens.render]).ComputeWorldBound(stage.GetPseudoRoot()).ComputeAlignedRange()
        assert UsdGeom.GetStageUpAxis(stage) == UsdGeom.Tokens.y
        units = UsdGeom.GetStageMetersPerUnit(stage)
        height = box.GetSize()[1] * units
        ground = box.GetMin()[1] * units
        assert abs(height - 1.5) < .001 and abs(ground) < .001, (name, height, ground)
        triangles = sum(sum(int(n)-2 for n in UsdGeom.Mesh(p).GetFaceVertexCountsAttr().Get()) for p in stage.Traverse() if p.IsA(UsdGeom.Mesh))
        with zipfile.ZipFile(packaged) as archive:
            assert archive.read(root) == geometry, 'USD geometry/material bindings must be unchanged'
            assert all(i.compress_type == zipfile.ZIP_STORED for i in archive.infolist())
            assert archive.testzip() is None
        _, _, unresolved = UsdUtils.ComputeAllDependencies(str(packaged))
        assert not unresolved, unresolved
        dest.write_bytes(packaged.read_bytes())
    # Use the actual Meshy result, rather than a concept picture, as the item thumbnail.
    thumbnail = source / folder / 'previews/thumbnail_front.png'
    subprocess.run(['sips', '-Z', '256', str(thumbnail), '--out', str(thumbs / f'oi-costume-{name}.png')], check=True, stdout=subprocess.DEVNULL)
    assert before == hashlib.sha256(src.read_bytes()).hexdigest()
    records.append(dict(id=name, source=str(src.relative_to(work)), sourceSHA256=before,
                        sourceBytes=src.stat().st_size, bytes=dest.stat().st_size,
                        heightMeters=height, groundMeters=ground, triangles=triangles,
                        geometryByteIdentical=True, outputSHA256=hashlib.sha256(dest.read_bytes()).hexdigest()))
    print('COSTUME_READY', name, height, dest.stat().st_size, flush=True)
(report/'manifest.json').write_text(json.dumps(records, indent=2))
