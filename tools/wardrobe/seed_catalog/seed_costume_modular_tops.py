"""Restore original modular top silhouettes around the seed's visible skin."""
import io
import re
import subprocess
import zipfile

import numpy as np
from PIL import Image

import seed_costume_geometry as geometry
from seed_costume_coverage import overlay_material


HIDDEN = frozenset(("Body", "LeftArm", "RightArm"))
AXIS_COUNT = 192
SOURCES = {
    "hoodie": ("SeedCucumberHoodie", "wardrobe-hoodie-long", "hoodie_top_001", "Material_0_002", "Hoodie"),
    "postech": ("SeedCucumberPostechJacket", "wardrobe-postech-long", "postech_top_001", "Material_0_007", "PostechJacket"),
}


def boundaries(faces):
    edges = np.concatenate((faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]))
    edges = np.sort(edges, axis=1)
    unique, counts = np.unique(edges, axis=0, return_counts=True)
    neighbor = {}
    for i, j in unique[counts == 1]:
        neighbor.setdefault(i, set()).add(j)
        neighbor.setdefault(j, set()).add(i)
    loops = []
    while neighbor:
        queue = [next(iter(neighbor))]
        group = set()
        for node in queue:
            if node in group:
                continue
            group.add(node)
            queue.extend(neighbor.pop(node, ()))
        loops.append(np.asarray(sorted(group)))
    return sorted(loops, key=len, reverse=True)


def waist_envelope(resources):
    """Measure the inner layering space shared by the two authored bottoms."""
    heights = np.arange(.445, .540, .002)
    radii = np.zeros((len(heights), AXIS_COUNT))
    center = np.array([-.004, -.005])
    for garment in ("SeedCucumberLongPants", "SeedCucumberShorts"):
        stage = geometry.read_stage(resources / "Characters" / (garment + ".usdz"))
        for _, points, faces, _ in geometry.meshes(stage):
            edge_indices = np.concatenate((faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]))
            edge_indices = np.unique(np.sort(edge_indices, axis=1), axis=0)
            a, b = points[edge_indices].transpose(1, 0, 2)
            lower, upper = np.minimum(a[:, 1], b[:, 1]), np.maximum(a[:, 1], b[:, 1])
            for index, height in enumerate(heights):
                cross = (lower < height) & (upper >= height)
                if not cross.any():
                    continue
                fraction = (height - a[cross, 1]) / (b[cross, 1] - a[cross, 1])
                xy = ((b[cross] - a[cross]) * fraction[:, None] + a[cross])[:, [0, 2]]
                delta = xy - center
                bins = np.floor(np.mod(np.arctan2(delta[:, 1], delta[:, 0]), 2 * np.pi)
                                * AXIS_COUNT / (2 * np.pi)).astype(int)
                local = np.zeros(AXIS_COUNT)
                np.maximum.at(local, bins, np.linalg.norm(delta, axis=1))
                valid = np.flatnonzero(local)
                if len(valid) > 8:
                    local = np.interp(np.arange(AXIS_COUNT), valid, local[valid], period=AXIS_COUNT)
                radii[index] = np.maximum(radii[index], local)
    # Pad neighboring samples as the panel moves through the waist and seams.
    radii = np.maximum.reduce([np.roll(radii, step, axis=0) for step in (-2, -1, 0, 1, 2)])
    radii[-3:] = 0
    radii = np.maximum.reduce([np.roll(radii, step, axis=1) for step in (-2, -1, 0, 1, 2)])
    return center, heights, radii


def fit_garment(points, faces, envelope, kind):
    ss = geometry.smoothstep
    neck, waist, *openings = boundaries(faces)
    if kind == "postech":
        waist, neck = neck, waist
    fit = points.copy()
    x, y, z = points.T
    fit[:, 0] *= 1.055
    fit[:, 2] = z * 1.076 + .009

    if kind == "hoodie":
        fit[:, 1] += .024
        # Keep the neck seam rounded and let its full shell settle lower on the
        # shoulders. Drawstrings and patch pockets retain the source topology.
        back = 1 - ss((z + .02) / .195)
        lower = ss((y - .674) / .101) * (.026 + .021 * back)
        fit[:, 1] -= lower
        fold = ss((y - .637) / .103) * (1 - ss((y - .898) / .047)) * (1 - ss((z + .112) / .090))
        fit[:, 2] -= .019 * fold
    else:
        # The selfie reference has a full, taller varsity jacket. Restore the
        # original standing collar and long ribbed sleeves in a neutral pose.
        fit[:, 1] += .028
        fit[:, 1] -= .021 * ss((y - .780) / .123)

    # Preserve the relaxed ribs and pocket, adding only the horizontal ease
    # where the top overlaps the neutral waist of either pair of trousers.
    center, heights, radii = envelope
    line = np.interp(np.minimum(fit[:, 1], .523), heights, np.arange(len(heights)))
    h = np.minimum(line.astype(int), len(heights) - 2)
    delta = fit[:, [0, 2]] - center
    a = np.mod(np.arctan2(delta[:, 1], delta[:, 0]), 2 * np.pi) * AXIS_COUNT / (2 * np.pi)
    l = a.astype(int)
    r = (l + 1) % AXIS_COUNT
    w_h, w_a = line - h, a - l
    low = radii[h, l] * (1 - w_a) + radii[h, r] * w_a
    high = radii[h + 1, l] * (1 - w_a) + radii[h + 1, r] * w_a
    clearance = low + (high - low) * w_h + .011
    extra = np.maximum(clearance - np.linalg.norm(delta, axis=1), 0)
    extra *= 1 - ss((fit[:, 1] - .530) / .065)
    fit[:, [0, 2]] += geometry.unit(delta) * extra[:, None]

    cuffs = {}
    anchor_x, anchor_y = (.308, .561) if kind == "hoodie" else (.326, .550)
    for side, label in [(-1, "LeftArm"), (1, "RightArm")]:
        rim = min(openings[:4], key=lambda item: np.linalg.norm(
            points[item].mean(axis=0) - [side * anchor_x, anchor_y, .031]))
        lift = ss((side * x - .210) / .096) * (1 - ss((y - .584) / .199))
        fit[:, 0] += side * (.004 if kind == "hoodie" else -.013) * lift
        fit[:, 1] += (.025 if kind == "hoodie" else .018) * lift
        fit[:, 2] -= .006 * lift
        cuffs[label] = fit[rim]
    return fit, fit[neck], fit[waist], cuffs


def profile(ring, center):
    local = ring[:, [0, 2]] - center
    angles = np.mod(np.arctan2(local[:, 1], local[:, 0]), 2 * np.pi)
    bins = np.floor(angles * AXIS_COUNT / (2 * np.pi)).astype(int)
    samples = np.full((AXIS_COUNT, 2), np.nan)
    radius = np.linalg.norm(local, axis=1)
    for index in np.unique(bins):
        member = bins == index
        samples[index] = np.median(np.column_stack((ring[member, 1], radius[member])), axis=0)
    axis = np.arange(AXIS_COUNT)
    known = np.isfinite(samples[:, 0])
    samples = np.column_stack([np.interp(axis, axis[known], column[known], period=AXIS_COUNT)
                               for column in samples.T])
    return sum(np.roll(samples, shift, axis=0) * weight
               for shift, weight in zip((-2, -1, 0, 1, 2), (.08, .22, .40, .22, .08)))


def interpolate(points, center, ring):
    delta = points[:, [0, 2]] - center
    phase = np.mod(np.arctan2(delta[:, 1], delta[:, 0]), 2 * np.pi) * AXIS_COUNT / (2 * np.pi)
    values = np.column_stack([np.interp(phase, np.arange(AXIS_COUNT), column, period=AXIS_COUNT)
                              for column in ring.T])
    return delta, values


def body_surface(points, faces, uv, collar, waist):
    # Retain the neck and the skin visible below the hem. The hidden torso no
    # longer forces the hoodie profile outward in order to avoid collisions.
    center = np.array([-.004, -.005])
    neck = profile(collar, center)
    lower = profile(waist, center)

    def top_limit(samples):
        _, values = interpolate(samples, center, neck)
        return samples[:, 1] - values[:, 0] + .017

    def bottom_limit(samples):
        _, values = interpolate(samples, center, lower)
        return values[:, 0] + .012 - samples[:, 1]

    upper, upper_faces, upper_uv = geometry.clipped_surface(points, faces, uv, top_limit)
    below, below_faces, below_uv = geometry.clipped_surface(points, faces, uv, bottom_limit)
    delta, values = interpolate(upper, center, neck)
    current = np.linalg.norm(delta, axis=1)
    # Seat the hidden edge inside the neck opening with a short fade; keep the
    # original body profile above the visible neckline.
    t = 1 - geometry.smoothstep((upper[:, 1] - values[:, 0] + .012) / .086)
    radius = current + t * (np.minimum(current, values[:, 1] - .007) - current)
    upper = upper.copy()
    upper[:, [0, 2]] = center + geometry.unit(delta) * radius[:, None]
    return (("BodyUpper", upper, upper_faces, upper_uv), ("BodyLower", below, below_faces, below_uv))


def arm_surface(name, points, faces, uv, rim):
    side = -1 if name == "LeftArm" else 1
    center = rim.mean(axis=0)
    _, eigenvectors = np.linalg.eigh(np.cov((rim - center).T))
    direction = eigenvectors[:, 0]
    if direction[1] > 0:
        direction = -direction
    if direction[0] * side < 0:
        direction[0] *= -.2
    direction = geometry.unit(direction)
    # Trim under the cuff and keep the full outer green hand.
    points, faces, uv = geometry.clipped_surface(points, faces, uv,
        lambda point: (point - center) @ direction + .019)
    p = points.copy()
    distance = (p - center) @ direction
    axis_point = center + distance[:, None] * direction
    radius = p - axis_point
    p = axis_point + radius * (1 - .39 * (1 - geometry.smoothstep((distance + .015) / .050)))[:, None]
    return p, faces, uv


def indexed_skin(name, points, faces, uv):
    """Carry a single vertex/UV pair per triangle corner, deduplicating seams."""
    normals, area = geometry.normals_for(points, faces)
    keep = area > 1e-13
    f = faces[keep]
    attr = np.column_stack([f.ravel(), uv[keep].reshape(-1, 2).round(9)])
    vertices, indices = np.unique(attr, axis=0, return_inverse=True)
    used = vertices[:, 0].astype(int)
    p = points[used]
    format_array = geometry.float_array
    return f'''    def Mesh "{name}" (
        prepend apiSchemas = ["MaterialBindingAPI"]
    )
    {{
        uniform bool doubleSided = true
        uniform token subdivisionScheme = "none"
        rel material:binding = </SeedCostume/Materials/{name}Material>
        float3[] extent = {format_array([p.min(axis=0), p.max(axis=0)])}
        point3f[] points = {format_array(p)}
        int[] faceVertexCounts = [{", ".join(["3"] * len(f))}]
        int[] faceVertexIndices = [{", ".join(map(str, indices))}]
        normal3f[] normals = {format_array(normals[used])} (
            interpolation = "vertex"
        )
        texCoord2f[] primvars:st = {format_array(vertices[:, 1:])} (
            interpolation = "vertex"
        )
    }}
'''


def asset_maps(scope, archive, output):
    paths = set(geometry.archive.findall(scope))
    textures = []
    for ref in sorted(paths):
        path = ref.removeprefix("./")
        destination = output / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(archive.read(path))
        textures.append(path)
    return textures


def make_stage(output, resources, *, preview=False, kind="hoodie"):
    name, source_name, original_mesh, material_name, mesh_name = SOURCES[kind]
    orig = resources / "Wardrobe" / (source_name + ".usdz")
    master = resources / "Characters" / "SeedCucumberMaster.usdz"
    original_source = geometry.read_stage(orig)
    _,points,faces,garment_uv = next(part for part in geometry.meshes(original_source) if part[0] == original_mesh)
    updated, collar, waist, cuffs = fit_garment(points, faces, waist_envelope(resources), kind)
    part = (mesh_name, updated, faces, garment_uv)
    top_mesh = geometry.as_mesh(*part)
    material_match = re.search(r'(?ms)^        def Material "' + re.escape(material_name) + r'"\n.*?^        }', original_source)
    material = material_match[0].replace(f"/OiWardrobe/_materials/{material_name}","/SeedCostume/Materials/mat0")
    material = material.replace(f'def Material "{material_name}"','def Material "mat0"')
    material = re.sub(r'@\./', '@', material)
    output.mkdir(exist_ok=True, parents=True)
    skin_source=geometry.read_stage(master)
    layers=[]
    bindings=""
    geometry_text=top_mesh
    with zipfile.ZipFile(orig) as source:
        textures=asset_maps(material,source,output)
        if preview:
            color_path = re.search(r'asset inputs:file = @([^@]+)@\s+token inputs:sourceColorSpace = "sRGB"', material)
            if color_path is None:
                raise ValueError(f"Missing sRGB color texture for {original_mesh}")
            albedo = np.asarray(Image.open(io.BytesIO(source.read(color_path[1]))).convert("RGB"))
    with zipfile.ZipFile(master) as source:
        for skin_name, p, f, uv in geometry.seed_data:
            if skin_name=="Body":
                sections = body_surface(p,f,uv,collar,waist)
            elif skin_name in cuffs:
                sections = [(skin_name,*arm_surface(skin_name,p,f,uv,cuffs[skin_name]))]
            else:
                continue
            for label,*shape in sections:
                label="Visible"+label
                binding=overlay_material(skin_source,label+"Material",skin_name)
                for resource in asset_maps(binding,source,output):
                    if resource not in textures: textures.append(resource)
                bindings+=binding
                geometry_text+=indexed_skin(label,*shape)
                layers.append(((label,*shape),skin_name))
    stage=f"""#usda 1.0
(
    defaultPrim = "SeedCostume"
    metersPerUnit = 1
    upAxis = "Y"
)
def Xform "SeedCostume"
{{
{geometry_text}
    def Scope "Materials"
    {{
{material}
{bindings}
    }}
}}
"""
    (output/(name+'.usda')).write_text(stage)
    for command in (
        ["/usr/bin/usdcat", "-o", name+".usdc", name+".usda"],
        ["/usr/bin/usdzip", name+".usdz", name+".usdc", *textures],
        ["/usr/bin/usdchecker", "--strict", "--arkit", name+".usdz"],
    ):
        subprocess.run(command, check=True, cwd=output, timeout=30)
    if preview:
        legs=[(n,p,f,u) for n,p,f,u in geometry.seed_data if n not in HIDDEN]
        with zipfile.ZipFile(master) as source:
            def texture(name):
                name="BodyBaseColor" if name=="Body" else name
                return np.asarray(Image.open(io.BytesIO(source.read("Textures/"+name+".png"))).convert("RGB"))
            def make_limb(parts):
                return [([m],texture(name)) for m,name in parts]
            geometry.raster(None,[([part],albedo)]+make_limb(layers+[(m,m[0]) for m in legs]),kind+"-new")
        geometry.raster([(mesh_name, points, faces, garment_uv)], albedo, kind+"-original")
