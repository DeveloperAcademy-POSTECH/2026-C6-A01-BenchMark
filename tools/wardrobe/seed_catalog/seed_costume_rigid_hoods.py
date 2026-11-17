"""Keep the original astronaut helmets and dinosaur snood with the live seed face."""

import numpy as np

import seed_costume_geometry as geometry
from seed_costume_original import prepare_original_costume, source_face_depth
from seed_costume_skin_volume import seal_skin_cuts


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
    keep = ~(face | stem)
    if id != 'dinosaur':
        # The only surviving donor geometry above the rigid helmet is dark
        # stem flecks. Remove them with the stem so the socket has one rim.
        keep &= centers[:, 1] <= 1.386
    if id == 'astronaut-navy':
        x, y, z = centers.T
        red, green, blue = rgb.T
        visor_shadow = ((aperture(id, centers) > -.009)
                        & (x < -.17) & (y > .988) & (y < 1.231) & (z > .073)
                        & (red < 147) & (green >= red - 3) & (green >= blue - 3))
        keep &= ~visor_shadow
    return keep


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


def nearest_face_sample(query, points, uv):
    """Interpolate existing front skin UVs and depth in the same face plane."""
    nearest_uv = []
    nearest_depth = []
    for start in range(0, len(query), 80):
        batch = query[start:start+80]
        distances = np.sum((batch[:, None, :2] - points[None, :, :2]) ** 2, axis=2)
        nearest = np.argpartition(distances, 3, axis=1)[:, :4]
        weights = 1 / np.maximum(np.take_along_axis(distances, nearest, axis=1), 1e-10)
        weights /= weights.sum(axis=1, keepdims=True)
        nearest_uv.append((uv[nearest] * weights[..., None]).sum(axis=1))
        nearest_depth.append((points[nearest, 2] * weights).sum(axis=1))
    return np.concatenate(nearest_uv), np.concatenate(nearest_depth)


def face_closure(points, faces, aperture, visible):
    """Seal the exact cut with a recessed surface sharing the original opening edge."""
    if not np.any(aperture):
        return None
    used, local_faces = np.unique(faces[aperture], return_inverse=True)
    welded = np.unique(np.round(points, 6), axis=0, return_inverse=True)[1]
    seam = np.intersect1d(welded[used], welded[faces[~aperture]])
    boundary = np.isin(welded[used], seam)
    closure = points[used].copy()
    visible_points, visible_faces, visible_uv = visible
    used_skin, texture_indices = np.unique(visible_faces.ravel(), return_index=True)
    live_points = visible_points[used_skin]
    mapped_uv, depth = nearest_face_sample(closure, live_points, visible_uv.reshape(-1, 2)[texture_indices])
    boundary_xy = closure[boundary, :2]
    distance = np.linalg.norm(closure[:, None, :2] - boundary_xy[None, :, :], axis=2).min(axis=1)
    slope = geometry.smoothstep(distance / .024)
    target = np.minimum(depth - .032, closure[:, 2] - .019)
    closure[:, 2] += slope * (target - closure[:, 2])
    local_faces = local_faces.reshape(-1, 3)
    return closure, local_faces, mapped_uv[local_faces]


def combined_surface(visible, closures):
    """Keep the front panel and opaque recessed repair on the same original maps."""
    points, faces, uv = visible
    for closure_points, closure_faces, closure_uv in closures:
        faces = np.concatenate((faces, closure_faces + len(points)), axis=0)
        uv = np.concatenate((uv, closure_uv), axis=0)
        points = np.concatenate((points, closure_points), axis=0)
    return points, faces, uv


def stem_closure(id, points, faces, uv, colors, centers, keep, stem):
    """Close the old stem socket under the hood without baking a second stem."""
    if not np.any(stem):
        return None
    used, local_faces = np.unique(faces[stem], return_inverse=True)
    welded = np.unique(np.round(points, 6), axis=0, return_inverse=True)[1]
    seam = np.intersect1d(welded[used], welded[faces[~stem]])
    closure = points[used].copy()
    boundary = np.isin(welded[used], seam)
    socket = closure[boundary & (closure[:, 1] < np.quantile(closure[boundary, 1], .8) + .003)]
    center = np.median(socket, axis=0)
    inside = ~boundary
    closure[inside] = center + (closure[inside] - center) * np.array([.38, 0, .38])
    closure[inside, 1] = center[1] - .017

    # Pick the local helmet fabric, avoiding original green stem texels.
    nearby = keep & (centers[:, 1] > center[1] - .052)
    nearby &= np.linalg.norm((centers - center)[:, [0, 2]], axis=1) < .13
    red, green, blue = colors.T
    if id == 'astronaut':
        nearby &= (red > 155) & (green > 130) & (blue > 117)
    elif id == 'astronaut-navy':
        nearby &= (blue > red + 10) & (blue > green + 10)
    else:
        nearby &= (green > 65) & (green < 135) & (blue < 65) & (green > red + 12)
    if not np.any(nearby):
        raise ValueError(f'Missing nearby socket fabric for {id}')
    selected = np.flatnonzero(nearby)
    median = np.median(colors[selected], axis=0)
    preferred = selected[np.argmin(np.sum((colors[selected] - median)**2, axis=1))]
    color_uv = uv[preferred].mean(axis=0)
    spread = (closure - center)[:, [0, 2]] * .012
    mapped_uv = color_uv + spread
    local_faces = local_faces.reshape(-1, 3)
    return "StemSocket", closure, local_faces, mapped_uv[local_faces]


def sealed_hood(id):
    part, name, *face = visible_face(id)[0]
    y_center = np.mean(np.array(PROFILE[id])[[0, -1], 0])

    def inset(rim):
        inner = rim.copy()
        inner[:, 0] *= .64 if id == "dinosaur" else .88
        inner[:, 1] = y_center + (inner[:, 1] - y_center) * .82
        inner[:, 2] = .095 if id == "dinosaur" else -.040
        return inner

    closed_face = seal_skin_cuts(*face, inset)
    sealed_apertures, sealed_sockets = [], []
    source, texture = geometry.load(id)
    for mesh, points, faces, uv in geometry.meshes(source):
        centers = points[faces].mean(axis=1)
        colors = geometry.sample(texture, uv.mean(axis=1)).astype(float)
        keep = donor_keep(id, centers, geometry.skin_color(texture, uv), colors, mesh)
        at_stem = centers[:, 1] >= 1.33
        seal = face_closure(points, faces, ~keep & ~at_stem, face)
        if seal is not None:
            sealed_apertures.append(seal)
        socket = stem_closure(id, points, faces, uv, colors, centers, keep, ~keep & at_stem)
        if socket is not None:
            sealed_sockets.append(socket)
    if not sealed_apertures or not sealed_sockets:
        raise ValueError(f"Missing hood closure for {id}")
    skin = combined_surface(closed_face, sealed_apertures)
    return [(part, name, *skin)], sealed_sockets


def prepare_rigid_hood(id, output, preview=False):
    skin, sockets = sealed_hood(id)
    return prepare_original_costume(id, output,
        lambda centers, green, rgb, name: donor_keep(id, centers, green, rgb, name),
        HIDDEN_MASTER_PARTS, skin, extras=sockets, preview=preview,
        preview_offsets={"Stem": STEM_OFFSETS[id], **{
            part: (0, 0, FACE_DEPTH_OFFSETS[id]) for part in ("LeftEye", "RightEye", "Mouth")
        }})
