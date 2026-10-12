"""Validate embedded GLB resources and animation/skin integrity without a GPU."""
import hashlib
import json
import pathlib
import struct

root = pathlib.Path(__file__).resolve().parents[1] / 'app/src/main/assets/models'
report = json.loads((root / 'conversion.json').read_text())
for entry in report:
    data = (root / (entry['name'] + '.glb')).read_bytes()
    magic, version, length = struct.unpack_from('<III', data)
    assert magic == 0x46546C67 and version == 2 and length == len(data)
    assert hashlib.sha256(data).hexdigest() == entry['glb_sha256']
    json_length, json_type = struct.unpack_from('<II', data, 12)
    assert json_type == 0x4E4F534A
    doc = json.loads(data[20:20 + json_length])
    assert doc.get('meshes') and doc.get('materials')
    assert all('uri' not in image for image in doc.get('images', [])), 'External image reference'
    assert all('uri' not in buffer for buffer in doc['buffers']), 'External buffer reference'
    triangles = sum(doc['accessors'][p['indices']]['count'] // 3
                    for mesh in doc['meshes'] for p in mesh['primitives'] if 'indices' in p)
    if entry['name'] == 'neopjukAnimated':
        assert doc.get('skins'), 'Missing skeleton'
        assert doc.get('animations'), 'Missing animation'
        assert all(animation['channels'] and animation['samplers'] for animation in doc['animations'])
        for animation in doc['animations']:
            for sampler in animation['samplers']:
                times = doc['accessors'][sampler['input']]
                assert times['max'][0] > times['min'][0], 'Zero-duration animation'
    print(f"{entry['name']}: {len(data)} bytes, {triangles} triangles, "
          f"{len(doc.get('skins', []))} skins, {len(doc.get('animations', []))} animations")
