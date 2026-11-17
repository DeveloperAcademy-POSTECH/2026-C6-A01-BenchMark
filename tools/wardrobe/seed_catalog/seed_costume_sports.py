"""Authoring masks and fit profiles for five existing STEP 3 costumes."""
from functools import cache

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import seed_costume_geometry as engine
from seed_costume_geometry import arm_sections, smoothstep


@cache
def limb_sections():
    return {
        name: arm_sections(points, faces)
        for name, points, faces, _ in engine.seed_data
        if name in ("LeftArm", "RightArm", "LeftLeg", "RightLeg")
    }


def baseball_arms(co, rgb):
    x, y = co[:, :2].T
    r, g, b = rgb.T
    left = (x < -.186) & (y > .469) & (y < .655)
    right = (x > .201) & (y > .461) & (y < .638)
    skin = (g > r + 4) & (g > b + 13)
    return (left | right) & skin


def baseball(co, green, rgb, name):
    x, y, z = co.T
    r, g, b = rgb.T
    orange = (r > 75) & (r - g > 18) & (g - b > 12)
    navy = (b > r + 8) & (b > g + 5)
    tan = (r > 70) & (r > b + 18) & (g > b + 8)
    bat = (x < -.19) & (y > .405) & orange
    mitt = (x > .205) & (y < .57) & (y > .29) & tan & ~green
    cap = (y > 1.06) & (navy | ((r > 100) & ~green))
    cloth = (y < .824) & ((~green) | (r > 200)) & ((np.abs(x) < .28) | (y > .52) | (y < .28))
    # The donor's repaired face atlas contains ivory pixels on its old skin.
    # Follow the sewn V-front and rounded back edge before using color.
    front = smoothstep((z + .049) / .101)
    neckline = (.742 + .235 * np.abs(x)) * (1 - front) + (.674 + .499 * np.abs(x)) * front
    cloth &= (y < neckline) | (navy & (y < .812))
    sleeve = (np.abs(x) > .211) & (y > .524) & (y < .784)
    fabric = (r > 137) & (r - g > -5) & (g - b < 43) & (b > .65 * r)
    cloth = np.where(sleeve, navy | fabric, cloth)
    return bat | mitt | cap | cloth | baseball_arms(co, rgb) | (y < .231)

def cowboy(co, green, rgb, name):
    x, y, z = co.T
    r, g, b = rgb.T
    hat = (y > 1.11) & (r > g + 10) & (g > b + 7)
    cloth = (y < .87) & ~green & ((np.abs(x) < .246) | (y > .55) | (y < .40))
    return hat | cloth

def farmer(co, green, rgb, name):
    x, y, z = co.T
    r, g, b = rgb.T
    denim = (b > r + 12) & (b > g + 5)
    wheat = (r > g + 7) & (g > b + 9)
    patch = (np.abs(x) < .11) & (z > .14) & (y > .43) & (y < .54)
    hat = (y > .995) & wheat
    cloth = (y > .15) & (y < .84) & ((~green & ((np.abs(x) < .27) | (y > .57))) | denim | patch)
    return hat | cloth

def sportswear(co, green, rgb, name):
    x, y, z = co.T
    r, g, b = rgb.T
    band = (y > 1.09) & (y < 1.234) & ((r > 182) | (b > r + 5))
    shoes = (y < .218) & ((~green) | (r > 205))
    cloth = (y > .263) & (y < .831) & ~green
    return band | shoes | cloth

def baseball_color(texture):
    # Green belongs on complete donor hands, but not on the fabric cutline.
    stage, _ = engine.load("baseball")
    height, width = texture.shape[:2]
    skin_uv = Image.new("L", (width, height))
    draw = ImageDraw.Draw(skin_uv)
    for _, points, faces, uv in engine.meshes(stage):
        face_rgb = engine.sample(texture, uv.mean(axis=1)).astype(float)
        for triangle in uv[baseball_arms(points[faces].mean(axis=1), face_rgb)]:
            pixels = triangle * [width, -height] + [0, height]
            draw.polygon([tuple(point) for point in pixels], fill=255)
    keep = np.asarray(skin_uv.filter(ImageFilter.MaxFilter(3))) != 0
    fabric = engine.replace_baked_green(texture, (236, 224, 195))
    return np.where(keep[:, :, None], texture, fabric)

def sportswear_color(texture):
    return engine.replace_baked_green(texture, (24, 35, 55))

def martial_arts(co, green, rgb, name):
    x, y, z = co.T
    r, g, b = rgb.T
    white = (r > 105) & (r + b > 2*g - 12)
    white |= (r > 224) & (b > 186) & (y < .886)
    belt = (np.abs(x) < .29) & (z > .096) & (y < .64) & (y > .32) & (b + r > 1.65*g)
    return (y > .177) & (y < .912) & (white | belt | ((y > .53) & (y < .637) & (~green) & (np.abs(x) < .27)))

def envelope(p, model, active, margin):
    src = p[active].copy()
    model.push_out(src, margin)
    p[active] = src


def baseball_sleeves(points, fitted):
    # Keep the complete donor sleeve and hand assembly. The bare seed arms
    # are covered by this costume, so stretching donor rims to bare wrists
    # is unnecessary and distorts the original toy silhouette.
    x, y, z = points.T
    inherited = points.copy()
    inherited[:, 0] *= 1.065
    inherited[:, 1] += .021
    inherited[:, 2] = z * 1.090 + .029
    left = smoothstep((-x - .180) / .045) * smoothstep((y - .451) / .025)
    right = smoothstep((x - .180) / .045) * smoothstep((y - .350) / .049)
    arm = np.maximum(left, right) * (1 - smoothstep((y - .757) / .085))
    # Carry the bat in the same frame as the player's hand.
    bat = smoothstep((-x - .188) / .026) * smoothstep((z + .040) / .027)
    bat *= smoothstep((y - .452) / .024) * (1 - smoothstep((y - .945) / .055))
    weight = np.maximum(arm, bat)
    return fitted + weight[:, None] * (inherited - fitted)

def costume_fit(p, faces, name, kind):
    limbs = limb_sections()
    left_arm, right_arm = limbs["LeftArm"], limbs["RightArm"]
    left_leg, right_leg = limbs["LeftLeg"], limbs["RightLeg"]
    x, y, z = p.T.copy()
    absx = np.abs(x)
    bat = (kind == "baseball") & (x < -.194) & (y > .43) & (z > -.039)
    mitt = (kind == "baseball") & (x > .209) & (y > .31) & (y < .570)
    # Match the body while raising the inherited sleeve mouths to the master wrists.
    sleeve = smoothstep((absx - .22) / .10) * smoothstep((y - .37) / .15) * (1 - smoothstep((y - .75) / .13))
    p[:,1] += sleeve * {"baseball": .0, "cowboy": .040, "farmer": .013, "sportswear": .076, "martial-arts": -.012}[kind]
    body_mix = smoothstep((y - .105) / .25) * (1 - smoothstep((y - .88) / .08))
    p[:,0] *= 1 + body_mix * {"baseball": .065, "cowboy": .095, "farmer": .018, "sportswear": .03, "martial-arts": .055}[kind]
    p[:,2] *= 1 + body_mix * {"baseball": .10, "cowboy": .10, "farmer": .10, "sportswear": .095, "martial-arts": .075}[kind]
    p[:,2] += body_mix * {"baseball": .025, "cowboy": -.008, "farmer": -.008, "sportswear": .004, "martial-arts": .009}[kind]
    foot = y < (.23 if kind == "sportswear" else .132)
    if kind in ("baseball", "cowboy", "sportswear"):
        p[foot,0] *= 1.07
        p[foot,2] += .013
        envelope(p, left_leg, foot & (x < 0), .009)
        envelope(p, right_leg, foot & (x > 0), .009)
    if kind == "baseball":
        sock = y < .257
        p[sock,2] += .013
        # Align the source sock openings before inflating the existing knitted ring.
        p[sock,0] += np.sign(x[sock]) * .013 * smoothstep((y[sock] - .055) / .05)
        envelope(p, left_leg, sock & (x < 0), .014)
        envelope(p, right_leg, sock & (x > 0), .014)
        # Close the sock-to-cleat gap on the unchanged master ankle.
        sock_join = smoothstep((y - .071) / .043) * (1 - smoothstep((y - .161) / .068))
        p[:,1] -= .022 * sock_join
        envelope(p, left_leg, sock & (x < 0), .019)
        envelope(p, right_leg, sock & (x > 0), .019)
    if kind in ("baseball", "cowboy", "farmer", "sportswear"):
        hat_min = {"baseball": 1.052, "cowboy": 1.105, "farmer": .985, "sportswear": 1.074}[kind]
        hat = y > hat_min
        p[hat,1] += {"baseball": .087, "cowboy": .054, "farmer": .082, "sportswear": .078}[kind]
        p[hat,2] += {"baseball": .037, "cowboy": -.003, "farmer": -.008, "sportswear": -.006}[kind]
        envelope(p, engine.body, hat, .013 if kind == "sportswear" else .006)
    if kind == "baseball":
        props = bat | mitt
        p[props] = np.column_stack((x[props] * 1.065, y[props] + .021, z[props] * 1.090 + .029))
    if kind in ("baseball", "sportswear"):
        crotch = smoothstep((.095 - absx) / .07) * smoothstep((y - .183) / .10) * (1 - smoothstep((y - .301) / .054))
        p[:,1] -= .039 * crotch
    garment = (y > .21) & (y < .92) & ~(bat | mitt)
    sleeve_zone = (y > .48) & (y < .856) & (absx > .185) & ~(bat | mitt)
    # Body and arm envelopes can overlap at the shoulder; repeat after fitting
    # cuffs so an arm correction cannot put the sleeve back inside the torso.
    for _ in range(3):
        envelope(p, engine.body, garment, .020 if kind in ("baseball", "sportswear") else .013)
        if kind != "baseball":
            envelope(p, left_arm, sleeve_zone & (x < 0), .016)
            envelope(p, right_arm, sleeve_zone & (x > 0), .016)
    if kind == "baseball":
        p = baseball_sleeves(np.column_stack((x,y,z)), p)
        # The torso grows wider than the donor's side seam. Give that seam
        # room while leaving the sleeve silhouette and hands in their frame.
        side_seam = (y > .397) & (y < .835) & (absx < .249)
        envelope(p, engine.body, side_seam, .029)
        # Keep the intact donor socks and cleats as one connected shape.
        weight = 1 - smoothstep((y - .198) / .089)
        feet = np.column_stack((x * 1.065, y + .008, z * 1.09 + .029))
        p += weight[:, None] * (feet - p)
    lower = (p[:,1] < .36) & garment
    if kind == "baseball":
        lower &= y > .274
    envelope(p, left_leg, lower & (x < 0), .013)
    envelope(p, right_leg, lower & (x > 0), .013)
    return p

masks = {
    "baseball": baseball,
    "cowboy": cowboy,
    "farmer": farmer,
    "sportswear": sportswear,
    "martial-arts": martial_arts,
}

SPORT_COSTUMES = tuple(masks)


def recipe(id):
    cleaner = {"baseball": baseball_color, "sportswear": sportswear_color}.get(id)
    covered = ("LeftArm", "RightArm", "LeftLeg", "RightLeg") if id == "baseball" else ()
    return masks[id], lambda points, faces, name: costume_fit(points, faces, name, id), covered, cleaner
