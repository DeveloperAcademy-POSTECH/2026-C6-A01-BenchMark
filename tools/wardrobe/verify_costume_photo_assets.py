"""Validate shipped bake assets against the exact USDZ version. Python standard library only."""
from pathlib import Path
import hashlib, json, struct, zlib
root=Path(__file__).resolve().parents[2]
resources=root/'apps/ios/OiDonation/Resources'
records=json.loads((root/'tools/wardrobe/costume-photo-manifest.json').read_text())
assert len(records)==19
size=0
for record in records:
    name=record['id']; model=name.removeprefix('photo-').removesuffix('-top')
    source=resources/'Wardrobe'/(model+'.usdz')
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    assert digest==record['sourceSHA256'], f'Regenerate mapping after changing {model}'
    metadata=json.loads((resources/'WardrobePhotoUV'/(name+'-bake.json')).read_text())
    assert metadata['version']==1 and metadata['sourceSHA256']==digest
    front=back=protected=0
    for binding in metadata['bindings']:
        assert binding['size']==2048 and binding['paths']
        only_back=any('RestoredRearFabric' in path for path in binding['paths'])
        assert not any('CenteredTail' in path for path in binding['paths'])
        data=(resources/'WardrobePhotoUV'/binding['map']).read_bytes();size+=len(data)
        raw=zlib.decompress(data,wbits=-15)
        assert len(raw)==binding['size']*binding['size']*4
        for x,y in struct.iter_unpack('<HH',raw):
            if x==65535: assert y==65535;protected+=1
            else:
                assert y<=65534
                if x<32767:
                    assert not only_back, 'Rear repair cloth must not use the front photo'
                    front+=1
                else: back+=1
        base=resources/'WardrobePhotoUV'/binding['baseImage'];assert base.is_file();size+=base.stat().st_size
    assert min(front,back)>1000 and protected>1000
    for side in ['front','back']:
        edges=json.loads((resources/'WardrobePhotoUV'/(name+'-'+side+'.json')).read_text())
        assert edges and all(len(edge)==2 and all(len(p)==2 for p in edge) for edge in edges)
    assert not (resources/'WardrobePhotoUV'/(name+'.usdz')).exists(), 'Do not ship the old offset overlay'
print(f'PASS: {len(records)} source hashes, UV maps, protected texels and guides; {size/1024/1024:.2f} MiB bake data/base images')

layouts=json.loads((resources/'WardrobePhotoUV/photo-print-frames.json').read_text())
expected={r['id'] for r in records} | {p.stem for p in (resources/'WardrobePhotoUV').glob('*.usdz')}
assert set(layouts)==expected
for name,layout in layouts.items():
    plain=resources/'WardrobePhotoUV'/(name+'.usdz')
    source=plain if plain.exists() else resources/'Wardrobe'/(name.removeprefix('photo-').removesuffix('-top')+'.usdz')
    assert hashlib.sha256(source.read_bytes()).hexdigest()==layout['sourceSHA256'], f'Regenerate print frame for {name}'
    for side in ['front','back']:
        f=layout[side]
        assert 0<f['x']<f['x']+f['width']<1 and 0<f['y']<f['y']+f['height']<1
        assert 0<f['radius']<min(f['width'],f['height'])/2
print(f'PASS: {len(layouts)} bounded rounded front/back print frames and source hashes')
