"""Authoring masks and fit profiles for five existing STEP 3 costumes."""
from functools import cache

import numpy as np

import seed_costume_geometry as engine
from seed_costume_geometry import arm_sections, smoothstep


@cache
def limb_sections():
    return {
        name: arm_sections(points, faces)
        for name, points, faces, _ in engine.seed_data
        if name in ("LeftArm", "RightArm", "LeftLeg", "RightLeg")
    }


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
    sleeve = (np.abs(x) > .215) & (y > .555) & (y < .777)
    cloth |= sleeve & (r > 115) & (b > 82) & (b > .61 * r)
    return bat | mitt | cap | cloth

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
    return engine.replace_baked_green(texture, (236, 224, 195))

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
    p[:,1] += sleeve * {"baseball": .052, "cowboy": .040, "farmer": .013, "sportswear": .076, "martial-arts": -.012}[kind]
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
        p[bat] = np.column_stack((x[bat] - .021, y[bat] + .028, z[bat] + .017))
        p[mitt] = np.column_stack((x[mitt] + .014, y[mitt] + .047, z[mitt] + .039))
    if kind in ("baseball", "sportswear"):
        crotch = smoothstep((.095 - absx) / .07) * smoothstep((y - .183) / .10) * (1 - smoothstep((y - .301) / .054))
        p[:,1] -= .039 * crotch
    garment = (y > .21) & (y < .92) & ~(bat | mitt)
    sleeve_zone = (y > .48) & (y < .856) & (absx > .185) & ~(bat | mitt)
    # Body and arm envelopes can overlap at the shoulder; repeat after fitting
    # cuffs so an arm correction cannot put the sleeve back inside the torso.
    for _ in range(3):
        envelope(p, engine.body, garment, .020 if kind in ("baseball", "sportswear") else .013)
        envelope(p, left_arm, sleeve_zone & (x < 0), .016)
        envelope(p, right_arm, sleeve_zone & (x > 0), .016)
    if kind == "baseball":
        envelope(p, right_arm, mitt & (p[:,1] > .509), .009)
        # The donor's elbow sits further back than the master. Keep its fabric
        # from cutting through the front of the shoulder after radial fitting.
        shoulder = smoothstep((absx - .18) / .045) * smoothstep((y - .614) / .077) * (1 - smoothstep((y - .787) / .062))
        p[:,2] += .020 * shoulder * smoothstep((z + .064) / .087) * (~(bat | mitt))
    lower = (p[:,1] < .36) & garment
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
    return masks[id], lambda points, faces, name: costume_fit(points, faces, name, id), (), cleaner
