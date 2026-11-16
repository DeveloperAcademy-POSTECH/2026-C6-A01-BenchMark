"""Remove baked skin while retaining the source costume's authored outer surface."""
import io
import re
import subprocess
from textwrap import indent
from zipfile import ZipFile

import numpy as np
from PIL import Image

import seed_costume_geometry as geometry
from seed_costume_coverage import compact_skin, crop_body_maps, overlay_material


FACE_ARRAY = re.compile(
    r'(?m)^(?P<prefix> +\w+\[\] (?P<name>[\w:]+) = \[)(?P<values>[^\]]+)(?P<suffix>\](?: \(\n[^)]*\))?)'
)
ARRAY_VALUE = re.compile(r'\([^()]*\)|[^,\s]+')


def filtered_mesh(block, keep):
    """Retain original points, normals and authored per-corner attributes."""
    corners = np.repeat(keep, 3)

    def filtered_array(match):
        prefix, name, values, suffix = match.groups()
        if name == 'faceVertexCounts' or 'interpolation = "uniform"' in suffix:
            selected = keep
        elif (name == 'faceVertexIndices' or 'interpolation = "faceVarying"' in suffix
              or name.endswith(':indices')):
            selected = corners
        else:
            return match[0]
        entries = ARRAY_VALUE.findall(values)
        if len(entries) != len(selected):
            raise ValueError(f'Unexpected topology attribute {name}: {len(entries)} entries')
        return prefix + ', '.join(entry for entry, keep_entry in zip(entries, selected) if keep_entry) + suffix

    return FACE_ARRAY.sub(filtered_array, block)


def extract_stage(source, texture, mask):
    objects = list(geometry.meshes(source))
    cut_objects = []
    edits = []
    mesh_prims = [prim for prim in geometry.prim_pattern.finditer(source) if prim[2] == 'Mesh']
    for prim, (name, points, faces, uv) in zip(mesh_prims, objects, strict=True):
        if prim[3] != name:
            raise ValueError(f'Unexpected mesh {name}')
        centers = points[faces].mean(axis=1)
        rgb = geometry.sample(texture, uv.mean(axis=1)).astype(float)
        keep = mask(centers, geometry.skin_color(texture, uv), rgb, name)
        if not np.any(keep):
            raise ValueError(f'Skin extraction removed every triangle from {name}')
        cut_objects.append((name, points, faces[keep], uv[keep]))
        if np.all(keep):
            continue
        indentation = prim[1]
        start = source.index('\n' + indentation + '{', prim.start()) + len(indentation) + 2
        end = source.index('\n' + indentation + '}', start)
        block = filtered_mesh(source[start:end], keep)
        edits.append((start, end, block))
    for start, end, block in reversed(edits):
        source = source[:start] + block + source[end:]

    root = re.search(r'(?m)^def Xform "([^"]+)"', source)
    if root is None:
        raise ValueError('Missing original costume root')
    legacy = source[root.start():].rstrip()
    # Render the asset under the editor's own camera and environment.
    legacy = re.sub(r'(?ms)^    def (?:Camera|\w+Light) "[^\"]*"[^\n]*\n    \{.*?^    \}\n', '', legacy)
    legacy_path = '/SeedCostume/LegacyOutfit'
    legacy = legacy.replace(f'def Xform "{root[1]}"', 'def Xform "LegacyOutfit"', 1)
    legacy = legacy.replace(f'</{root[1]}/', f'<{legacy_path}/')
    return indent(legacy, '    '), legacy_path, objects, cut_objects


def source_face_depth(id, query):
    """Measure the legacy shell depth at the exposed face to keep the rim clear."""
    stage, _ = geometry.load(id)
    step = .0025
    lower = np.array([-.28, .79])
    dims = np.array([225, 215])
    depth = np.full(tuple(dims), -np.inf)
    for _, points, faces, _ in geometry.meshes(stage):
        triangles = points[faces]
        eligible = (triangles[:, :, 2].max(axis=1) > 0)
        eligible &= np.all(triangles[:, :, :2].max(axis=1) >= lower, axis=1)
        eligible &= np.all(triangles[:, :, :2].min(axis=1) <= lower + step*(dims-1), axis=1)
        for triangle in triangles[eligible]:
            a, b, c = triangle
            mid = (triangle[:, :2] - lower) / step
            lo = np.maximum(0, np.ceil(mid.min(axis=0)).astype(int))
            hi = np.minimum(dims - 1, np.floor(mid.max(axis=0)).astype(int))
            if np.any(hi < lo):
                continue
            u,v = (a-c)[:2], (b-c)[:2]
            det = u[0]*v[1] - u[1]*v[0]
            if abs(det) < 1e-12:
                continue
            row = np.arange(lo[0], hi[0]+1)
            col = np.arange(lo[1], hi[1]+1)
            x = (row * step + lower[0] - c[0])[:, None]
            y = (col * step + lower[1] - c[1])[None, :]
            r = (x*v[1]-y*v[0])/det
            s = (u[0]*y-u[1]*x)/det
            inside = (r>=0)&(s>=0)&(r+s<=1)
            z = np.where(inside, c[2]+r*(a[2]-c[2])+s*(b[2]-c[2]), -np.inf)
            dest = depth[lo[0]:hi[0]+1, lo[1]:hi[1]+1]
            np.maximum(dest,z,out=dest)
    tx, ty = np.clip(np.rint((query[:, :2]-lower)/step).astype(int), 0, dims-1).T
    values=depth[tx,ty]
    return np.where(np.isfinite(values), values, query[:,2])


def prepare_original_costume(id, output, mask, hidden, skin_sections, *, extras=(),
                             preview_offsets=None, preview=False):
    extras = tuple(extras)
    preview_offsets = preview_offsets or {}
    source, texture = geometry.load(id)
    legacy, legacy_path, original, costume = extract_stage(source, texture, mask)
    output.mkdir(parents=True, exist_ok=True)
    texture_entries = list(dict.fromkeys(path.removeprefix('./') for path in geometry.archive.findall(legacy)))
    legacy_file = geometry.assets / f'Wardrobe/wardrobe-costume-{id}.usdz'
    with ZipFile(legacy_file) as archive:
        for entry in texture_entries:
            target = output / entry
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(entry))

    extra_meshes = [geometry.as_mesh(*mesh).replace('/SeedCostume/Materials/mat0>',
                    f'{legacy_path}/_materials/mat0>') for mesh in extras]
    new_materials, preview_sections = [], []
    master_file = geometry.assets / 'Characters/SeedCucumberMaster.usdz'
    master = geometry.read_stage(master_file)
    with ZipFile(master_file) as archive:
        for part, name, points, faces, uv in skin_sections:
            if not len(faces):
                raise ValueError(f'Missing exposed skin for {id} {part}')
            material = overlay_material(master, name + 'Material', part)
            entries = list(dict.fromkeys(geometry.archive.findall(material)))
            for entry in entries:
                (output / entry).parent.mkdir(parents=True, exist_ok=True)
            if part == 'Body':
                uv = crop_body_maps(archive, output, uv, entries)
            else:
                for entry in entries:
                    (output / entry).write_bytes(archive.read(entry))
            extra_meshes.append(compact_skin(name, points, faces, uv))
            new_materials.append(material)
            preview_sections.append((part, name, points, faces, uv))
            texture_entries.extend(entries)

        if preview:
            geometry.raster(original, texture, id + '-legacy')
            packages = [([*costume, *extras], texture)]
            master_sections = [(name, name, points, faces, uv) for name, points, faces, uv in geometry.seed_data
                               if name not in hidden]
            for part, name, points, faces, uv in [*master_sections, *preview_sections]:
                suffix = 'BodyBaseColor' if part == 'Body' else part
                entry = f'Textures/{suffix}.png'
                if part == 'Body' and name != part:
                    base = Image.open(output / entry)
                else:
                    base = Image.open(io.BytesIO(archive.read(entry)))
                with base:
                    image = np.asarray(base.convert('RGB'))
                offset = preview_offsets.get(part)
                if offset is not None:
                    points = points + np.asarray(offset)
                packages.append(([(name, points, faces, uv)], image))
            geometry.raster(None, packages, id + '-original-fit')

    basename = 'seed-costume-' + id
    text = '#usda 1.0\n(\n    defaultPrim = "SeedCostume"\n    metersPerUnit = 1\n    upAxis = "Y"\n)\n'
    text += 'def Xform "SeedCostume"\n{\n' + legacy + '\n' + ''.join(extra_meshes)
    if new_materials:
        text += '    def Scope "Materials"\n    {\n' + ''.join(new_materials) + '    }\n'
    (output / f'{basename}.usda').write_text(text + '}\n')
    package = output / f'{basename}.usdz'
    package.unlink(missing_ok=True)
    for command in (
        ('/usr/bin/usdcat', '-o', f'{basename}.usdc', f'{basename}.usda'),
        ('/usr/bin/usdzip', package.name, f'{basename}.usdc', *dict.fromkeys(texture_entries)),
        ('/usr/bin/usdchecker', '--strict', '--arkit', package.name),
    ):
        subprocess.run(command, cwd=output, check=True, timeout=25)
    print(id, 'source triangles', [len(mesh[2]) for mesh in original],
          'retained triangles', [len(mesh[2]) for mesh in costume], flush=True)
