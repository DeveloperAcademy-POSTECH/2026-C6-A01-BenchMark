"""Repair the editable face inside the STEP 3 raincoat."""
import argparse
import io
from pathlib import Path
import subprocess
from zipfile import ZipFile

import numpy as np
from PIL import Image

import seed_costume_geometry as geometry
from prepare_seed_costume_proposals import edited_mesh, hood_fit
from seed_costume_hood_interior import seal_hood_face
from seed_costume_original import FACE_ARRAY, filtered_mesh
from seed_costume_school_science import material_surface


LINING = 'RaincoatOpeningLining'
LINING_BITMAP = np.full((4, 4, 3), (233, 183, 38), dtype=np.uint8)
STEM_OFFSET = (-.018, -.052, .012)
SKIN_MAPS = tuple(f'Textures/Body{layer}.png' for layer in ('BaseColor', 'Normal', 'Roughness'))
CLOTH_MESHES = ('mesh1_001', 'InnerHoodmesh1_001', 'InnerCrown')
HEIGHTS = (.841, .865, .908, .957, 1.020, 1.094, 1.171, 1.223, 1.261, 1.270)
HALF_WIDTHS = (.035, .071, .130, .167, .190, .199, .173, .130, .076, .033)


def master_face():
    _, points, faces, uv = next(part for part in geometry.seed_data if part[0] == 'Body')

    def aperture(samples):
        x, y, z = samples.T
        width = np.interp(y, HEIGHTS, HALF_WIDTHS)
        # Continue the canonical cheek under the hood lip so the cut edge and
        # recessed seal stay behind fabric when viewed from the side.
        width += .042 * geometry.smoothstep((width - .045) / .085)
        return np.minimum.reduce((y - HEIGHTS[0], HEIGHTS[-1] - y, width - abs(x + .004), z - .018))

    normals, _ = geometry.normals_for(points, faces)
    attributes = np.concatenate((uv, normals[faces]), axis=-1)
    points, faces, clipped = geometry.clipped_surface(points, faces, attributes, aperture)
    uv, normals = clipped[..., :2], geometry.unit(clipped[..., 2:])
    sealed_points, sealed_faces, sealed_uv = seal_hood_face('raincoat', points, faces, uv)
    backing = np.any(sealed_faces >= len(points), axis=1)

    # Use the original rind normals at the rim. The backing must not blend
    # its normals or stretch its UVs over the visible face.
    visible = geometry.as_mesh('VisibleBody', points, faces, uv)
    _, area = geometry.normals_for(points, faces)
    corner_normals = geometry.float_array(normals[area > 1e-13].reshape(-1, 3))

    def preserve_normals(match):
        prefix, name, _, suffix = match.groups()
        if name == 'normals':
            return prefix[:-1] + corner_normals + suffix[1:]
        return match[0]

    visible = FACE_ARRAY.sub(preserve_normals, visible).replace('/mat0>', '/VisibleBodyMaterial>')
    back = geometry.as_mesh('FaceBacking', sealed_points, sealed_faces[backing], sealed_uv[backing])
    return visible + back.replace('/mat0>', '/FaceBackingMaterial>')


def clean_opening(points, faces, uv, texture):
    """Keep the fabric surface and isolate the triangles still showing baked skin."""
    x, y, z = points[faces].mean(axis=1).T
    cheek = (y > .844) & (y < 1.296) & (abs(x) < .254) & (z > -.078)
    crown = (y >= 1.296) & (y < 1.350) & (abs(x) < .140)
    samples = [uv.mean(axis=1)]
    for corner in range(3):
        samples.append(.68 * uv[:, corner] + .32 * samples[0])
    green = np.zeros(len(faces), dtype=bool)
    for sample in samples:
        red, green_channel, blue = geometry.sample(texture, sample).astype(np.int16).T
        green |= (green_channel > red + 2) & (green_channel > blue + 8)
    return (cheek | crown) & green


def mesh_block(text, prim):
    indentation = prim[1]
    start = text.index('\n' + indentation + '{', prim.start()) + len(indentation) + 2
    end = text.index('\n' + indentation + '}', start)
    return start, end, text[start:end]


def make_stage(text, texture, skin):
    prims = [prim for prim in geometry.prim_pattern.finditer(text) if prim[2] == 'Mesh']
    outfits = list(geometry.meshes(text, include_transform=True))
    edits, patches = [], []
    for prim, (name, points, faces, uv, transform) in zip(prims, outfits, strict=True):
        start, end, block = mesh_block(text, prim)
        if name == 'VisibleBody':
            edits.append((prim.start(), end + len(prim[1]) + 2, skin.rstrip()))
            continue
        if name not in CLOTH_MESHES:
            continue
        # The first card keeps the established raincoat silhouette. Start from
        # the stable base resource so regenerating it never consumes itself.
        fitted = points if name == 'InnerCrown' else hood_fit('raincoat', points, 0)
        if not np.array_equal(fitted, points):
            start, end, block = edited_mesh(text, prim, points, fitted, faces, transform)
        lining = clean_opening(points, faces, uv, texture)
        if lining.any():
            block = filtered_mesh(block, ~lining)
            inner = geometry.as_mesh('CleanOpening' + name, fitted, faces[lining], uv[lining])
            patches.append(inner.replace('/SeedCostume/Materials/mat0>', f'/SeedCostume/Materials/{LINING}>'))
        edits.append((start, end, block))
    for start, end, block in reversed(edits):
        text = text[:start] + block + text[end:]
    marker = '    def Scope "Materials"\n    {\n'
    if not patches or marker not in text:
        raise ValueError('Missing raincoat opening or materials')
    lining = material_surface(LINING, '(0.8148, 0.4735, 0.0194)', .83)
    backing = material_surface('FaceBackingMaterial', '(0.14, 0.25, 0.019)', .88)
    return text.replace(marker, ''.join(patches) + marker + lining + backing, 1)


def preview(text, bitmaps, master, key, directory):
    cloth, body = bitmaps
    render = []
    for name, points, faces, uv in geometry.meshes(text):
        bitmap = LINING_BITMAP if name.startswith('CleanOpening') else body if name == 'VisibleBody' else cloth
        if name == 'FaceBacking':
            bitmap = np.full((4, 4, 3), (103, 137, 38), dtype=np.uint8)
        render.append(([(name, points, faces, uv)], bitmap))
    for name, points, faces, uv in geometry.seed_data:
        if name not in ('LeftEye', 'RightEye', 'Mouth', 'Stem'):
            continue
        if name == 'Stem':
            points = points + STEM_OFFSET
        with master.open(f'Textures/{name}.png') as file:
            bitmap = np.asarray(Image.open(file).convert('RGB'))
        if name == 'FaceBacking':
            bitmap = np.full((4, 4, 3), (103, 137, 38), dtype=np.uint8)
        render.append(([(name, points, faces, uv)], bitmap))
    frame = geometry.raster(None, render, key, transparent_front=True)
    thumbnail = frame.crop((36, 14, 354, 532))
    thumbnail.thumbnail((150, 210))
    thumbnail.save(directory / f'{key}.png')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workspace', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--preview', action='store_true')
    args = parser.parse_args()
    resources = (args.workspace / 'apps/ios/OiDonation/Resources').resolve()
    output = args.output.resolve()
    if output.is_relative_to(resources):
        parser.error('output must be a staging directory')
    geometry.configure(resources, output / 'renders')
    if args.preview:
        subprocess.run(['/usr/bin/clang', '-O3', str(Path(__file__).with_name('raster.c')),
                        '-o', str(geometry.root / 'raster')], check=True, timeout=30)
    characters = resources / 'Characters'
    source = characters / 'seed-costume-raincoat.usdz'
    text = geometry.read_stage(source)
    with ZipFile(source) as reference, ZipFile(characters / 'SeedCucumberMaster.usdz') as master:
        maps = {name: reference.read(name) for name in reference.namelist()[1:]}
        cloth_map = next(name for name in maps if name.lower().endswith('albedo.png'))
        cloth = np.asarray(Image.open(io.BytesIO(maps[cloth_map])).convert('RGB'))
        skin = master_face()
        for name in SKIN_MAPS:
            maps[name] = master.read(name)
        body = np.asarray(Image.open(io.BytesIO(maps[SKIN_MAPS[0]])).convert('RGB'))
        key = 'seed-costume-raincoat-proposal-1'
        folder = output / key
        folder.mkdir(exist_ok=True)
        stage = make_stage(text, cloth, skin)
        (folder / f'{key}.usda').write_text(stage)
        for name, data in maps.items():
            path = folder / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        (folder / f'{key}.usdz').unlink(missing_ok=True)
        for command in (('usdcat', '-o', f'{key}.usdc', f'{key}.usda'),
                        ('usdzip', f'{key}.usdz', f'{key}.usdc', *maps),
                        ('usdchecker', '--strict', '--arkit', f'{key}.usdz')):
            subprocess.run(('/usr/bin/' + command[0], *command[1:]), cwd=folder, check=True, timeout=35)
        if args.preview:
            preview(stage, (cloth, body), master, key, folder)
        print(key, flush=True)


if __name__ == '__main__':
    main()
