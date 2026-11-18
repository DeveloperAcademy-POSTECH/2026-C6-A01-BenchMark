"""Bake front/back photo coordinates for the exact shipped seed cucumber tops.

Requires NumPy, Pillow and the macOS USD tools. No source USDZ, topology, UV,
normal or material is changed. Only the named fabric mesh receives a binding.

    python3 tools/wardrobe/seed_catalog/prepare_seed_top_photo_uv.py . OUTPUT
    python3 tools/wardrobe/seed_catalog/prepare_seed_top_photo_uv.py . OUTPUT --verify

OUTPUT can be a staging folder or apps/ios/OiDonation/Resources/WardrobePhotoUV.
The 2048x1024 photo atlas is transparent outside the user's image layers; the
baker composites it onto the copied original base-color image. Apply cloth tint
only to that base before compositing, then use a white material tint so photo
colors are preserved. Normal, roughness and metallic channels stay untouched.
"""
from argparse import ArgumentParser
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import zipfile
import zlib

import numpy as np
from PIL import Image

import seed_costume_geometry as geometry
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from photo_bake_geometry import bake_map, depth_sides, projection, raster_triangle


TOPS = {
    "tshirt": ("SeedCucumberWhiteTshirt", ["Top", "WhiteTshirt"]),
    "hoodie": ("SeedCucumberHoodie", ["Hoodie"]),
    "cardigan": ("SeedCucumberCardigan", ["Top", "cardigan_top_001"]),
    "postech": ("SeedCucumberPostechJacket", ["PostechJacket"]),
}
SIZE = 2048


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prim_block(stage, kind, name):
    matches = list(re.finditer(r'(?m)^( *)def ' + kind + ' "' + re.escape(name) + r'"[^\n]*\n', stage))
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one {kind} {name}")
    match = matches[0]
    indentation = match[1]
    start = stage.index('\n' + indentation + '{', match.start()) + len(indentation) + 2
    end = stage.index('\n' + indentation + '}', start)
    return stage[start:end]


def color_image(stage, mesh_name, source):
    mesh = prim_block(stage, 'Mesh', mesh_name)
    binding = re.search(r'rel material:binding = <([^>]+)>', mesh)
    if binding is None:
        raise ValueError(f"Missing material binding for {mesh_name}")
    material = prim_block(stage, 'Material', binding[1].rsplit('/', 1)[-1])
    # Only the bound fabric material is searched; visible skin has its own maps.
    candidates = re.findall(r'asset inputs:file = @([^@]+)@\s+token inputs:sourceColorSpace = "sRGB"', material)
    if len(candidates) != 1:
        raise ValueError(f"Expected one sRGB base-color image for {mesh_name}")
    name = candidates[0].removeprefix('./')
    if Path(name).is_absolute() or '..' in Path(name).parts:
        raise ValueError("Unsafe texture path")
    with zipfile.ZipFile(source) as archive:
        data = archive.read(name)
    image = Image.open(io.BytesIO(data))
    if image.format != 'PNG' or max(image.size) > SIZE:
        raise ValueError(f"Unsupported source texture {name}: {image.size}")
    return data


def guide_edges(points, faces, sides, regions):
    # Weld position-only seams for the guide, without changing the actual mesh.
    # A UV seam should not appear as an extra line inside the shirt silhouette.
    _, welded = np.unique(points.round(7), axis=0, return_inverse=True)
    edges = {}
    for face, side in zip(faces, sides):
        for a, b in zip(face, np.roll(face, -1)):
            key = tuple(sorted((int(welded[a]), int(welded[b]))))
            edges.setdefault(key, []).append((int(side), int(a), int(b)))
    guides = [[], []]
    for owners in edges.values():
        if len(owners) != 1 and len({owner[0] for owner in owners}) == 1:
            continue
        for side, a, b in owners:
            uv = projection(points[[a, b]], side, regions[side])
            uv[:, 0] = uv[:, 0] * 2 - side
            if not np.isfinite(uv).all() or np.any(uv < -1e-5) or np.any(uv > 1 + 1e-5):
                raise ValueError("Guide lies outside its full-square editor chart")
            guides[side].append(np.round(np.clip(uv, 0, 1), 6).tolist())
    if not all(guides):
        raise ValueError("Missing front or back guide")
    return guides


def chart_owners(uv, sides):
    owners = np.zeros((SIZE, SIZE), dtype=np.uint8)
    for triangle, side in zip(uv, sides):
        raster = raster_triangle(triangle, SIZE)
        if raster is not None:
            y, x, _ = raster
            owners[y, x] |= np.uint8(1 << side)
    return owners


def verify(source, output, top):
    name = f'photo-seed-{top}-top'
    manifest = json.loads((output / (name + '-bake.json')).read_text())
    _, path = TOPS[top]
    assert manifest['version'] == 1 and manifest['sourceSHA256'] == sha(source)
    assert len(manifest['bindings']) == 1
    binding = manifest['bindings'][0]
    assert binding['paths'] == [path] and binding['size'] == SIZE
    raw = zlib.decompress((output / binding['map']).read_bytes(), wbits=-15)
    assert len(raw) == SIZE * SIZE * 4
    mapping = np.frombuffer(raw, dtype='<u2').reshape(SIZE, SIZE, 2)
    empty = mapping[:, :, 0] == 65535
    assert np.array_equal(empty, mapping[:, :, 1] == 65535)
    assert np.all(mapping[~empty] <= 65534)
    front = int(np.sum(~empty & (mapping[:, :, 0] < 32767)))
    back = int(np.sum(~empty & (mapping[:, :, 0] >= 32767)))
    assert min(front, back) > 1000 and int(empty.sum()) > 1000
    stage = geometry.read_stage(source)
    _, points, faces, uv = next(mesh for mesh in geometry.meshes(stage) if mesh[0] == path[-1])
    owners = chart_owners(uv, depth_sides(points, faces))
    assert np.all(empty[owners == 3]), 'Shared front/back texels must keep the original cloth'
    data = color_image(stage, path[-1], source)
    assert (output / binding['baseImage']).read_bytes() == data
    for side in ('front', 'back'):
        edges = np.asarray(json.loads((output / (name + '-' + side + '.json')).read_text()))
        assert edges.ndim == 3 and edges.shape[1:] == (2, 2) and len(edges) > 0
        assert np.isfinite(edges).all() and np.all((edges >= 0) & (edges <= 1))
    return {'top': top, 'frontTexels': front, 'backTexels': back,
            'unmappedTexels': int(empty.sum()), 'sourceSHA256': sha(source),
            'sourceBaseColorBytesUnchanged': True}


def prepare(source, output, top):
    original_hash = sha(source)
    stage = geometry.read_stage(source)
    _, path = TOPS[top]
    name, points, faces, uv = next(mesh for mesh in geometry.meshes(stage) if mesh[0] == path[-1])
    assert np.isfinite(points).all() and np.isfinite(uv).all()
    assert faces.min() >= 0 and faces.max() < len(points)
    assert np.all((uv >= 0) & (uv <= 1))
    lower, upper = points.min(axis=0), points.max(axis=0)
    region = (float(lower[0]), float(upper[0]), float(lower[1]), float(upper[1]))
    regions = [region, region]
    sides = depth_sides(points, faces)
    mapping, stats = bake_map(points, faces, uv, sides, regions, size=SIZE)
    if stats['mappedPixels'] < 1000:
        raise ValueError(f"Missing printable geometry for {top}")
    # A few one-pixel UV seams belong to both faces. Keep the original cloth
    # there instead of transferring an image from one side onto the other.
    shared = chart_owners(uv, sides) == 3
    mapping[shared] = 65535
    stats['sharedFrontBackTexelsPreserved'] = int(shared.sum())
    stats['mappedPixels'] = int(np.sum(mapping[:, :, 0] != 65535))
    guides = guide_edges(points, faces, sides, regions)
    prefix = f'photo-seed-{top}-top'
    material_prefix = prefix + '-material-0'
    compressor = zlib.compressobj(level=9, wbits=-15)
    data = compressor.compress(mapping.tobytes()) + compressor.flush()
    (output / (material_prefix + '.uvmap')).write_bytes(data)
    base_name = ('photo-wardrobe-postech-long-top-material-0.png' if top == 'postech'
                 else material_prefix + '.png')
    base_data = color_image(stage, name, source)
    base_path = output / base_name
    # The seed jacket retains this exact original atlas. Reuse the existing
    # bundled image rather than shipping another 3.35 MiB copy.
    if top == 'postech' and base_path.exists():
        if base_path.read_bytes() != base_data:
            raise ValueError('The shared POSTECH base image no longer matches the seed jacket')
    else:
        base_path.write_bytes(base_data)
    for side, guide in zip(('front', 'back'), guides):
        (output / (prefix + '-' + side + '.json')).write_text(json.dumps(guide, separators=(',', ':')) + '\n')
    manifest = {'version': 1, 'sourceSHA256': original_hash,
                'bindings': [{'paths': [path], 'baseImage': base_name,
                              'map': material_prefix + '.uvmap', 'size': SIZE}]}
    (output / (prefix + '-bake.json')).write_text(json.dumps(manifest, separators=(',', ':')) + '\n')
    assert sha(source) == original_hash
    return {**stats, **verify(source, output, top)}


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument('workspace', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('tops', nargs='*', help='Selected tops; omit to process all four')
    parser.add_argument('--verify', action='store_true', help='Check existing assets without writing them')
    args = parser.parse_args()
    unknown = set(args.tops) - set(TOPS)
    if unknown:
        parser.error('Unknown tops: ' + ', '.join(sorted(unknown)))
    resources = args.workspace.resolve() / 'apps/ios/OiDonation/Resources/Characters'
    output = args.output.resolve()
    if not args.verify:
        output.mkdir(parents=True, exist_ok=True)
    for top in args.tops or TOPS:
        source = resources / (TOPS[top][0] + '.usdz')
        report = verify(source, output, top) if args.verify else prepare(source, output, top)
        print(json.dumps(report, sort_keys=True), flush=True)


if __name__ == '__main__':
    main()
