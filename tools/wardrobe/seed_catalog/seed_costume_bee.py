"""Keep the original bee shell and use the editable seed face and stem."""
import numpy as np

import seed_costume_geometry as geometry
from seed_costume_coverage import bee_hood_lining
from seed_costume_original import prepare_original_costume


HIDDEN = {'Body', 'LeftArm', 'RightArm', 'LeftLeg', 'RightLeg'}
STEM_OFFSET = (-.028, -.084, -.010)
APERTURE_HEIGHTS = (.727, .750, .800, .870, .950, 1.040, 1.120, 1.177, 1.212, 1.228)
APERTURE_HALF_WIDTHS = (.105, .152, .209, .227, .234, .227, .202, .164, .128, .105)


def keep_bee_cloth(centers, green, rgb, name):
    x, y, z = centers.T
    red, green_channel, blue = rgb.T
    dark_skin = (green_channel > red + 2) & (green_channel > blue + 4) & (blue < 95)
    original_face = (y > .79) & (y < 1.32) & (z > .085) & (np.abs(x) < .204)
    eyes = original_face & (np.abs(x) < .105) & (y > .925) & (y < 1.13)
    eyes &= (green_channel < 89) & (green_channel > blue + 1) & (red < 70)
    original_stem = (y > 1.286) & (np.abs(x) < .20) & (green | dark_skin)
    legacy_shins = (y > .136) & (y < .285) & (np.abs(x) > .034) & (green | dark_skin)
    face_center = (y > .912) & (y < 1.113) & (z > .161) & (np.abs(x) < .105)
    old_skin = (green_channel > red + 2) & (green_channel > blue + 4) & (blue < 155)
    inside = (y > .728) & (y < 1.264) & (z > .072) & (abs(x) < .225)
    return ~(original_stem | (original_face & (green | dark_skin | eyes)) | face_center
             | legacy_shins | (old_skin & inside))


def bee_skin_sections():
    for name, points, faces, uv in geometry.seed_data:
        if name == 'Body':
            def crop_face(samples):
                x, y, z = samples.T
                half_width = np.interp(y, APERTURE_HEIGHTS, APERTURE_HALF_WIDTHS)
                return np.minimum.reduce((y - APERTURE_HEIGHTS[0], APERTURE_HEIGHTS[-1] - y,
                                          half_width - abs(x), z - .012))

            visible = geometry.clipped_surface(points, faces, uv, crop_face)
        elif name in ('LeftLeg', 'RightLeg'):
            def crop_shin(samples):
                y = samples[:, 1]
                return np.minimum(y - .142, .303 - y)

            visible = geometry.clipped_surface(points, faces, uv, crop_shin)
        else:
            continue
        yield name, 'Visible' + name, *visible


def prepare_bee(output, preview=False):
    source, texture = geometry.load('bee')
    original = []
    for name, points, faces, uv in geometry.meshes(source):
        center = points[faces].mean(axis=1)
        colors = geometry.sample(texture, uv.mean(axis=1)).astype(float)
        kept = keep_bee_cloth(center, geometry.skin_color(texture, uv), colors, name)
        original.append((name, points, faces[kept], uv[kept]))
    prepare_original_costume('bee', output, keep_bee_cloth, HIDDEN, bee_skin_sections(),
                             extras=bee_hood_lining(original), preview_offsets={'Stem': STEM_OFFSET},
                             preview=preview)
