"""Generate five STEP 3 raincoats with the editable seed's original face."""
import argparse
import io
from pathlib import Path
import subprocess
from zipfile import ZipFile

import numpy as np
from PIL import Image

import seed_costume_geometry as geometry
from prepare_seed_costume_proposals import edited_mesh, hood_fit
from seed_costume_coverage import compact_skin, crop_body_maps
from seed_costume_hood_interior import seal_hood_face
from seed_costume_original import filtered_mesh
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
        return np.minimum.reduce((y - HEIGHTS[0], HEIGHTS[-1] - y, width - abs(x + .004), z - .072))

    return seal_hood_face('raincoat', *geometry.clipped_surface(points, faces, uv, aperture))


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


def shape(points, number):
    if number == 1:
        return points
    x, y, z = points.T
    smooth = geometry.smoothstep
    height = smooth((y - .844) / .140)
    ahead = smooth((z - .025) / .105)
    rear = smooth((-z - .011) / .120)
    crown = smooth((y - 1.080) / .124) * (1 - smooth((y - 1.317) / .074))
    seat = smooth((np.hypot(x - .005, z - .033) - .056) / .080)
    fitted = points.copy()
    if number == 2:
        # A forward bill directs rain away while keeping the neutral opening below.
        fitted[:, 2] += .080 * crown * ahead * seat
        fitted[:, 0] += .137 * x * crown * ahead
        fitted[:, 1] += .019 * crown * ahead * seat
    elif number == 3:
        # The deeper rounded back keeps the same front lip.
        fitted[:, 2] -= .064 * height * rear
        fitted[:, 0] += .112 * x * height * (1 - .86 * ahead)
        fitted[:, 1] += .033 * crown * seat * (1 - ahead)
    elif number == 4:
        # The low, wide hood adds room beside the face.
        fitted[:, 0] += .158 * x * height * (.77 + .23 * ahead)
        fitted[:, 1] -= .026 * crown * seat
        fitted[:, 2] += .025 * crown * ahead
    else:
        # A higher taper at the crown keeps the rear silhouette compact.
        fitted[:, 0] -= .108 * x * height * (1 - .94 * ahead)
        fitted[:, 1] += .047 * crown * seat
        fitted[:, 2] += height * (.017 * ahead + .027 * rear)
    return fitted


def mesh_block(text, prim):
    indentation = prim[1]
    start = text.index('\n' + indentation + '{', prim.start()) + len(indentation) + 2
    end = text.index('\n' + indentation + '}', start)
    return start, end, text[start:end]


def make_stage(text, texture, skin, number):
    prims = [prim for prim in geometry.prim_pattern.finditer(text) if prim[2] == 'Mesh']
    outfits = list(geometry.meshes(text, include_transform=True))
    edits, patches = [], []
    for prim, (name, points, faces, uv, transform) in zip(prims, outfits, strict=True):
        start, end, block = mesh_block(text, prim)
        if name == 'VisibleBody':
            body = compact_skin(name, *skin).rstrip()
            edits.append((prim.start(), end + len(prim[1]) + 2, body))
            continue
        if name not in CLOTH_MESHES:
            continue
        # The first card keeps the established raincoat silhouette. Start from
        # the stable base resource so regenerating it never consumes itself.
        baseline = points if name == 'InnerCrown' else hood_fit('raincoat', points, 0)
        fitted = shape(baseline, number)
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
    return text.replace(marker, ''.join(patches) + marker + lining, 1)


def preview(text, bitmaps, master, key, directory):
    cloth, body = bitmaps
    render = []
    for name, points, faces, uv in geometry.meshes(text):
        bitmap = LINING_BITMAP if name.startswith('CleanOpening') else body if name == 'VisibleBody' else cloth
        render.append(([(name, points, faces, uv)], bitmap))
    for name, points, faces, uv in geometry.seed_data:
        if name not in ('LeftEye', 'RightEye', 'Mouth', 'Stem'):
            continue
        if name == 'Stem':
            points = points + STEM_OFFSET
        with master.open(f'Textures/{name}.png') as file:
            bitmap = np.asarray(Image.open(file).convert('RGB'))
        render.append(([(name, points, faces, uv)], bitmap))
    geometry.raster(None, render, key)
    with Image.open(geometry.root / f'{key}-0.ppm') as frame:
        thumbnail = frame.crop((36, 14, 354, 532))
        thumbnail.thumbnail((150, 210))
        thumbnail.save(directory / f'{key}.jpg', quality=91)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workspace', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--proposal', choices=range(1, 6), type=int, action='append')
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
        face_points, face_faces, face_uv = master_face()
        skin_folder = output / 'skin'
        (skin_folder / 'Textures').mkdir(parents=True, exist_ok=True)
        face_uv = crop_body_maps(master, skin_folder, face_uv, SKIN_MAPS)
        for name in SKIN_MAPS:
            maps[name] = (skin_folder / name).read_bytes()
        body = np.asarray(Image.open(io.BytesIO(maps[SKIN_MAPS[0]])).convert('RGB'))
        for number in args.proposal or range(1, 6):
            key = f'seed-costume-raincoat-proposal-{number}'
            folder = output / key
            folder.mkdir(exist_ok=True)
            stage = make_stage(text, cloth, (face_points, face_faces, face_uv), number)
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
