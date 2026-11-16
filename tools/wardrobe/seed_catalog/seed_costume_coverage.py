"""Bake only the seed surfaces that remain visible through each full costume."""
import re
import zipfile

import numpy as np
from PIL import Image

import seed_costume_geometry as geometry
from seed_costume_extras import package_stage

def overlay_material(source, name, part):
    start = re.search(r'(?m)^( +)def Material "' + re.escape(part) + r'"\n', source)
    if start is None:
        raise ValueError(f"missing master material {part}")
    indent = start[1]
    end = source.index("\n" + indent + "}", start.end()) + len(indent) + 2
    material = source[start.start():end]
    material = material.replace('def Material "' + part + '"', 'def Material "' + name + '"')
    material = material.replace("/Cucumber/Materials/" + part, "/SeedCostume/Materials/" + name)
    material = re.sub(r"@(?:[^@]*\[)?(?:\./)?(Textures/[^@\]]+)(?:\])?@", r"@\1@", material)
    return material + "\n"


def compact_skin(label, points, faces, uv):
    """Keep the original indexed texture coordinates for the partial master."""
    used, indices = np.unique(faces, return_inverse=True)
    corner_indices = indices.reshape(-1)
    indexed_uv = np.empty((len(used), 2), dtype=np.float64)
    indexed_uv[corner_indices] = uv.reshape(-1, 2)
    if not np.array_equal(indexed_uv[corner_indices], uv.reshape(-1, 2)):
        return geometry.as_mesh(label, points, faces, uv).replace("/mat0>", f"/{label}Material>")
    normals, area = geometry.normals_for(points, faces)
    indices = indices.reshape(-1, 3)[area > 1e-13].reshape(-1)
    points = points[used]
    return f'''    def Mesh "{label}" (
        prepend apiSchemas = ["MaterialBindingAPI"]
    )
    {{
        uniform bool doubleSided = true
        uniform token subdivisionScheme = "none"
        rel material:binding = </SeedCostume/Materials/{label}Material>
        float3[] extent = {geometry.float_array([points.min(axis=0), points.max(axis=0)])}
        point3f[] points = {geometry.float_array(points)}
        int[] faceVertexCounts = [{", ".join(["3"] * (len(indices) // 3))}]
        int[] faceVertexIndices = [{", ".join(map(str, indices))}]
        normal3f[] normals = {geometry.float_array(normals[used])} (
            interpolation = "vertex"
        )
        texCoord2f[] primvars:st = {geometry.float_array(indexed_uv)} (
            interpolation = "vertex"
        )
    }}
'''


def crop_body_maps(source, output, uv, entries):
    """Use the original texels and remap the visible face into a padded UV crop."""
    with source.open(entries[0]) as file:
        width, height = Image.open(file).size
    low, high = uv.min(axis=(0, 1)), uv.max(axis=(0, 1))
    box = (
        max(0, int(np.floor(low[0] * width)) - 8),
        max(0, int(np.floor((1 - high[1]) * height)) - 8),
        min(width, int(np.ceil(high[0] * width)) + 8),
        min(height, int(np.ceil((1 - low[1]) * height)) + 8),
    )
    for entry in entries:
        with source.open(entry) as file:
            im = Image.open(file)
            if im.size != (width, height):
                raise ValueError("Body material maps must share dimensions")
            im.crop(box).save(output / entry)
    remapped = uv.copy()
    x0, y0, x1, y1 = box
    remapped[..., 0] = (uv[..., 0] * width - x0) / (x1 - x0)
    remapped[..., 1] = 1 - ((1 - uv[..., 1]) * height - y0) / (y1 - y0)
    return remapped


def bee_hood_lining(costume):
    """Give the inside of the cut hood its own inward-facing fabric."""
    lining = []
    for name, points, faces, uv in costume:
        x, y, z = points[faces].mean(axis=1).T
        sides = (abs(x) > .09) & (z < .12) & (y > .76) & (y < 1.30)
        if np.any(sides):
            normals, _ = geometry.normals_for(points, faces)
            inner = points - .0006 * normals
            lining.append(("HoodLining" + name, inner, faces[sides, ::-1], uv[sides, ::-1]))
    return lining


def add_scientist_body(output):
    name = "seed-costume-scientist"
    stage_file = output / (name + ".usda")
    stage = stage_file.read_text()
    master_file = geometry.assets / "Characters/SeedCucumberMaster.usdz"
    master = geometry.read_stage(master_file)
    material_scope = '    def Scope "Materials"\n    {\n'
    textures = [entry.removeprefix("./") for entry in geometry.archive.findall(stage)]
    _, points, faces, uv = next(part for part in geometry.seed_data if part[0] == "Body")
    sample = points[faces].mean(axis=1)
    visible = (sample[:, 1] >= .76) & (sample[:, 1] <= 1.50) & (sample[:, 2] >= -1)
    material = overlay_material(master, "VisibleBodyMaterial", "Body")
    entries = list(dict.fromkeys(geometry.archive.findall(material)))
    with zipfile.ZipFile(master_file) as source:
        (output / "Textures").mkdir(exist_ok=True)
        remapped = crop_body_maps(source, output, uv[visible], entries)
    mesh = compact_skin("VisibleBody", points, faces[visible], remapped)
    stage_file.write_text(stage.replace(material_scope, mesh + material_scope + material, 1))
    package_stage(output, name, textures + entries)
