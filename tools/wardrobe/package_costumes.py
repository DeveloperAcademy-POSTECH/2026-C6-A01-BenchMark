"""Package the existing complete costumes without changing mesh/UVs or source files.
Run with Blender -b --python package_costumes.py -- WORKSPACE
"""
import sys, tempfile, zipfile, subprocess, hashlib, json, shutil
from pathlib import Path
from pxr import Usd, UsdGeom, UsdUtils, Sdf
work = Path(sys.argv[sys.argv.index('--') + 1])
repo = work / 'project/oi-campus-redesign-pr'
source = work / 'project/OiCharacterLab/OiCharacterLab/Resources'
out = repo / 'apps/ios/OiDonation/Resources/Wardrobe'
thumbs = repo / 'apps/ios/OiDonation/Resources/WardrobeThumbnails'
report = work / 'output/oi-complete-costumes-20261104'
report.mkdir(parents=True, exist_ok=True)
records = []
for name in ['dinosaur', 'raincoat', 'bee', 'cat']:
    src = source / f'ClosetModels/closet-{name}.usdz'
    dest = out / f'wardrobe-costume-{name}.usdz'
    before = hashlib.sha256(src.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='oi-costume-') as temporary:
        scratch = Path(temporary)
        with zipfile.ZipFile(src) as archive:
            root = archive.namelist()[0]
            archive.extractall(scratch)
        # Keep texture paths/formats (including normal maps) and lossless PNG pixels.
        for image in scratch.rglob('*.png'):
            subprocess.run(['sips', '-Z', '1024', str(image)], check=True, stdout=subprocess.DEVNULL)
        assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(scratch/root)), str(dest))
    stage = Usd.Stage.Open(str(dest))
    box = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_, UsdGeom.Tokens.render]).ComputeWorldBound(stage.GetPseudoRoot()).ComputeAlignedRange()
    extent = box.GetSize()
    height = extent[1 if UsdGeom.GetStageUpAxis(stage) == UsdGeom.Tokens.y else 2] * UsdGeom.GetStageMetersPerUnit(stage)
    assert abs(height - 1.5) < .01, (name, height)
    with zipfile.ZipFile(dest) as archive:
        # Geometry is byte-identical; only texture resolution changes.
        assert archive.read(root) == zipfile.ZipFile(src).read(root)
        for entry in archive.infolist():
            assert entry.compress_type == zipfile.ZIP_STORED
        assert archive.testzip() is None
    shutil.copyfile(source / f'ClosetThumbnails/thumb-{name}.png', thumbs / f'oi-costume-{name}.png')
    assert before == hashlib.sha256(src.read_bytes()).hexdigest()
    records.append(dict(id=name, source=str(src), sha256=before, output=str(dest), bytes=dest.stat().st_size, heightMeters=height))
    print('COSTUME_READY', name, height, dest.stat().st_size, flush=True)
(report/'manifest.json').write_text(json.dumps(records, indent=2))
