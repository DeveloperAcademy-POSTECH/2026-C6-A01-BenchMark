#!/usr/bin/env python3
"""Create versioned remote USDZs without changing source assets or App Clip membership.
Requires Pillow and Apple's usdcat/usdzip/usdchecker tools; Blender only for large static meshes.
"""
import argparse, hashlib, json, struct, subprocess, tempfile
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile, ZIP_STORED
from PIL import Image

p=argparse.ArgumentParser()
p.add_argument('--source', type=Path, default=Path('apps/ios/OiDonation/Resources/Characters'))
p.add_argument('--output', type=Path, default=Path('apps/ios/RemoteAssets/CharactersLite'))
p.add_argument('--blender', default='/Applications/Blender.app/Contents/MacOS/Blender')
p.add_argument('--texture-size', type=int, default=1024)
p.add_argument('--triangles', type=int, default=100000)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
rows=[]; workspace=tempfile.TemporaryDirectory(prefix='oi-character-lod-'); work=Path(workspace.name); jobs=[]
for src in sorted(a.source.glob('*.usdz')):
    folder=work/src.stem;folder.mkdir()
    textures=[]
    with ZipFile(src) as archive:
        for member in archive.infolist():
            destination=folder/member.filename
            assert destination.resolve().is_relative_to(folder.resolve()), 'Unsafe archive path'
            destination.parent.mkdir(parents=True,exist_ok=True)
            data=archive.read(member)
            if destination.suffix.lower() in ['.jpg','.jpeg','.png']:
                image=Image.open(BytesIO(data));before=image.size
                image.thumbnail((a.texture_size,a.texture_size),Image.Resampling.LANCZOS)
                if destination.suffix.lower() in ['.jpg','.jpeg']:
                    image.save(destination,quality=88,optimize=True,subsampling=0)
                else: image.save(destination,optimize=True)
                textures.append(dict(file=member.filename,before=list(before),after=list(image.size)))
            else: destination.write_bytes(data)
        root=archive.infolist()[0].filename
        root_bytes=archive.read(root)
    # Preserve the animation data; repair an existing normal-map decode omission
    # in the animated source only. Verify all other authored USD text is unchanged.
    normal_fix=False
    if src.stem == 'neopjukAnimated':
        before=subprocess.check_output(['usdcat',str(folder/root)],text=True)
        start=before.index('def Shader "NormalTexture"')
        end=before.index('}',start)+1
        shader=before[start:end]
        corrected=shader.replace('uniform token info:id',
            'float4 inputs:scale = (2, 2, 2, 1)\n                float4 inputs:bias = (-1, -1, -1, 0)\n                uniform token info:id',1)
        text=before[:start]+corrected+before[end:]
        patch=folder/'normal-fix.usda';patch.write_text(text)
        subprocess.run(['usdcat',str(patch),'-o',str(folder/root)],check=True)
        after=subprocess.check_output(['usdcat',str(folder/root)],text=True)
        def outside_shader(value):
            a=value.index('def Shader "NormalTexture"');b=value.index('}',a)+1
            return value[:a]+value[b:]
        assert outside_shader(before)==outside_shader(after), 'Animation or scene data changed'
        normal_fix=True
    expected_scene_hash=hashlib.sha256((folder/root).read_bytes()).hexdigest()
    geometry_lod=src.stem in ['ponix','doni','ponixVsNeopjuk']
    if geometry_lod:
        metadata=subprocess.check_output(['usdcat',str(src.resolve()),'--layerMetadata'],text=True)
        metadata=metadata.rstrip();assert metadata.endswith(')')
        metadata=metadata[:-1]+f'    subLayers = [@{root}@]\n)\n'
        jobs.append(dict(source=str(src.resolve()),triangles=a.triangles,
            overlay=str(folder/'lod.usda'),metadata=metadata,stats=str(folder/'stats.json')))
    rows.append(dict(name=src.stem,originalBytes=src.stat().st_size,
        sourceSHA256=hashlib.sha256(src.read_bytes()).hexdigest(),textures=textures,
        geometryLOD=geometry_lod,folder=str(folder),root=root,
        originalSceneSHA256=hashlib.sha256(root_bytes).hexdigest(),
        expectedSceneSHA256=expected_scene_hash,normalMapCorrection=normal_fix))
if jobs:
    plan=work/'plan.json';plan.write_text(json.dumps(jobs))
    subprocess.run([a.blender,'--background','--factory-startup','--python',
        str(Path(__file__).with_name('character-lod-blender.py').resolve()),'--',str(plan)],check=True)
for row in rows:
    folder=Path(row.pop('folder'));root=row.pop('root')
    if row['geometryLOD']:
        subprocess.run(['usdcat','--flatten','--skipSourceFileComment','lod.usda','-o','lite.usdc'],cwd=folder,check=True)
        root='lite.usdc';row.update(json.loads((folder/'stats.json').read_text()))
    output=a.output/(row['name']+'-lite-v1.usdz')
    subprocess.run(['usdzip','--asset',root,str(output.resolve())],cwd=folder,check=True)
    subprocess.run(['usdcat','--loadOnly',str(output)],check=True)
    # Validate required storage and 64-byte payload alignment independently.
    with ZipFile(output) as archive, output.open('rb') as raw:
        for member in archive.infolist():
            assert member.compress_type==ZIP_STORED
            raw.seek(member.header_offset);header=raw.read(30)
            n,extra=struct.unpack_from('<HH',header,26)
            assert (member.header_offset+30+n+extra)%64==0
        if not row['geometryLOD']:
            assert hashlib.sha256(archive.read(archive.infolist()[0])).hexdigest()==row['expectedSceneSHA256'], 'Scene changed'
    check=subprocess.run(['usdchecker','--arkit',str(output)],capture_output=True,text=True)
    row['complianceExitCode']=check.returncode
    (a.output/(row['name']+'-validation.txt')).write_text(check.stdout+check.stderr)
    row['optimizedBytes']=output.stat().st_size
    row['sha256']=hashlib.sha256(output.read_bytes()).hexdigest()
    row['file']=output.name
    row['reductionPercent']=round((1-row['optimizedBytes']/row['originalBytes'])*100,1)
    print('RESULT '+json.dumps(row,ensure_ascii=False),flush=True)
(a.output/'manifest.json').write_text(json.dumps(dict(version=1,textureMaxDimension=a.texture_size,
    staticTriangleTarget=a.triangles,models=rows),ensure_ascii=False,indent=2)+'\n')
workspace.cleanup()
print('Temporary working files cleaned')
