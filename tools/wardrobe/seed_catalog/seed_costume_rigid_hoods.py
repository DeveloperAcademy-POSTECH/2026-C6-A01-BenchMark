"""Keep the original astronaut helmets and dinosaur snood with the live seed face."""

import numpy as np

import seed_costume_geometry as geometry
from seed_costume_original import prepare_original_costume, source_face_depth


ORIGINAL_VOLUME_HOODS = ("astronaut", "astronaut-navy", "dinosaur")
HIDDEN_MASTER_PARTS = {"Body", "LeftArm", "RightArm", "LeftLeg", "RightLeg"}
STEM_OFFSETS = {
    "astronaut": (-.008, -.010, -.050),
    "astronaut-navy": (.008, -.002, -.058),
    "dinosaur": (.010, -.018, .068),
}
FACE_DEPTH_OFFSETS = {"astronaut": .040, "astronaut-navy": .062, "dinosaur": .088}

# Width at each height of the actual visor and toothed hood openings.
PROFILE = {
    "astronaut": ((.907, 0), (.923, .078), (.940, .122), (.957, .161),
                  (.998, .206), (1.04, .229), (1.12, .233), (1.16, .225),
                  (1.195, .213), (1.229, .193), (1.257, .162), (1.279, .110),
                  (1.294, .047), (1.300, 0)),
    "astronaut-navy": ((.882, 0), (.901, .081), (.917, .135), (.949, .188),
                       (.981, .225), (1.045, .247), (1.107, .247), (1.159, .237),
                       (1.196, .226), (1.230, .199), (1.257, .167), (1.281, .123),
                       (1.295, .064), (1.300, 0)),
    "dinosaur": ((.802, 0), (.818, .068), (.850, .132), (.880, .177),
                 (.929, .204), (.988, .217), (1.063, .220), (1.106, .221),
                 (1.149, .218), (1.177, .209), (1.205, .190), (1.222, .158),
                 (1.236, .092), (1.242, 0)),
}


def aperture(id, points):
    x, y, _ = points.T
    heights, widths = np.array(PROFILE[id]).T
    return np.interp(y, heights, widths, left=-.05, right=-.05) - np.abs(x)


def donor_keep(id, centers, green, rgb, name):
    x, y, z = centers.T
    r, g, b = rgb.T
    dark_green = (g-r > 7) & (g-b > 8)
    in_aperture = aperture(id, centers) > -.009
    if id == "dinosaur":
        # Distinguish the lighter live area from the olive fabric and pale fangs.
        light_skin = (g > 157) & (g > r+26) & (g > b+32) & (r > 92)
        stripe = (g < 145) & (g > r+32) & (b >= r-7) & (g > b+14)
        center = (np.abs(x) < .087) & (y > .897) & (y < 1.104) & (z > .165)
        face = in_aperture & (z > .092) & (light_skin | stripe | center)
        stem = (y > 1.353) & (np.abs(x) < .185) & dark_green & (g-r > 17) & (r < 89) & (g < 126)
    else:
        color_green = (g > r+6) & (g > b+8)
        ymid = 1.105 if id == "astronaut" else 1.099
        center = (np.abs(x) < .103) & (np.abs(y-ymid) < .157) & (z > .164)
        face = in_aperture & (z > .041) & (color_green | center)
        stem_min = 1.356 if id == "astronaut" else 1.374
        stem = (y > stem_min) & (np.abs(x) < .195) & dark_green
    return ~(face | stem)


def visible_face(id):
    _, points, faces, uv = geometry.seed_data[0]
    extra = .009 if id == "dinosaur" else .006
    back = .069 if id == "dinosaur" else .006
    exposed, kept, coords = geometry.clipped_surface(points, faces, uv,
        lambda v: np.minimum(aperture(id, v) + extra, v[:, 2] - back))
    exposed = exposed.copy()
    # Set the editable face center near the original modeled visor and let the
    # skin retreat under the existing rim rather than intersect its outer edge.
    used = np.unique(kept)
    sample = exposed[used]
    inset = geometry.smoothstep((aperture(id, sample) - .003) / .045)
    target = sample[:, 2] + FACE_DEPTH_OFFSETS[id] * inset
    source_cap = source_face_depth(id, sample)
    exposed[used,2] = np.minimum(target, source_cap - .002)
    return [("Body", "VisibleBody", exposed, kept, coords)]


def prepare_rigid_hood(id, output, preview=False):
    return prepare_original_costume(id, output,
        lambda centers, green, rgb, name: donor_keep(id, centers, green, rgb, name),
        HIDDEN_MASTER_PARTS, visible_face(id), preview=preview,
        preview_offsets={"Stem": STEM_OFFSETS[id], **{
            part: (0, 0, FACE_DEPTH_OFFSETS[id]) for part in ("LeftEye", "RightEye", "Mouth")
        }})
