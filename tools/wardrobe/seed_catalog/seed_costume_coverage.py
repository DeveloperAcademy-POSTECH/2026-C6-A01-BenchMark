"""Bake only the seed surfaces that remain visible through each full costume."""
import io
import re
import zipfile

import numpy as np
from PIL import Image, ImageFilter

import seed_costume_geometry as geometry
from seed_costume_extras import package_stage
from seed_costume_hoods import colors, options
from seed_costume_school_science import material_surface

CUTS = {
    "scientist": {"Body": (.76, 1.50, -1)},
    "bee": {"Body": (.77, 1.310, -.045)},
    "raincoat": {"Body": (.770, 1.324, -.044),
                 "LeftLeg": (.178, .269, -1), "RightLeg": (.178, .269, -1)},
    "cat": {"Body": (.789, 1.300, -.048), "LeftArm": (0, .623, -1),
            "RightArm": (0, .623, -1), "LeftLeg": (0, .083, -1), "RightLeg": (0, .083, -1)},
    "cat-bear": {"Body": (.789, 1.301, -.048), "LeftArm": (0, .595, -1),
                 "RightArm": (0, .593, -1), "LeftLeg": (0, .113, -1), "RightLeg": (0, .113, -1)},
}

# Use the original pose and outfit fit; the removal happens under the material,
# so the player's visible face panel and palm meshes stay as authored.
def visible_skin(id):
    parts = CUTS[id]
    for part, points, faces, uv in geometry.seed_data:
        if part not in parts:
            continue
        y0, y1, front = parts[part]
        sample = points[faces].mean(axis=1)
        visible = (sample[:, 1] >= y0) & (sample[:, 1] <= y1) & (sample[:, 2] >= front)
        if id == "cat-bear" and part == "RightArm":
            # The hand on the teddy bear is a copy of the master palm, not
            # the baked hand or a green fragment of the torso behind the prop.
            points = points.copy()
            pivot = np.array((.318, .551, .033))
            points = pivot + .88 * (points - pivot)
            points += np.array((-.108, .080, .227))
        yield part, "Visible" + part, points, faces[visible], uv[visible]


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


def bee_crown():
    """Bridge the original crown opening to the base of the seed stem."""
    segments = 48
    points = [[-.009, 1.378, .004]]
    faces = []
    angle = np.arange(segments) * (2 * np.pi / segments)
    for row, radius in enumerate((.21, .42, .64, .83, 1.)):
        x = -.009 + radius * .142 * np.cos(angle)
        z = .004 + radius * .130 * np.sin(angle)
        y = 1.378 - (.051 + .009 * np.sin(angle)) * radius ** 1.8
        points.extend(np.column_stack((x, y, z)).tolist())
        for column in range(segments):
            i = 1 + row * segments + column
            j = 1 + row * segments + (column + 1) % segments
            if row == 0:
                faces.append((0, j, i))
            else:
                faces.extend(((i - segments, j, i), (i - segments, j - segments, j)))
    return "CrownInset", np.asarray(points), np.asarray(faces), np.zeros((len(faces), 3, 2))


def cat_cuff_lining(side):
    """Close the old sleeve openings behind the unchanged master paws."""
    angles = np.linspace(0, 2 * np.pi, 40, endpoint=False)
    points = [(side * .222, .595, .080)]
    points.extend(np.column_stack((
        np.full(len(angles), side * .253),
        .595 + .047 * np.cos(angles),
        .080 + .048 * np.sin(angles),
    )))
    indices = np.arange(len(angles)) + 1
    edges = np.column_stack((np.zeros_like(indices), indices, np.roll(indices, -1)))
    if side < 0:
        edges = edges[:, ::-1]
    label = "LeftCuffLining" if side < 0 else "RightCuffLining"
    return label, np.asarray(points), edges, np.zeros((len(edges), 3, 2))


def trim_old_face(mask, id):
    if id == "bee":
        return mask

    def selection(points, green, rgb, name):
        x, y, z = points.T
        c = (x / .090) ** 2 + ((y - 1.058) / .112) ** 2 < 1
        former_face = c & (z > .11)
        return mask(points, green, rgb, name) & ~former_face

    return selection


def clean_texture(id, texture):
    color = colors[id]
    cleaned = geometry.replace_baked_green(texture, color)
    if id in ("cat", "cat-bear"):
        # Knock down fabric speckle but keep the black buttons, stitching,
        # and pink ear and honey belly panel boundaries crisp.
        i = Image.fromarray(cleaned)
        blurred = np.asarray(i.filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32)
        base = cleaned.astype(np.float32)
        cloth = np.linalg.norm(base - np.asarray(color), axis=2) < 53
        far_from_edge = np.linalg.norm(base - blurred, axis=2) < 27
        w = (cloth & far_from_edge).astype(np.float32)[..., None] * .60
        return np.rint(base + (blurred - base) * w).astype(np.uint8)
    if id == "raincoat":
        base = cleaned.astype(np.float32)
        r, g, b = np.moveaxis(base, -1, 0)
        # Old baked plant material near the back and around coat openings
        # leaves olive patches; remap only the contaminated yellow hue band.
        cloth = (r > 135) & (g > 110) & (b < 115) & (r - g < 36) & (g - b > 38)
        strength = np.clip((36 - (r - g)) / 26, 0, .82)[..., None]
        gold = np.array((251, 205, 58), dtype=np.float32)
        base[cloth] += (gold - base[cloth]) * strength[cloth]
        return np.rint(base).astype(np.uint8)
    return cleaned


def prepare_trimmed_costume(id, output, preview=False):
    mask, fit, hidden = options(id)
    hidden = set(hidden) | CUTS[id].keys()
    geometry.prepare(id, output, trim_old_face(mask, id), fit, hidden=hidden, render=False,
                     clean_color=lambda texture: clean_texture(id, texture))
    add_visible_sections(id, output, hidden, preview)


def add_visible_sections(id, output, hidden=(), preview=False):
    name = "seed-costume-" + id
    stage_file = output / (name + ".usda")
    stage = stage_file.read_text()
    costume = list(geometry.meshes(stage)) if preview else []
    master_file = geometry.assets / "Characters/SeedCucumberMaster.usdz"
    master = geometry.read_stage(master_file)
    material_scope = '    def Scope "Materials"\n    {\n'
    textures = [entry.removeprefix("./") for entry in geometry.archive.findall(stage)]
    limbs, materials = [], []
    kept = []
    accents = []
    if id == "bee":
        accents.append(([bee_crown()], "CrownFabric", "(0.99, 0.61, 0.044)", (250, 205, 59)))
    if id == "cat":
        accents.append(([cat_cuff_lining(-1), cat_cuff_lining(1)], "CuffFabric",
                        "(0.42, 0.37, 0.36)", (174, 164, 162)))
    for meshes, material, color, _ in accents:
        limbs.extend(geometry.as_mesh(*mesh).replace("/mat0>", f"/{material}>") for mesh in meshes)
        materials.append(material_surface(material, color, .82))
    with zipfile.ZipFile(master_file) as source:
        (output / "Textures").mkdir(exist_ok=True)
        for part, label, points, faces, uv in visible_skin(id):
            material = overlay_material(master, label + "Material", part)
            entries = list(dict.fromkeys(geometry.archive.findall(material)))
            if part == "Body":
                uv = crop_body_maps(source, output, uv, entries)
            else:
                for entry in entries:
                    (output / entry).write_bytes(source.read(entry))
            limbs.append(compact_skin(label, points, faces, uv))
            materials.append(material)
            textures.extend(entries)
            kept.append((part, label, points, faces, uv))
        if preview:
            material = Image.open(output / textures[0]).convert("RGB")
            packages = [(costume, np.asarray(material))]
            packages.extend((meshes, np.full((4, 4, 3), rgb, dtype=np.uint8))
                            for meshes, _, _, rgb in accents)
            base = [(n, n, p, f, uv) for n, p, f, uv in geometry.seed_data if n not in hidden] + kept
            for part, label, points, faces, uv in base:
                suffix = "BodyBaseColor" if part == "Body" else part
                entry = f"Textures/{suffix}.png"
                if part == "Body":
                    image = Image.open(output / entry).convert("RGB")
                else:
                    image = Image.open(io.BytesIO(source.read(entry))).convert("RGB")
                packages.append(([(label, points, faces, uv)], np.asarray(image)))
            geometry.raster(None, packages, id + "-overlay")
    stage_file.write_text(stage.replace(material_scope, "".join(limbs)+material_scope+"".join(materials), 1))
    package_stage(output, name, textures)
