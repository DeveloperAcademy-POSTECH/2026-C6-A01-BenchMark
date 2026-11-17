"""Restore the scientist's original costume and flask around the editable seed."""
import io
import zipfile

import numpy as np
from PIL import Image

import seed_costume_geometry as geometry
from seed_costume_extras import package_stage
from seed_costume_modular_tops import indexed_skin
from seed_costume_original import prepare_original_costume
from seed_costume_school_science import add_eyewear, material_surface

HIDDEN = frozenset(("Body", "LeftArm", "RightArm", "LeftLeg", "RightLeg"))
COLLAR_ANGLES = np.arange(0, 360, 30)
COLLAR_HEIGHTS = np.array([.883, .889, .929, .954, .956, .942, .938, .947, .958, .956, .936, .911])
COLLAR_CENTER = np.array([-.01, -.065])


def collar_coords(samples):
    delta = samples[:, [0, 2]] - COLLAR_CENTER
    phase = np.degrees(np.arctan2(delta[:, 0], delta[:, 1])) % 360
    threshold = np.interp(phase, COLLAR_ANGLES, COLLAR_HEIGHTS, period=360)
    return delta, phase, threshold


def keep_scientist(centers, green, rgb, name):
    x, y, z = centers.T
    r, g, b = rgb.T
    _, _, threshold = collar_coords(centers)
    pale_cloth = (r > 185) & (b > 146) & (r-g < 46) & (g-r < 18)
    # The green lanyard reaches to the neckline and must be retained with the coat.
    lanyard = (y < .889) & (np.abs(x + .015) < .114) & (z > .069)
    garment = (y < threshold - .009) | ((y < threshold + .011) & (pale_cloth | lanyard))
    # This pose is fused to the original flask. Keep the fingers, glass rim,
    # bottom liquid shape and stirring rod together in their authored coordinates.
    moving_boundary = np.interp(y, [.90,.97,1.025,1.08,1.145,1.20,1.32,1.38],
                                [-.231,-.233,-.248,-.252,-.254,-.231,-.202,-.197])
    grip = (x < moving_boundary) & (y < 1.13) & (z > .040)
    sleeve = (x < -.253) & (y < .966)
    liquid = (r > 169) & (r-g > 43) & (b-g > 3) & (x < -.166) & (z > .108) & (y > .909) & (y < 1.06)
    glass = (r > 101) & (np.ptp(rgb, axis=1) < 33) & (x < moving_boundary + .023) & (z > .116) & (y > 1.00) & (y < 1.365)
    near_flask = (x < -.201) & (x > -.332) & (z > .121) & (y > .921) & (y < 1.108) & ~green & ((r > 103) | (b > 105))
    return garment | (grip & (y > .810)) | sleeve | liquid | glass | near_flask


def collar_ring(points, faces, keep):
    # A contour cut through the original surface gives the radius to which the
    # seed's lower neck must taper. The costume itself keeps every donor vertex.
    edges = np.sort(np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]]), axis=1)
    unique, inverse = np.unique(edges, axis=0, return_inverse=True)
    retained = np.bincount(inverse, weights=np.tile(keep, 3)) == 1
    shared = np.bincount(inverse) == 2
    seam = points[unique[retained & shared]].mean(axis=1)
    delta, phase, threshold = collar_coords(seam)
    radius = np.linalg.norm(delta, axis=1)
    selection = (np.abs(seam[:, 1] - threshold) < .019) & (radius > .10) & (radius < .280)
    # Exclude the adjacent source fingers/flask seam from the shoulder fit.
    selection &= ~((seam[:, 0] < -.180) & (seam[:, 2] > .105) & (seam[:, 1] > .913))
    bins = np.floor(phase * .2).astype(int)
    heights, radii = np.full(72, np.nan), np.full(72, np.nan)
    for index in np.unique(bins[selection]):
        match = selection & (bins == index)
        heights[index] = np.median(seam[match, 1])
        radii[index] = np.median(radius[match])
    axis = np.arange(72)
    valid = np.isfinite(heights)
    if np.count_nonzero(valid) < 20:
        raise ValueError("The original scientist neckline could not be measured")
    profile = np.column_stack([np.interp(axis, axis[valid], value[valid], period=72)
                               for value in (heights, radii)])
    return sum(np.roll(profile, shift, axis=0) * weight
               for shift, weight in zip((-2, -1, 0, 1, 2), (.08, .22, .40, .22, .08)))


def visible_body(source, texture):
    name, points, faces, uv = next(geometry.meshes(source))
    centers = points[faces].mean(axis=1)
    colors = geometry.sample(texture, uv.mean(axis=1)).astype(float)
    keep = keep_scientist(centers, geometry.skin_color(texture, uv), colors, name)
    contour = collar_ring(points, faces, keep)
    _, body, tri, body_uv = next(part for part in geometry.seed_data if part[0] == "Body")

    def profile(vertices):
        delta, phase, _ = collar_coords(vertices)
        return delta, np.column_stack([np.interp(phase * .2 - .5, np.arange(72), samples, period=72)
                                       for samples in contour.T])

    def trim(vertices):
        _, samples = profile(vertices)
        return vertices[:, 1] - samples[:, 0] + .010

    visible, cut_faces, cut_uv = geometry.clipped_surface(body, tri, body_uv, trim)
    visible = visible.copy()
    used = np.unique(cut_faces)
    delta, samples = profile(visible[used])
    keep_radius = np.linalg.norm(delta, axis=1)
    taper = 1 - geometry.smoothstep((visible[used, 1] - samples[:, 0] + .002) / .096)
    span = keep_radius + taper * (samples[:, 1] - .004 - keep_radius)
    visible[np.ix_(used, [0, 2])] = COLLAR_CENTER + geometry.unit(delta) * span[:, None]
    return [("Body", "VisibleBody", visible, cut_faces, cut_uv)]


def attach_visor(output):
    name = "seed-costume-scientist"
    path = output / (name + ".usda")
    stage = path.read_text()
    mesh_text = []
    for label, points, faces, material in add_eyewear("scientist", geometry.body):
        # The neutral seed's eyes are slightly lower than the donor eyes.
        # Position the existing clear visor around them without baking face parts.
        points[:, 1] -= .032
        geometry.body.push_out(points, .013)
        mesh = geometry.as_mesh(label, points, faces, np.zeros((len(faces), 3, 2)))
        mesh_text.append(mesh.replace("/Materials/mat0>", f"/Materials/{material}>"))

    materials = "".join([
        material_surface("VisorFrameMaterial", "(0.68, 0.72, 0.66)", .37),
        material_surface("VisorLensMaterial", "(0.69, 0.82, 0.74)", .19, .19),
        material_surface("VisorStrapMaterial", "(0.055, 0.062, 0.06)", .8),
    ])
    scope = '    def Scope "Materials"\n    {\n'
    stage = stage.replace(scope, "".join(mesh_text) + scope + materials, 1)
    path.write_text(stage)
    maps = list(dict.fromkeys(entry.removeprefix("./") for entry in geometry.archive.findall(stage)))
    package_stage(output, name, maps)
    return stage


def review_scientist(stage, output, texture):
    parts = []
    colors = {"VisorFrame": [168, 174, 157], "VisorStrap": [40, 44, 40]}
    body = np.asarray(Image.open(output / "Textures/BodyBaseColor.png").convert("RGB"))
    for part in geometry.meshes(stage):
        label = part[0]
        if label == "VisorLens":
            continue
        atlas = body if label == "VisibleBody" else texture
        if label in colors:
            atlas = np.full((4, 4, 3), colors[label], dtype=np.uint8)
        parts.append(([part], atlas))
    master = geometry.assets / "Characters/SeedCucumberMaster.usdz"
    with zipfile.ZipFile(master) as source:
        for part in geometry.seed_data:
            if part[0] in HIDDEN:
                continue
            atlas = np.asarray(Image.open(io.BytesIO(source.read(f"Textures/{part[0]}.png"))).convert("RGB"))
            parts.append(([part], atlas))
    geometry.raster(None, parts, "scientist-revised")


def prepare_scientist(output, preview=False):
    source, texture = geometry.load("scientist")
    skin = visible_body(source, texture)
    prepare_original_costume("scientist", output, keep_scientist, HIDDEN, skin,
                             skin_writer=indexed_skin, preview=preview)
    stage = attach_visor(output)
    if preview:
        review_scientist(stage, output, texture)
