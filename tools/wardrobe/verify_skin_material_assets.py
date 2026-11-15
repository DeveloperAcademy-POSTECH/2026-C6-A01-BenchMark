"""Check shipped skin packages against the reviewed manifest; standard library only."""
from pathlib import Path
import hashlib
import json
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'apps/ios/OiDonation/Resources/Wardrobe'
manifest = json.loads((ROOT / 'tools/wardrobe/skin-material-manifest.json').read_text())
expected = {f'wardrobe-{top}-{bottom}.usdz' for top in
            ('tshirt', 'hoodie', 'cardigan', 'postech') for bottom in ('shorts', 'long')}
assert len(manifest['models']) == 8
assert {m['file'] for m in manifest['models']} == expected
assert manifest['palette'] == 'fresh-cucumber-bright4'
assert manifest['baseRGB'] == [151, 211, 106] and manifest['stripeRGB'] == [55, 108, 60]
assert abs(manifest['roughness'] - 155 / 255) < 1e-6
assert manifest['metallic'] == manifest['clearcoat'] == 0
sha = lambda data: hashlib.sha256(data).hexdigest()
reference_digest = sha((ASSETS / manifest['reference']).read_bytes())
if reference_digest != manifest['referenceSHA256']:
    update = manifest['referenceAppearanceUpdate']
    assert update['sourceSHA256'] == manifest['referenceSHA256']
    reports = json.loads((ROOT / update['manifest']).read_text())
    record = next(r for r in reports if r['id'] == 'cat')
    assert record['sourceSHA256'] == manifest['referenceSHA256']
    assert record['outputSHA256'] == update['outputSHA256']
    if reference_digest != update['outputSHA256']:
        faces = json.loads((ROOT / 'tools/wardrobe/costume-face-cleanup-manifest.json').read_text())
        cleanup = next(r for r in faces if r['id'] == 'cat')
        assert cleanup['sourceSHA256'] == update['outputSHA256']
        assert cleanup['outputSHA256'] == reference_digest
    assert record['baseColor'] == '#97D36A' and record['stripeColor'] == '#376C3C'

seen_textures = set()
for model in manifest['models']:
    path = ASSETS / model['file']
    raw = path.read_bytes()
    assert sha(raw) == model['outputSHA256'], f'Update reviewed manifest for {path.name}'
    assert len(raw) == model['bytes']
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        for entry in archive.infolist():
            assert entry.compress_type == zipfile.ZIP_STORED
            name_length, extra_length = struct.unpack_from('<HH', raw, entry.header_offset + 26)
            assert (entry.header_offset + 30 + name_length + extra_length) % 64 == 0
            if Path(entry.filename).name.startswith('skin-fresh-cucumber-bright4-'):
                digest = sha(archive.read(entry))
                assert digest in {t['outputSHA256'] for t in manifest['textures'].values()}
                seen_textures.add(digest)
    if model['file'] == 'wardrobe-cardigan-shorts.usdz':
        fit = model['garmentFit']
        assert fit['outputSHA256'] == model['outputSHA256']
        assert not model['geometryUVsTransformsUnchanged']
        assert fit['shortsTopologyAndUVExactMatchToTshirt']
    else:
        assert model['geometryUVsTransformsUnchanged']
assert seen_textures == {t['outputSHA256'] for t in manifest['textures'].values()}
print('PASS: 8 approved skin packages, 5 palette textures, cat reference, and aligned USDZ packaging')
