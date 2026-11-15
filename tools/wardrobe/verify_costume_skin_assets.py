"""Validate the shipped 17-costume skin assets, budgets and appearance records."""
from pathlib import Path
import hashlib,json,struct,zipfile
ROOT=Path(__file__).resolve().parents[2]
RESOURCES=ROOT/'apps/ios/OiDonation/Resources'
manifest=json.loads((ROOT/'tools/wardrobe/mobile-costumes-manifest.json').read_text())
expected={'dinosaur','raincoat','bee','cat','astronaut','scientist','cat-bear','postech-selfie','baseball','cowboy','farmer','sportswear','martial-arts','school-uniform','school-uniform-trousers','astronaut-navy','scientist-goggles'}
assert {c['id'] for c in manifest['costumes']}==expected
assert len(manifest['costumes'])==17
sha=lambda b:hashlib.sha256(b).hexdigest()

def png_size(data):
    assert data[:8]==b'\x89PNG\r\n\x1a\n'
    return struct.unpack_from('>II',data,16)

for costume in manifest['costumes']:
    name=costume['id'];path=RESOURCES/'Wardrobe'/f'wardrobe-costume-{name}.usdz';raw=path.read_bytes()
    assert sha(raw)==costume['sha256'],name
    assert len(raw)==costume['bytes'] and len(raw)<12*1024*1024,name
    assert abs(costume['heightMeters']-1.5)<.01 and abs(costume['groundMeters'])<.01,name
    assert costume['skinRepair']['palette']=='fresh-cucumber-bright4',name
    eyes=costume.get('faceCleanup',costume.get('eyeRefinement',costume['skinRepair']))
    assert eyes['eyeColor']=='#0C0C0C',name
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        sizes=[]
        for item in archive.infolist():
            assert not Path(item.filename).is_absolute() and '..' not in Path(item.filename).parts
            assert item.compress_type==zipfile.ZIP_STORED
            a,b=struct.unpack_from('<HH',raw,item.header_offset+26)
            assert (item.header_offset+30+a+b)%64==0
            if item.filename.endswith('.png'):
                size=png_size(archive.read(item));sizes.extend(size)
                assert max(size)<=2048,(name,item.filename,size)
                if any(channel in item.filename.lower() for channel in ['normal','roughness','metallic']):
                    assert max(size)<=1024,(name,item.filename,size)
        assert max(sizes)==costume['maxTextureDimension'],name
    assert png_size((RESOURCES/'WardrobeThumbnails'/f'oi-costume-{name}.png').read_bytes())==(192,256),name
for record in json.loads((ROOT/'tools/wardrobe/remaining-costume-skin-repair-manifest.json').read_text()):
    assert record['baseColor']=='#97D36A' and record['stripeColor']=='#376C3C'
    assert record['mouthColor']=='#20452A' and record['eyeColor']=='#0C0C0C'
    assert abs(record['roughness']-155/255)<1e-6 and record['metallic']==0
    assert record['geometryUVsTransformsBindingsUnchanged'] and record['clothingNormalsUnchanged']
    assert record['outsideSkinColorMaxError']<=1/255+1e-6
    current=next(c for c in manifest['costumes'] if c['id']==record['id'])
    assert record['outputSHA256']==current.get('faceCleanup',{}).get('sourceSHA256',current['sha256'])
config=json.loads((ROOT/'tools/wardrobe/costume-face-cleanup-config.json').read_text())
assert set(config['models'])==expected and config['cleanupVersion']==4
assert config['baseRGB']==[151,211,106] and config['eyeRGB']==[12,12,12] and config['mouthRGB']==[32,69,42]
assert sha((ROOT/'tools/wardrobe/costume-face-fields.npz').read_bytes())==config['fieldsSHA256']
face_records=json.loads((ROOT/'tools/wardrobe/costume-face-cleanup-manifest.json').read_text())
assert len(face_records)==17 and {r['id'] for r in face_records}==expected
for record in face_records:
    current=next(c for c in manifest['costumes'] if c['id']==record['id'])
    assert record['outputSHA256']==current['sha256']
    assert record['sourceSHA256']==config['models'][record['id']]['sourceSHA256']
    assert record['sourceRevision']==config['sourceRevision']
    assert record['fieldsSHA256']==config['fieldsSHA256']
    assert record['cleanupVersion']==4 and record['sharedUVConflictsGuarded']
    assert record['geometryUVsNormalsBindingsUnchanged'] and record['otherMaterialChannelsUnchanged']
    assert record['outsideFaceMaxError']<=1/255+1e-6
    gates=config['models'][record['id']].get('eyeDepthGates',{})
    assert set(record.get('eyeDepthGates',{}))==set(gates)
    for key,settings in gates.items():
        assert all(record['eyeDepthGates'][key][k]==v for k,v in settings.items())
        assert record['eyeDepthGates'][key]['peakZ']>0
print('PASS: 17 costume hashes, palette/eye records, 150cm bounds, PNG sizes, thumbnails, 12MiB budgets and aligned packages')

proofs=json.loads((ROOT/'tools/wardrobe/costume-face-review-manifest.json').read_text())
assert len(proofs)==17 and {p['id'] for p in proofs}==expected
for proof in proofs:
    current=next(c for c in manifest['costumes'] if c['id']==proof['id'])
    assert proof['sourceSHA256']==current['sha256']
    for kind in ['lit','albedo']:
        assert sha((ROOT/proof[kind]['path']).read_bytes())==proof[kind]['sha256']
print('PASS: 17 paired review renders match the shipped model hashes')
