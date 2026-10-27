"""Generate Doorgunner's sprites in three flat, RimWorld-like styles into assets/sprites/{a,b,c}/.

Every image is drawn at 16x its logical size (coordinates below are logical px), shaded and shadowed,
then downsampled with LANCZOS to 4x. The game scales sprites by Art.SCALE = 0.25 back to logical size.
Terrain tiles are drawn on a 3x3 repeated canvas and cropped, so they wrap seamlessly.
"""
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sprites")
SS = 16  # draw scale
OUT = 4  # output scale

STYLES = {
    "a": {  # RimWorld Classic
        "grass": ((86, 96, 58), (116, 122, 76)), "tuft": (68, 78, 44),
        "forest": ((66, 74, 46), (84, 90, 58)), "canopy": (78, 94, 54), "canopy_lt": (98, 112, 66),
        "water": ((76, 96, 110), (96, 116, 126)), "ripple": (138, 156, 160),
        "sand": ((170, 150, 108), (194, 176, 132)), "soil": ((104, 86, 62), (128, 106, 76)),
        "road": ((74, 72, 68), (90, 88, 84)), "road_line": (178, 166, 120, 110),
        "pave": ((118, 114, 106), (134, 130, 122)), "bwall": (152, 148, 138), "roof": (76, 80, 88), "vent": (118, 122, 128),
        "skylight": (126, 146, 152), "rubble": (126, 120, 110), "char": (48, 44, 40),
        "floor": ((126, 124, 116), (144, 142, 134)),
        "heli": (116, 124, 110), "glass": (48, 58, 64), "metal": (78, 78, 76), "rotor": (54, 54, 52, 150),
        "alien": (120, 98, 124), "alien_dk": (78, 62, 86), "alien_lt": (150, 128, 152), "eye": (222, 214, 188),
        "core": (184, 92, 150), "core_lt": (232, 176, 212), "goo": (124, 104, 128), "spit": (196, 100, 164),
        "skin": (214, 172, 132), "shirt": (78, 102, 128), "hair": (72, 54, 40),
        "tan": (168, 148, 104), "crate": (102, 108, 72), "strap": (176, 160, 114),
        "pad": (92, 92, 88), "paint": (226, 220, 198), "red": (200, 64, 48), "fire": (236, 140, 60),
        "shade": 0.74, "shadow": (0.38, 0.8, 1.1, 0.7), "edge": (26, 24, 20, 110), "grain": 5, "hatch": None, "contrast": 1.0, "alien_glow": None,
    },
    "b": {  # Field Map
        "grass": ((184, 182, 138), (204, 200, 158)), "tuft": (150, 152, 106),
        "forest": ((160, 162, 118), (174, 176, 130)), "canopy": (132, 144, 98), "canopy_lt": (152, 164, 116),
        "water": ((150, 186, 182), (168, 202, 196)), "ripple": (198, 224, 216),
        "sand": ((214, 198, 154), (230, 216, 176)), "soil": ((176, 156, 120), (194, 176, 140)),
        "road": ((118, 112, 100), (132, 126, 112)), "road_line": (236, 228, 200, 150),
        "pave": ((190, 184, 166), (204, 198, 180)), "bwall": (216, 210, 192), "roof": (122, 120, 114), "vent": (164, 160, 150),
        "skylight": (176, 200, 200), "rubble": (178, 170, 152), "char": (98, 90, 80),
        "floor": ((196, 192, 176), (210, 206, 190)),
        "heli": (116, 124, 86), "glass": (66, 82, 86), "metal": (96, 94, 88), "rotor": (64, 62, 56, 140),
        "alien": (84, 56, 102), "alien_dk": (56, 36, 72), "alien_lt": (116, 86, 132), "eye": (236, 226, 200),
        "core": (168, 72, 140), "core_lt": (222, 150, 200), "goo": (96, 70, 112), "spit": (128, 58, 132),
        "skin": (220, 180, 140), "shirt": (70, 98, 126), "hair": (80, 60, 44),
        "tan": (196, 176, 128), "crate": (118, 124, 86), "strap": (206, 190, 140),
        "pad": (140, 138, 128), "paint": (244, 238, 220), "red": (196, 70, 52), "fire": (232, 140, 64),
        "shade": 0.82, "shadow": (0.22, 0.6, 0.8, 0.25), "edge": (52, 46, 36, 230), "grain": 3,
        "hatch": (112, 104, 74, 60), "contrast": 0.7, "alien_glow": None,
    },
    "c": {  # Grim Overcast
        "grass": ((64, 72, 62), (86, 94, 78)), "tuft": (50, 58, 48),
        "forest": ((48, 54, 46), (60, 66, 56)), "canopy": (56, 68, 56), "canopy_lt": (72, 84, 68),
        "water": ((52, 62, 68), (66, 78, 84)), "ripple": (96, 108, 112),
        "sand": ((110, 106, 92), (130, 126, 110)), "soil": ((70, 64, 54), (86, 80, 68)),
        "road": ((32, 32, 34), (44, 44, 46)), "road_line": (126, 120, 98, 80),
        "pave": ((72, 74, 72), (84, 86, 84)), "bwall": (92, 94, 92), "roof": (44, 46, 50), "vent": (72, 74, 78),
        "skylight": (78, 92, 96), "rubble": (82, 82, 78), "char": (28, 26, 24),
        "floor": ((80, 82, 80), (96, 98, 94)),
        "heli": (104, 110, 102), "glass": (34, 42, 46), "metal": (60, 60, 60), "rotor": (36, 36, 36, 160),
        "alien": (52, 66, 44), "alien_dk": (24, 30, 22), "alien_lt": (84, 108, 62), "eye": (214, 236, 130),
        "core": (118, 168, 58), "core_lt": (184, 222, 112), "goo": (36, 48, 30), "spit": (126, 176, 58),
        "skin": (182, 152, 126), "shirt": (122, 92, 68), "hair": (40, 36, 32),
        "tan": (118, 110, 88), "crate": (72, 78, 62), "strap": (132, 124, 98),
        "pad": (58, 60, 60), "paint": (176, 174, 164), "red": (170, 50, 40), "fire": (226, 128, 52),
        "shade": 0.68, "shadow": (0.6, 1.1, 1.5, 1.0), "edge": (12, 12, 10, 140), "grain": 9, "hatch": None, "contrast": 1.1, "alien_glow": (120, 170, 60),
    },
}
P = STYLES["a"]  # current style, set by main loop


def dk(c, f=None):
    f = P["shade"] if f is None else f
    return tuple(int(v * f) for v in c[:3]) + tuple(c[3:])


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def fill(img, mask, col):
    """Alpha-composite a solid colour through an L mask."""
    layer = Image.new("RGBA", img.size, col[:3] + (0,))
    a = col[3] if len(col) > 3 else 255
    layer.putalpha(mask if a == 255 else mask.point(lambda v: v * a // 255))
    img.alpha_composite(layer)


class Spr:
    """Drawing canvas in logical px. tile=True repeats every shape 3x3 so the centre cell wraps."""

    def __init__(self, w, h, tile=False):
        self.w, self.h, self.tile = w, h, tile
        n = 3 if tile else 1
        self.size = (w * n * SS, h * n * SS)
        self.reps = [(i * w, j * h) for i in range(3) for j in range(3)] if tile else [(0, 0)]
        self.img = Image.new("RGBA", self.size, (0, 0, 0, 0))

    def m(self):
        return Mask(self)

    def paint(self, m, col, sh=None, light=None, edge=True):
        """Flat fill plus two-tone shading: the lower-right rim of the shape gets the darker tone."""
        if P["edge"] and edge:
            fill(self.img, m.im.filter(ImageFilter.MaxFilter(2 * (SS // OUT) + 1)), P["edge"])
        fill(self.img, m.im, col)
        if sh is None:
            box = m.im.getbbox()
            sh = 0.0 if box is None else min(box[2] - box[0], box[3] - box[1]) / SS * 0.22
        if sh > 0:
            d = int(sh * SS)
            rim = ImageChops.subtract(m.im, ImageChops.offset(m.im, -d // 3, -d))
            fill(self.img, rim, dk(col))
        if light:
            d = int(light * SS)
            fill(self.img, ImageChops.subtract(m.im, ImageChops.offset(m.im, d // 3, d)), mix(col, (255, 255, 255), 0.18))
        return self

    def drop(self, scale=1.0):
        """Soft drop shadow under everything drawn so far."""
        a, dx, dy, blur = P["shadow"]
        alpha = self.img.getchannel("A").filter(ImageFilter.GaussianBlur(max(1, blur * SS * scale)))
        alpha = ImageChops.offset(alpha, int(dx * SS * scale), int(dy * SS * scale)).point(lambda v: int(v * a))
        out = Image.new("RGBA", self.size, (8, 10, 6, 0))
        out.putalpha(alpha)
        out.alpha_composite(self.img)
        self.img = out
        return self

    def glow(self, col, blur, a=0.6):
        alpha = self.img.getchannel("A").filter(ImageFilter.GaussianBlur(blur * SS)).point(lambda v: int(v * a))
        out = Image.new("RGBA", self.size, col[:3] + (0,))
        out.putalpha(alpha)
        out.alpha_composite(self.img)
        self.img = out
        return self

    def under(self, ground):
        ground.alpha_composite(self.img)
        self.img = ground
        return self

    def out(self):
        n = 3 if self.tile else 1
        im = self.img.resize((self.w * n * OUT, self.h * n * OUT), Image.LANCZOS)
        if self.tile:
            im = im.crop((self.w * OUT, self.h * OUT, 2 * self.w * OUT, 2 * self.h * OUT))
        return im


class Mask:
    def __init__(s, spr):
        s.spr = spr
        s.im = Image.new("L", spr.size, 0)
        s.d = ImageDraw.Draw(s.im)

    def ell(s, cx, cy, rx, ry=None, v=255):
        ry = rx if ry is None else ry
        for ox, oy in s.spr.reps:
            s.d.ellipse([(cx - rx + ox) * SS, (cy - ry + oy) * SS, (cx + rx + ox) * SS, (cy + ry + oy) * SS], fill=v)
        return s

    def rect(s, x0, y0, x1, y1, r=0.0, v=255):
        for ox, oy in s.spr.reps:
            s.d.rounded_rectangle([(x0 + ox) * SS, (y0 + oy) * SS, (x1 + ox) * SS, (y1 + oy) * SS], radius=r * SS, fill=v)
        return s

    def poly(s, pts, v=255):
        for ox, oy in s.spr.reps:
            s.d.polygon([((x + ox) * SS, (y + oy) * SS) for x, y in pts], fill=v)
        return s

    def line(s, pts, w, v=255):
        for ox, oy in s.spr.reps:
            s.d.line([((x + ox) * SS, (y + oy) * SS) for x, y in pts], fill=v, width=max(1, int(w * SS)), joint="curve")
        for x, y in pts:
            s.ell(x, y, w / 2, v=v)
        return s


# ---------------------------------------------------------------- terrain

def pnoise(size, cells, seed):
    """Smooth value noise that wraps with period `size` (bicubic upscale of a tiled random grid)."""
    rnd = random.Random(seed)
    small = Image.new("L", (cells, cells))
    small.putdata([rnd.randrange(256) for _ in range(cells * cells)])
    big = Image.new("L", (cells * 3, cells * 3))
    for i in range(3):
        for j in range(3):
            big.paste(small, (i * cells, j * cells))
    return big.resize((size * 3, size * 3), Image.BICUBIC).crop((size, size, 2 * size, 2 * size))


def fbm(size, seed, octaves=((2, 0.25), (4, 0.35), (8, 0.25), (16, 0.15))):
    acc = None
    total = 0.0
    for i, (cells, w) in enumerate(octaves):
        n = pnoise(size, cells, seed * 31 + i)
        total += w
        acc = n if acc is None else Image.blend(acc, n, w / total)
    return ImageOps.autocontrast(acc, cutoff=1)


def ground(cols, seed, contrast=1.0, octaves=None):
    """3x3 tiled RGBA ground at draw scale, colourised mottling between two tones."""
    size = 16 * SS
    n = fbm(size, seed) if octaves is None else fbm(size, seed, octaves)
    k = contrast * P["contrast"]
    n = n.point(lambda v: max(0, min(255, int(128 + (v - 128) * k))))
    c = ImageOps.colorize(n, cols[0], cols[1]).convert("RGBA")
    big = Image.new("RGBA", (size * 3, size * 3))
    for i in range(3):
        for j in range(3):
            big.paste(c, (i * size, j * size))
    return big


def detail(s, seed, col, count, rmin=0.15, rmax=0.4):
    """Random speckle (pebbles, dirt flecks) in a tiled canvas."""
    rnd = random.Random(seed)
    m = s.m()
    for _ in range(count):
        m.ell(rnd.uniform(0, 16), rnd.uniform(0, 16), rnd.uniform(rmin, rmax), rnd.uniform(rmin, rmax) * 0.8)
    fill(s.img, m.im, col)


def hatch(s):
    if not P["hatch"]:
        return
    m = s.m()
    for k in range(-16, 32, 4):  # period 4 divides 16, so it wraps
        m.line([(k, 0), (k + 16, 16)], 0.16)
    fill(s.img, m.im, P["hatch"])
    detail(s, 77, P["hatch"][:3] + (110,), 14, 0.07, 0.13)  # survey-map speckle


def grain(im, seed):
    """Per-pixel grain at output resolution (uncorrelated, so it cannot create seams)."""
    amt = P["grain"]
    if not amt:
        return im
    rnd = random.Random(seed)
    g = Image.new("L", im.size)
    g.putdata([max(0, min(255, int(128 + rnd.gauss(0, amt)))) for _ in range(im.size[0] * im.size[1])])
    rgb = ImageChops.add(im.convert("RGB"), g.convert("RGB"), 1.0, -128)
    out = rgb.convert("RGBA")
    out.putalpha(im.getchannel("A"))
    return out


def t_grass(seed=1):
    s = Spr(16, 16, True)
    s.img = ground(P["grass"], 7, 0.6, ((4, 0.45), (8, 0.35), (16, 0.2)))
    hatch(s)
    detail(s, seed + 1, P["grass"][1] + (90,), 26, 0.1, 0.3)
    rnd = random.Random(seed)
    tuft = s.m()
    for _ in range(3):
        x, y = rnd.uniform(0, 16), rnd.uniform(0, 16)
        for a in (-0.7, -0.25, 0.2, 0.65):
            tuft.line([(x, y), (x + a * 1.3, y - 1.1 - abs(a) * -0.3)], 0.22)
    fill(s.img, tuft.im, P["tuft"] + (170,))
    return s


def t_forest():
    s = Spr(16, 16, True)
    s.img = ground(P["forest"], 7, 0.8)
    detail(s, 21, dk(P["forest"][0], 0.8) + (120,), 30, 0.1, 0.3)
    trees = Spr(16, 16, True)
    rnd = random.Random(12)
    for gx in range(3):  # jittered grid of canopies so the repeat is less obvious
        for gy in range(3):
            x, y, r = (gx + rnd.uniform(0.1, 0.9)) * 5.33, (gy + rnd.uniform(0.1, 0.9)) * 5.33, rnd.uniform(2.3, 3.7)
            m = trees.m().ell(x, y, r, r * rnd.uniform(0.88, 1.0))
            trees.paint(m, mix(P["canopy"], dk(P["canopy"], 0.8), rnd.random()), sh=r * 0.45, edge=False)
            trees.paint(trees.m().ell(x - r * 0.3, y - r * 0.35, r * 0.4), P["canopy_lt"], sh=0, edge=False)
    trees.drop()
    return trees.under(s.img)


def t_water():
    s = Spr(16, 16, True)
    s.img = ground(P["water"], 11, 0.8, ((2, 0.5), (4, 0.35), (8, 0.15)))
    rnd = random.Random(5)
    m = s.m()
    for _ in range(7):
        x, y, l = rnd.uniform(0, 16), rnd.uniform(0, 16), rnd.uniform(1.5, 3.5)
        m.line([(x, y), (x + l * 0.5, y - 0.25), (x + l, y)], 0.22)
    fill(s.img, m.im, P["ripple"] + (110,))
    return s


def t_sand():
    s = Spr(16, 16, True)
    s.img = ground(P["sand"], 7, 0.7)
    hatch(s)
    detail(s, 31, dk(P["sand"][0], 0.82) + (150,), 40, 0.08, 0.22)
    detail(s, 32, P["sand"][1] + (150,), 20, 0.08, 0.2)
    return s


def t_road():
    s = Spr(16, 16, True)
    s.img = ground(P["road"], 13, 0.6, ((4, 0.4), (8, 0.3), (16, 0.3)))
    detail(s, 41, dk(P["road"][0], 0.8) + (140,), 30, 0.1, 0.3)
    m = s.m()
    for y in (1.5, 9.5):  # dashes, period 8 so they wrap
        m.rect(7.55, y, 8.45, y + 4.5, 0.3)
    m.ell(9.5, 3, 0.9, v=0).ell(7, 12, 0.7, v=0)  # worn patches
    fill(s.img, m.im, P["road_line"])
    return s


def t_building():
    s = Spr(16, 16, True)
    s.img = ground(P["pave"], 17, 0.5)
    hatch(s)
    b = Spr(16, 16, True)
    b.paint(b.m().rect(1.5, 1.5, 14.5, 14.5, 0.4), P["bwall"], sh=0.7)
    b.paint(b.m().rect(2.6, 2.6, 13.4, 13.4, 0.3), P["roof"], sh=0)
    b.paint(b.m().rect(2.6, 8.0, 13.4, 13.4, 0.0), dk(P["roof"], 0.86), sh=0, edge=False)  # two-tone roof halves
    b.paint(b.m().rect(9.2, 4.0, 12.0, 6.4, 0.4), P["vent"], sh=0.5)
    b.paint(b.m().rect(4.0, 9.6, 7.4, 12.0, 0.2), P["skylight"], sh=0.4)
    b.drop()
    return b.under(s.img)


def t_ruin():
    s = Spr(16, 16, True)
    s.img = ground(P["soil"], 19, 0.8)
    rnd = random.Random(6)
    scorch = s.m().ell(9, 8, 5.5, 4.5)
    fill(s.img, scorch.im.filter(ImageFilter.GaussianBlur(2.0 * SS)), P["char"] + (150,))
    b = Spr(16, 16, True)
    b.paint(b.m().poly([(1.5, 1.5), (9, 1.5), (9, 3), (3, 3), (3, 8), (1.5, 9.5)]), P["bwall"], sh=0.5)
    b.paint(b.m().poly([(14.5, 9), (14.5, 14.5), (8, 14.5), (8.5, 13), (13, 13), (13, 10)]), P["bwall"], sh=0.5)
    for _ in range(14):
        x, y, r = rnd.uniform(3, 14), rnd.uniform(3, 14), rnd.uniform(0.3, 0.9)
        b.paint(b.m().poly([(x - r, y), (x, y - r * 0.8), (x + r, y + r * 0.2), (x + r * 0.2, y + r)]),
                P["rubble"] if rnd.random() < 0.6 else dk(P["rubble"], 0.8), sh=0.25)
    b.drop(0.6)
    return b.under(s.img)


def t_floor():
    s = Spr(16, 16, True)
    s.img = ground(P["floor"], 23, 0.35, ((2, 0.4), (4, 0.3), (16, 0.3)))
    hatch(s)
    detail(s, 51, dk(P["floor"][0], 0.85) + (90,), 16, 0.1, 0.35)
    joints = s.m().rect(0, 7.92, 16, 8.08).rect(7.92, 0, 8.08, 16).rect(0, -0.08, 16, 0.08).rect(-0.08, 0, 0.08, 16)
    fill(s.img, joints.im, dk(P["floor"][0], 0.75) + (90,))  # concrete slab joints, 8 px grid
    return s


def tiles():
    strip = Image.new("RGBA", (128 * OUT, 16 * OUT))
    for i, f in enumerate((t_grass, t_forest, t_water, t_sand, t_road, t_building, t_ruin, t_floor)):
        strip.paste(grain(f().out(), 100 + i), (i * 16 * OUT, 0))
    return strip


# ---------------------------------------------------------------- sprites

def heli():
    s = Spr(32, 32)
    s.paint(s.m().rect(9.2, 8, 10.4, 21, 0.6), P["metal"], sh=0.3)  # skids
    s.paint(s.m().rect(21.6, 8, 22.8, 21, 0.6), P["metal"], sh=0.3)
    s.paint(s.m().rect(10, 11, 22, 12, 0.3).rect(10, 17, 22, 18, 0.3), P["metal"], sh=0.3)
    s.paint(s.m().rect(15, 19, 17, 29.5, 1.0), P["heli"], sh=0.5)  # tail boom
    s.paint(s.m().rect(12, 25, 20, 26.6, 0.8), P["heli"], sh=0.5)  # stabiliser
    s.paint(s.m().rect(17.2, 27, 18.4, 31, 0.5), P["metal"], sh=0.3)  # tail rotor
    s.paint(s.m().rect(11, 4.5, 21, 22.5, 4.5), P["heli"], sh=1.6, light=0.8)  # fuselage
    s.paint(s.m().ell(16, 8.2, 4.1, 3.6), P["glass"], sh=0, light=0.9)
    s.paint(s.m().ell(14.6, 6.8, 1.6, 1.0), mix(P["glass"], (255, 255, 255), 0.35), sh=0, edge=False)
    s.paint(s.m().rect(13.6, 13, 18.4, 19.5, 1.6), dk(P["heli"], 0.86), sh=0.6)  # engine deck
    s.paint(s.m().rect(11.1, 11, 12.1, 18, 0.4).rect(19.9, 11, 20.9, 18, 0.4), dk(P["heli"], 0.7), sh=0)  # doors
    return s


def rotor():
    s = Spr(32, 32)
    m = s.m()
    m.poly([(15.3, 16), (15.6, 1), (16.4, 1), (16.7, 16), (16.4, 31), (15.6, 31)])
    m.poly([(16, 15.3), (1, 15.6), (1, 16.4), (16, 16.7), (31, 16.4), (31, 15.6)])
    fill(s.img, m.im, P["rotor"])
    s.paint(s.m().ell(16, 16, 1.8), P["metal"], sh=0.5)
    return s


def bullet():
    s = Spr(4, 4)
    s.paint(s.m().ell(2, 2, 1.7, 0.7), (255, 226, 120), sh=0)
    s.paint(s.m().ell(2.3, 2, 0.9, 0.35), (255, 250, 220), sh=0)
    return s.glow((255, 200, 80), 0.4, 0.8)


def enemy_bullet():
    s = Spr(6, 6)
    s.paint(s.m().ell(3, 3, 1.9), P["spit"], sh=0.6)
    s.paint(s.m().ell(2.5, 2.4, 0.6), mix(P["spit"], (255, 255, 255), 0.5), sh=0)
    return s.glow(P["spit"], 0.45, 0.7)


def alien(s):
    """Grim style: faint goo glow so dark aliens still read at night."""
    return s.glow(P["alien_glow"], 0.7, 0.4) if P["alien_glow"] else s


def eyes(s, pts, r):
    m = s.m()
    for x, y in pts:
        m.ell(x, y, r)
    s.paint(m, P["eye"], sh=0)


def walker():
    s = Spr(16, 16)
    legs = s.m()
    for y in (6.0, 10.0):
        legs.line([(6, y), (3.2, y - 1.2), (1.6, y + 1.8)], 0.9)
        legs.line([(10, y), (12.8, y - 1.2), (14.4, y + 1.8)], 0.9)
    s.paint(legs, P["alien_dk"], sh=0)
    s.paint(s.m().ell(8, 9, 3.4, 4.2), P["alien"])
    s.paint(s.m().ell(8, 4.6, 2.2, 1.8), P["alien_lt"], sh=0.5)
    eyes(s, ((7.1, 4.3), (8.9, 4.3)), 0.5)
    return alien(s.drop(0.6))


def runner():
    s = Spr(16, 16)
    limbs = s.m()
    limbs.line([(7, 9), (4.5, 10.5), (3.5, 13.5)], 0.7).line([(9, 9), (11.5, 10.5), (12.5, 13.5)], 0.7)
    limbs.line([(7, 5), (4.6, 4.6), (3.6, 2)], 0.7).line([(9, 5), (11.4, 4.6), (12.4, 2)], 0.7)
    s.paint(limbs, P["alien_dk"], sh=0)
    s.paint(s.m().ell(8, 8.4, 1.9, 4.6), P["alien_lt"])
    s.paint(s.m().ell(8, 3.6, 1.6, 1.5), P["alien_lt"], sh=0.5)
    eyes(s, ((7.3, 3.2), (8.7, 3.2)), 0.4)
    return alien(s.drop(0.6))


def spitter():
    s = Spr(16, 16)
    s.paint(s.m().ell(8, 8.8, 5.6, 5.2), P["alien"], sh=1.4)
    s.paint(s.m().ell(8, 10, 3.4, 2.8), P["core"], sh=0.8)
    s.paint(s.m().ell(7.2, 9.2, 1.1, 0.8), P["core_lt"], sh=0)
    s.paint(s.m().ell(8, 3.8, 2.0, 1.3), P["alien_dk"], sh=0)  # mouth
    eyes(s, ((5.0, 5.0), (11.0, 5.0)), 0.5)
    return alien(s.drop(0.6))


def flyer():
    s = Spr(16, 16)
    s.paint(s.m().poly([(7.5, 6), (1, 5), (0.5, 7.5), (3, 8.2), (4.5, 9.8), (7.5, 9.5)]), P["alien"], sh=0.8)
    s.paint(s.m().poly([(8.5, 6), (15, 5), (15.5, 7.5), (13, 8.2), (11.5, 9.8), (8.5, 9.5)]), P["alien"], sh=0.8)
    m = s.m()
    for x0, x1 in ((7, 1.4), (9, 14.6)):
        m.line([(x0, 6.8), (x1, 5.6)], 0.25)
    s.paint(m, P["alien_dk"], sh=0)
    s.paint(s.m().ell(8, 7.6, 1.9, 4.4), P["alien_dk"], sh=0.8)
    eyes(s, ((7.3, 4.4), (8.7, 4.4)), 0.4)
    return alien(s)


def boss():
    s = Spr(48, 48)
    legs = s.m()
    for y in (15, 23, 31):
        legs.line([(17, y), (8, y - 3), (3, y + 6)], 2.0)
        legs.line([(31, y), (40, y - 3), (45, y + 6)], 2.0)
    s.paint(legs, P["alien_dk"], sh=0.5)
    s.paint(s.m().ell(24, 27, 12, 15), P["alien"], sh=3.0)
    s.paint(s.m().ell(24, 10, 7.5, 6), P["alien_lt"], sh=1.6)
    s.paint(s.m().line([(20, 5), (18.5, 2)], 1.2).line([(28, 5), (29.5, 2)], 1.2), P["alien_dk"], sh=0)
    s.paint(s.m().ell(24, 28, 7, 7.5), P["core"], sh=1.4)
    s.paint(s.m().ell(23, 27, 3.4, 3.6), P["core_lt"], sh=0)
    eyes(s, ((21, 8.4), (27, 8.4), (22.6, 11), (25.4, 11)), 0.9)
    return alien(s.drop(1.4))


def survivor():
    s = Spr(8, 8)
    s.paint(s.m().ell(4, 5.1, 2.7, 2.1), P["shirt"], sh=0.8)
    s.paint(s.m().ell(4, 3.4, 1.65), P["skin"], sh=0.6)
    s.paint(s.m().ell(4, 2.85, 1.55, 1.15), P["hair"], sh=0)
    return s.drop(0.35)


def helipad():
    s = Spr(48, 48)
    s.paint(s.m().ell(24, 24, 22.6), P["pad"], sh=0.8)
    paint = (P["paint"][0], P["paint"][1], P["paint"][2], 215)
    ring = s.m().ell(24, 24, 19.6)
    ring.ell(24, 24, 17.8, v=0)
    fill(s.img, ring.im, paint)
    h = s.m().rect(16, 14, 19.5, 34).rect(28.5, 14, 32, 34).rect(16, 22.3, 32, 25.7)
    h.ell(21, 30, 1.2, v=110)  # worn paint
    fill(s.img, h.im, paint)
    return s.drop(0.4)


def turret():
    s = Spr(16, 16)
    s.paint(s.m().ell(8, 9, 5.6), P["tan"], sh=1.0)  # sandbag ring
    s.paint(s.m().ell(8, 9, 3.8), dk(P["tan"], 0.8), sh=0)
    s.paint(s.m().rect(7.3, 1, 8.7, 9, 0.6), P["metal"], sh=0.4)
    s.paint(s.m().ell(8, 9, 2.6), mix(P["metal"], (255, 255, 255), 0.15), sh=0.8)
    return s.drop(0.5)


def hangar():
    s = Spr(32, 32)
    s.paint(s.m().rect(1.5, 1.5, 30.5, 29.5, 0.8), P["bwall"], sh=1.0)
    s.paint(s.m().rect(3, 3, 29, 28, 0.5), P["roof"], sh=0)
    s.paint(s.m().rect(16, 3, 29, 28, 0), dk(P["roof"], 0.86), sh=0)  # shaded roof half
    ribs = s.m()
    for x in range(5, 29, 3):
        ribs.rect(x, 3.5, x + 0.4, 27.5)
    fill(s.img, ribs.im, dk(P["roof"], 0.7) + (140,))
    s.paint(s.m().rect(15.5, 3, 16.5, 28), dk(P["roof"], 0.6), sh=0)  # ridge
    s.paint(s.m().rect(6, 6, 10, 9, 0.4), P["vent"], sh=0.6)
    s.paint(s.m().rect(20, 18, 26, 22, 0.3), P["skylight"], sh=0.5, light=0.6)
    s.paint(s.m().rect(9, 27, 23, 31, 0.2), (30, 30, 30), sh=0)  # door
    s.paint(s.m().rect(9, 27, 23, 27.8), P["metal"], sh=0)
    return s.drop()


def wall():
    s = Spr(16, 16)
    rnd = random.Random(3)
    for row, y in enumerate((3.6, 8.0, 12.4)):
        off = 2.2 if row == 1 else 0
        for x in range(-2, 18, 5):
            cx = x + off + 2.5
            s.paint(s.m().rect(cx - 2.6, y - 2.2, cx + 2.6, y + 2.2, 1.8),
                    mix(P["tan"], (0, 0, 0), rnd.uniform(0, 0.1)), sh=0.9)
    return s.drop(0.5)


def crate():
    s = Spr(16, 16)
    s.paint(s.m().rect(1.5, 1.5, 14.5, 14.5, 0.8), P["crate"], sh=1.2)
    s.paint(s.m().rect(3, 3, 13, 13, 0.4), mix(P["crate"], (255, 255, 255), 0.08), sh=0)
    s.paint(s.m().rect(7, 1.5, 9, 14.5).rect(1.5, 7, 14.5, 9), P["strap"], sh=0.4)
    return s.drop(0.6)


def radio_tower():
    s = Spr(16, 32)
    m = s.m()
    m.line([(7.4, 2), (3, 31)], 0.7).line([(8.6, 2), (13, 31)], 0.7)
    for y in range(6, 31, 5):
        hw = 0.8 + (y - 2) * 4.4 / 29
        m.line([(8 - hw, y), (8 + hw, y)], 0.45)
        m.line([(8 - hw, y), (8 + hw + 0.7, y + 5)], 0.3)
    s.paint(m, P["metal"], sh=0)
    s.paint(s.m().ell(8, 1.8, 1.3), P["red"], sh=0)
    s.glow(P["red"], 0.1, 0)
    return s.drop(0.8)


def wreck():
    s = Spr(32, 32)
    fill(s.img, s.m().ell(15, 16, 13, 12).im.filter(ImageFilter.GaussianBlur(3 * SS)), P["char"] + (200,))
    burnt = mix(P["metal"], P["char"], 0.6)
    s.paint(s.m().line([(18, 20), (27, 26.5)], 2.2), burnt, sh=0.6)
    s.paint(s.m().rect(9, 8.5, 19, 22, 3.5), burnt, sh=1.6)
    s.paint(s.m().rect(10.5, 9.5, 17.5, 13, 1.5), P["char"], sh=0)
    s.paint(s.m().line([(4, 6), (24, 14)], 1.0).line([(16, 2), (11, 23)], 1.0), dk(P["metal"], 0.6), sh=0)
    rnd = random.Random(9)
    m = s.m()
    for _ in range(9):
        m.ell(rnd.uniform(10, 19), rnd.uniform(10, 21), rnd.uniform(0.35, 0.7))
    fill(s.img, m.im.filter(ImageFilter.GaussianBlur(0.4 * SS)), P["fire"] + (255,))
    return s


def nest():
    s = Spr(32, 32)
    fill(s.img, s.m().ell(16, 18, 14, 12.5).im.filter(ImageFilter.GaussianBlur(1.5 * SS)), P["goo"] + (170,))
    s.paint(s.m().ell(16, 17, 12, 10.5), P["alien_dk"], sh=2.2)
    s.paint(s.m().ell(15, 15.5, 9.5, 8), P["alien"], sh=2.0)
    s.paint(s.m().ell(13, 12, 4.5, 3), P["alien_lt"], sh=0)
    for cx, cy, r in ((11, 14, 2.2), (20.5, 16, 2.4), (15, 21.5, 2.0)):
        s.paint(s.m().ell(cx, cy, r, r * 0.85), (20, 16, 22), sh=0)
        s.paint(s.m().ell(cx + 0.3, cy + 0.4, r * 0.5), P["core"], sh=0)
    return s.drop(0.8)


def muzzle():
    s = Spr(8, 8)
    s.paint(s.m().poly([(4, 0.3), (4.8, 3.2), (7.7, 4), (4.8, 4.8), (4, 7.7), (3.2, 4.8), (0.3, 4), (3.2, 3.2)]),
            (255, 196, 80), sh=0)
    s.paint(s.m().ell(4, 4, 1.5), (255, 248, 210), sh=0)
    return s.glow((255, 170, 60), 0.6, 0.8)


def explosion():
    strip = Image.new("RGBA", (96 * OUT, 16 * OUT))
    smoke = mix(P["metal"], (200, 200, 200), 0.2)
    frames = (
        (3.0, (255, 210, 120), (255, 250, 220), 255),
        (5.0, P["fire"], (255, 220, 130), 255),
        (6.4, mix(P["fire"], P["red"], 0.5), P["fire"], 245),
        (6.8, dk(smoke, 0.5), mix(P["fire"], P["red"], 0.6), 230),
        (6.6, dk(smoke, 0.75), dk(smoke, 0.6), 190),
        (6.2, smoke, dk(smoke, 0.85), 110),
    )
    rnd = random.Random(4)
    for i, (r, outer, inner, a) in enumerate(frames):
        s = Spr(16, 16)
        m = s.m().ell(8, 8, r * 0.8)
        for k in range(7):
            ang = k / 7 * 6.283 + rnd.uniform(-0.3, 0.3)
            m.ell(8 + math.cos(ang) * r * 0.45, 8 + math.sin(ang) * r * 0.45, r * rnd.uniform(0.38, 0.55))
        fill(s.img, m.im.filter(ImageFilter.GaussianBlur(0.3 * SS)), outer + (a,))
        fill(s.img, s.m().ell(7.6, 7.4, r * 0.45).im.filter(ImageFilter.GaussianBlur(0.4 * SS)), inner + (a,))
        if i < 3:
            s.glow((255, 170, 60), 0.8, 0.5)
        strip.paste(s.out(), (i * 16 * OUT, 0))
    return strip


SPRITES = {
    "heli": heli, "rotor": rotor, "bullet": bullet, "enemy_bullet": enemy_bullet, "walker": walker,
    "runner": runner, "spitter": spitter, "flyer": flyer, "boss": boss, "survivor": survivor,
    "helipad": helipad, "turret": turret, "hangar": hangar, "wall": wall, "crate": crate,
    "radio_tower": radio_tower, "wreck": wreck, "nest": nest, "muzzle": muzzle,
}
SIZES = {  # logical sizes, see assets/sprites/README.md
    "heli": (32, 32), "rotor": (32, 32), "bullet": (4, 4), "enemy_bullet": (6, 6), "walker": (16, 16),
    "runner": (16, 16), "spitter": (16, 16), "flyer": (16, 16), "boss": (48, 48), "survivor": (8, 8),
    "tiles": (128, 16), "helipad": (48, 48), "turret": (16, 16), "hangar": (32, 32), "wall": (16, 16),
    "crate": (16, 16), "radio_tower": (16, 32), "wreck": (32, 32), "nest": (32, 32), "muzzle": (8, 8),
    "explosion": (96, 16),
}


def main():
    global P
    for variant, style in STYLES.items():
        P = style
        out = os.path.join(ROOT, variant)
        os.makedirs(out, exist_ok=True)
        images = {name: f().out() for name, f in SPRITES.items()}
        images["tiles"] = tiles()
        images["explosion"] = explosion()
        for name, im in images.items():
            w, h = SIZES[name]
            assert im.size == (w * OUT, h * OUT), (name, im.size)
            im.save(os.path.join(out, name + ".png"))
        print(variant, len(images), "images")


if __name__ == "__main__":
    main()
