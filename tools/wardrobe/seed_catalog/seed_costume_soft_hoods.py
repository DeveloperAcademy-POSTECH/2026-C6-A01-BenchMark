"""Use the authored raincoat and pajama shells around a locally trimmed seed face."""

import numpy as np

import seed_costume_geometry as geometry
from seed_costume_hood_interior import cut_costume, hood_inside, raincoat_crown_inside, seal_hood_face
from seed_costume_original import prepare_original_costume, source_face_depth


# The original face opening, in neutral coordinates, followed by the editable stem attachment.
# Closed necklines retain the original gloves, paws, boots, and costume props.
SOFT_HOODS = {
    "cat": ((-.002, 1.033, .160, .210), .101, .034, 1.315, (-.024, -.061, .022)),
    "cat-bear": ((-.004, 1.020, .165, .188), .099, .023, 1.313, (-.036, -.064, -.066)),
    "raincoat": ((-.004, 1.050, .177, .215), .090, .019, 1.320, (-.018, -.052, .012)),
}
HIDDEN = {"Body", "LeftArm", "RightArm", "LeftLeg", "RightLeg"}


def keep_cloth(id, centers, green, rgb, stem_height):
    x, y, z = centers.T
    red, g, blue = rgb.T
    old_skin = green | ((g > red + 2) & (g > blue + 4) & (blue < 95))
    opening = (y > .78) & (y < 1.32) & (z > .074) & (np.abs(x) < .22)
    stem = (y >= stem_height) & (np.abs(x) < .182)
    former_features = (z > .130) & ((x / .097) ** 2 + ((y - 1.03) / .126) ** 2 < 1)
    removed = (old_skin & (opening | stem)) | former_features
    if id == "raincoat":
        # A small part of the old face wraps behind the exposed coat lining.
        cheek = (y > .96) & (y < 1.15) & (abs(x) < .16) & (z > .007) & (z < .074)
        removed |= cheek & (g > red + 15) & (g > blue + 9)
        cheek_edge = (y > .975) & (y < 1.13) & (abs(x) < .214) & (z > .038) & (z < .074)
        removed |= cheek_edge & (g > red + 3) & (g > blue + 12)
    return ~removed


def prepare_soft_hood(id, output, preview=False):
    (cx, cy, rx, ry), front, depth, stem_height, stem = SOFT_HOODS[id]
    _, points, faces, uv = next(part for part in geometry.seed_data if part[0] == "Body")

    def aperture(samples):
        x, y, _ = samples.T
        return 1 - ((x - cx) / rx) ** 2 - ((y - cy) / ry) ** 2

    points, faces, uv = geometry.clipped_surface(
        points, faces, uv, lambda sample: np.minimum(aperture(sample), (sample[:, 2] - front) * 12)
    )
    points = points.copy()
    used = np.unique(faces)
    original = points[used]
    # Keep the central face close to its original depth, blending into the opening.
    weight = geometry.smoothstep(aperture(original) / .54)
    target = original[:, 2] + depth * weight
    source_limit = source_face_depth(id, original) - .002
    points[used, 2] = np.minimum(target, source_limit) + weight * np.maximum(target - source_limit, 0)
    if id == "cat":
        # Extend the exposed rind beneath the original hood rim so the lining
        # cannot show through the gap beside the narrower master face.
        points[used, 0] = cx + (points[used, 0] - cx) * 1.28
    skin = [("Body", "VisibleBody", *seal_hood_face(id, points, faces, uv))]
    face_offsets = {name: (0, 0, depth) for name in ("LeftEye", "RightEye", "Mouth")}
    def mask(centers, green, rgb, name):
        return keep_cloth(id, centers, green, rgb, stem_height)

    lining = hood_inside(id, cut_costume(id, mask))
    if id == "raincoat":
        lining.append(raincoat_crown_inside())
    prepare_original_costume(id, output, mask, HIDDEN, skin, extras=lining,
                             preview_offsets={"Stem": stem, **face_offsets}, preview=preview)
