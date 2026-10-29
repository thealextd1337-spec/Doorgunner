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
        "zskin": (126, 140, 110), "zcloth": (66, 64, 68), "zred": (150, 96, 84), "flesh": (178, 98, 94), "blood": (112, 32, 30),
        "eye": (222, 214, 188),
        "grass2": (70, 104, 52), "grass3": (152, 140, 82), "crop": (138, 156, 70), "dirt": ((122, 98, 70), (142, 118, 86)),
        "rock": ((116, 114, 108), (142, 140, 132)), "crack": (74, 72, 68), "lawn": ((112, 126, 74), (136, 148, 92)),
        "path": (190, 180, 156),
        "skin": (214, 172, 132), "shirt": (78, 102, 128), "hair": (72, 54, 40),
        "tan": (168, 148, 104), "crate": (102, 108, 72), "strap": (176, 160, 114),
        "pad": (92, 92, 88), "paint": (226, 220, 198), "red": (200, 64, 48), "fire": (236, 140, 60),
        "barn": (146, 66, 50), "wood": (134, 104, 72), "ash": ((70, 68, 64), (92, 88, 82)), "reed": (132, 136, 76),
        "hedge": (58, 78, 42), "hroof": (178, 164, 148), "metalroof": (148, 152, 150), "stone": ((146, 140, 128), (166, 160, 148)),
        "white": (224, 220, 208), "car": (196, 196, 192),
        "shade": 0.74, "shadow": (0.38, 0.8, 1.1, 0.7), "edge": (26, 24, 20, 110), "grain": 5, "hatch": None, "contrast": 1.0,
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
        "zskin": (150, 164, 130), "zcloth": (96, 92, 92), "zred": (182, 126, 110), "flesh": (198, 126, 118), "blood": (140, 58, 52),
        "eye": (236, 226, 200),
        "grass2": (150, 172, 112), "grass3": (214, 198, 140), "crop": (150, 172, 96), "dirt": ((188, 164, 122), (204, 182, 140)),
        "rock": ((172, 168, 156), (192, 188, 176)), "crack": (126, 120, 106), "lawn": ((198, 200, 152), (214, 214, 170)),
        "path": (238, 230, 206),
        "skin": (220, 180, 140), "shirt": (70, 98, 126), "hair": (80, 60, 44),
        "tan": (196, 176, 128), "crate": (118, 124, 86), "strap": (206, 190, 140),
        "pad": (140, 138, 128), "paint": (244, 238, 220), "red": (196, 70, 52), "fire": (232, 140, 64),
        "barn": (192, 106, 86), "wood": (190, 164, 124), "ash": ((150, 146, 136), (170, 166, 156)), "reed": (162, 172, 112),
        "hedge": (122, 140, 90), "hroof": (224, 212, 192), "metalroof": (198, 198, 192), "stone": ((204, 198, 182), (220, 214, 198)),
        "white": (246, 242, 230), "car": (232, 230, 222),
        "shade": 0.82, "shadow": (0.22, 0.6, 0.8, 0.25), "edge": (52, 46, 36, 230), "grain": 3,
        "hatch": (112, 104, 74, 60), "contrast": 0.7,
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
        "zskin": (102, 114, 94), "zcloth": (40, 40, 42), "zred": (128, 82, 72), "flesh": (150, 78, 74), "blood": (88, 24, 22),
        "eye": (196, 200, 170),
        "grass2": (52, 72, 48), "grass3": (98, 96, 72), "crop": (92, 108, 62), "dirt": ((80, 70, 58), (96, 86, 72)),
        "rock": ((84, 86, 84), (102, 104, 100)), "crack": (44, 44, 44), "lawn": ((78, 88, 70), (96, 106, 86)),
        "path": (126, 124, 114),
        "skin": (182, 152, 126), "shirt": (122, 92, 68), "hair": (40, 36, 32),
        "tan": (118, 110, 88), "crate": (72, 78, 62), "strap": (132, 124, 98),
        "pad": (58, 60, 60), "paint": (176, 174, 164), "red": (170, 50, 40), "fire": (226, 128, 52),
        "barn": (104, 54, 46), "wood": (96, 82, 64), "ash": ((44, 42, 40), (58, 56, 52)), "reed": (86, 94, 60),
        "hedge": (38, 50, 36), "hroof": (122, 114, 106), "metalroof": (98, 100, 100), "stone": ((94, 92, 86), (110, 108, 102)),
        "white": (164, 162, 154), "car": (150, 150, 148),
        "shade": 0.68, "shadow": (0.6, 1.1, 1.5, 1.0), "edge": (12, 12, 10, 140), "grain": 9, "hatch": None, "contrast": 1.1,
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


def grass_base():
    s = Spr(16, 16, True)
    s.img = ground(P["grass"], 7, 0.45, ((4, 0.45), (8, 0.35), (16, 0.2)))
    hatch(s)
    return s


def tufts(s, rnd, n, col):
    m = s.m()
    for _ in range(n):  # kept off the edges so grass variants and tree edges tile with each other
        x, y = rnd.uniform(2, 14), rnd.uniform(2.5, 14)
        for a in (-0.7, -0.25, 0.2, 0.65):
            m.line([(x, y), (x + a * 1.3, y - 1.1 - abs(a) * -0.3)], 0.22)
    fill(s.img, m.im, col + (120,))


def t_grass(seed=1, n=3, tint=None, flecks=None):
    """Grass and its variants share one ground; the tint is a soft blob that fades out before the tile edge."""
    s = grass_base()
    if tint:
        rnd = random.Random(seed * 7)
        blob = s.m()
        for _ in range(3):
            blob.ell(rnd.uniform(7, 9), rnd.uniform(7, 9), rnd.uniform(3.5, 4.5), rnd.uniform(3.5, 4.5))
        fill(s.img, blob.im.filter(ImageFilter.GaussianBlur(1.8 * SS)), tint + (70,))
    detail(s, seed + 1, P["grass"][1] + (60,), 26, 0.1, 0.3)
    if flecks:
        detail(s, seed + 2, flecks + (130,), 18, 0.1, 0.25)
    tufts(s, random.Random(seed), n, P["tuft"])
    return s


def t_tree_edge():
    s = grass_base()
    detail(s, 3, P["grass"][1] + (90,), 26, 0.1, 0.3)
    tufts(s, random.Random(4), 2, P["tuft"])
    trees = Spr(16, 16, True)
    for x, y, r in ((5.2, 5.6, 3.0), (11.2, 9.4, 2.6), (6.4, 12.2, 1.9)):
        trees.paint(trees.m().ell(x, y, r, r * 0.94), P["canopy"], sh=r * 0.45, edge=False)
        trees.paint(trees.m().ell(x - r * 0.3, y - r * 0.35, r * 0.4), P["canopy_lt"], sh=0, edge=False)
    trees.drop()
    return trees.under(s.img)


def t_field():
    s = Spr(16, 16, True)
    s.img = ground(P["soil"], 29, 0.5)
    rnd = random.Random(8)
    furrow = s.m()
    for x in (3, 7, 11, 15):  # period 4 divides 16, so rows wrap
        furrow.rect(x - 0.5, 0, x + 0.5, 16)
    fill(s.img, furrow.im, dk(P["soil"][0], 0.78) + (150,))
    for x in (1, 5, 9, 13):
        plants = s.m()
        for k in range(16):
            plants.ell(x + rnd.uniform(-0.15, 0.15), k + 0.5, rnd.uniform(1.0, 1.3), rnd.uniform(0.6, 0.8))
        fill(s.img, plants.im, P["crop"])
        rim = ImageChops.subtract(plants.im, ImageChops.offset(plants.im, -SS // 6, -SS // 3))
        fill(s.img, rim, dk(P["crop"]))
    detail(s, 9, mix(P["crop"], (255, 255, 255), 0.2) + (120,), 30, 0.1, 0.2)
    return s


def t_dirt_road(tracks=True):
    """Wheel tracks along y; without them it is the plain dirt of junctions and bends."""
    s = Spr(16, 16, True)
    s.img = ground(P["dirt"], 37, 0.6)
    detail(s, 43, dk(P["dirt"][0], 0.8) + (130,), 30, 0.1, 0.3)
    detail(s, 44, P["dirt"][1] + (140,), 16, 0.08, 0.2)
    if not tracks:
        return s
    tracks = s.m()
    for x in (4.6, 11.4):
        tracks.line([(x + 0.3 * math.sin(k / 16 * 6.283), k) for k in range(-1, 18)], 1.5)
    fill(s.img, tracks.im.filter(ImageFilter.GaussianBlur(0.3 * SS)), dk(P["dirt"][0], 0.82) + (110,))
    mid = s.m()
    for k in range(5):
        mid.ell(8 + (k % 2 - 0.5) * 0.6, k * 3.2 + 1, 0.5, 0.9)
    fill(s.img, mid.im, P["tuft"] + (90,))  # faint grass between the tracks
    return s


def t_rock():
    s = Spr(16, 16, True)
    s.img = ground(P["rock"], 53, 0.9)
    hatch(s)
    detail(s, 55, dk(P["rock"][0], 0.8) + (130,), 30, 0.1, 0.3)
    rnd = random.Random(14)
    cracks = s.m()
    for _ in range(5):
        x, y = rnd.uniform(0, 16), rnd.uniform(0, 16)
        pts = [(x, y)]
        for _ in range(4):
            x, y = x + rnd.uniform(-1.6, 1.6), y + rnd.uniform(0.4, 1.6)
            pts.append((x, y))
        cracks.line(pts, 0.28)
    fill(s.img, cracks.im, P["crack"] + (190,))
    b = Spr(16, 16, True)
    for x, y, r in ((5, 5.5, 1.5), (11.5, 11.5, 1.1)):
        b.paint(b.m().poly([(x - r, y + r * 0.2), (x - r * 0.4, y - r * 0.9), (x + r * 0.7, y - r * 0.7),
                            (x + r, y + r * 0.3), (x + r * 0.2, y + r * 0.9), (x - r * 0.7, y + r * 0.8)]),
                mix(P["rock"][1], (255, 255, 255), 0.08), sh=r * 0.5)
    b.drop(0.5)
    return b.under(s.img)


def t_yard():
    s = Spr(16, 16, True)
    s.img = ground(P["lawn"], 7, 0.5, ((4, 0.45), (8, 0.35), (16, 0.2)))
    hatch(s)
    stripes = s.m()
    for x in (0, 8):  # mowing stripes
        stripes.rect(x, 0, x + 4, 16)
    fill(s.img, stripes.im, P["lawn"][1] + (50,))
    path = s.m().rect(6.4, -1, 9.6, 17)
    s.paint(path, P["path"], sh=0, edge=False)
    joints = s.m()
    for y in (0, 4, 8, 12):
        joints.rect(6.4, y - 0.1, 9.6, y + 0.1)
    fill(s.img, joints.im, dk(P["path"], 0.75) + (120,))
    b = Spr(16, 16, True)
    for x, y, r in ((3.2, 4.0, 1.5), (12.6, 11.5, 1.3)):
        b.paint(b.m().ell(x, y, r), P["canopy_lt"], sh=r * 0.4, edge=False)
    b.drop(0.4)
    return b.under(s.img)


def t_asphalt():
    s = Spr(16, 16, True)
    s.img = ground(P["road"], 13, 0.6, ((4, 0.4), (8, 0.3), (16, 0.3)))  # same ground as the road, so they join
    detail(s, 41, dk(P["road"][0], 0.8) + (140,), 30, 0.1, 0.3)
    fill(s.img, s.m().ell(5, 10, 1.8, 1.2).im.filter(ImageFilter.GaussianBlur(0.6 * SS)), dk(P["road"][0], 0.6) + (110,))
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
    wave = s.m()
    for y0 in (2.5, 6.5, 10.5, 14.5):  # wavy highlight, one period per tile so it wraps
        wave.line([(k, y0 + 0.5 * math.sin((k + y0 * 2) / 16 * 12.566)) for k in range(-1, 18)], 0.32)
    fill(s.img, wave.im.filter(ImageFilter.GaussianBlur(0.25 * SS)), mix(P["ripple"], (255, 255, 255), 0.15) + (70,))
    return s


def t_sand():
    s = Spr(16, 16, True)
    s.img = ground(P["sand"], 7, 0.7)
    hatch(s)
    detail(s, 31, dk(P["sand"][0], 0.82) + (150,), 40, 0.08, 0.22)
    detail(s, 32, P["sand"][1] + (150,), 20, 0.08, 0.2)
    return s


def t_road(dashes=True):
    s = Spr(16, 16, True)
    s.img = ground(P["road"], 13, 0.6, ((4, 0.4), (8, 0.3), (16, 0.3)))
    detail(s, 41, dk(P["road"][0], 0.8) + (140,), 30, 0.1, 0.3)
    if not dashes:
        return s
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


def t_hedge():
    """Grass with a hedgerow running down the middle (transposed in game for east-west hedges)."""
    s = t_grass(31, 2)
    b = Spr(16, 16, True)
    rnd = random.Random(15)
    m = b.m()
    for k in range(6):  # period 16, so the hedge joins the next tile
        m.ell(8 + rnd.uniform(-0.6, 0.6), k * 16 / 6, rnd.uniform(3.0, 3.6), 2.4)
    b.paint(m, P["hedge"], sh=1.0, edge=False)
    hl = b.m()
    for k in range(6):
        hl.ell(7 + rnd.uniform(-0.5, 0.5), k * 16 / 6 - 0.6, 1.3, 0.9)
    fill(b.img, hl.im, mix(P["hedge"], (255, 255, 255), 0.16) + (170,))
    b.drop(0.6)
    return b.under(s.img)


def t_marsh():
    """Reed bed: wet mud, small pools and reed clumps, joins water and grass."""
    s = Spr(16, 16, True)
    s.img = ground((mix(P["grass2"], P["water"][0], 0.5), P["grass2"]), 61, 0.7)
    rnd = random.Random(62)
    pools = s.m()
    for _ in range(4):
        pools.ell(rnd.uniform(2, 14), rnd.uniform(2, 14), rnd.uniform(1.4, 2.6), rnd.uniform(0.9, 1.6))
    fill(s.img, pools.im.filter(ImageFilter.GaussianBlur(0.3 * SS)), P["water"][0] + (230,))
    fill(s.img, ImageChops.subtract(pools.im, ImageChops.offset(pools.im, 0, SS // 2)), P["ripple"] + (120,))
    reeds = s.m()
    for _ in range(9):
        x, y = rnd.uniform(1, 15), rnd.uniform(2, 15)
        for a in (-0.8, -0.35, 0.0, 0.4, 0.85):
            reeds.line([(x, y), (x + a * 1.2, y - 1.6 - rnd.uniform(0, 0.8))], 0.24)
    fill(s.img, reeds.im, P["reed"] + (235,))
    detail(s, 63, mix(P["reed"], (255, 255, 255), 0.3) + (160,), 14, 0.1, 0.2)
    return s


def t_warehouse():
    """Ribbed metal roof, seamless: adjacent tiles form one big roof (ribs turned by ACROSS)."""
    s = Spr(16, 16, True)
    s.img = ground((P["metalroof"], mix(P["metalroof"], (255, 255, 255), 0.08)), 71, 0.25)
    ribs = s.m()
    for x in range(0, 16, 2):
        ribs.rect(x + 0.7, 0, x + 1.1, 16)
    fill(s.img, ribs.im, dk(P["metalroof"], 0.8) + (150,))
    fill(s.img, s.m().ell(4, 11, 2.5, 1.6).im.filter(ImageFilter.GaussianBlur(1 * SS)), P["rubble"] + (60,))  # stain
    return s


def ash_ground(seed):
    s = Spr(16, 16, True)
    s.img = ground(P["ash"], seed, 0.8)
    detail(s, seed + 1, P["char"] + (170,), 30, 0.1, 0.35)
    detail(s, seed + 2, mix(P["ash"][1], (255, 255, 255), 0.25) + (120,), 16, 0.08, 0.2)
    return s


def t_ash():
    s = ash_ground(81)
    m = s.m()
    rnd = random.Random(83)
    for _ in range(3):  # charred sticks
        x, y, a = rnd.uniform(3, 13), rnd.uniform(3, 13), rnd.uniform(0, 3.1)
        m.line([(x - math.cos(a) * 1.4, y - math.sin(a) * 1.4), (x + math.cos(a) * 1.4, y + math.sin(a) * 1.4)], 0.35)
    fill(s.img, m.im, P["char"] + (220,))
    tufts(s, random.Random(84), 2, dk(P["grass3"], 0.7))
    return s


def t_crater():
    s = ash_ground(91)
    fill(s.img, s.m().ell(8, 8, 7, 6.4).im.filter(ImageFilter.GaussianBlur(0.8 * SS)), P["char"] + (200,))
    fill(s.img, s.m().ell(8.5, 8.6, 4.6, 4.0).im.filter(ImageFilter.GaussianBlur(0.8 * SS)), dk(P["char"], 0.6) + (230,))
    rim = s.m().ell(8, 8, 7.2, 6.6)
    rim.ell(8.8, 8.8, 6.6, 6.0, v=0)
    fill(s.img, rim.im.filter(ImageFilter.GaussianBlur(0.4 * SS)), mix(P["ash"][1], (255, 255, 255), 0.2) + (150,))
    b = Spr(16, 16, True)
    rnd = random.Random(92)
    for _ in range(7):
        a, r = rnd.uniform(0, 6.28), rnd.uniform(6.4, 7.6)
        x, y, k = 8 + math.cos(a) * r, 8 + math.sin(a) * r * 0.9, rnd.uniform(0.3, 0.6)
        b.paint(b.m().poly([(x - k, y), (x, y - k), (x + k, y + k * 0.3)]), P["rubble"], sh=0.2)
    b.drop(0.3)
    return b.under(s.img)


def t_bend(paved):
    """Road (paved) or dirt road turning from the bottom edge to the right edge, grass outside the curve.
    The game flips it for the other three turns. Drawn once, not tiled: the curve is centred on the tile's corner."""
    s = t_grass()
    road = t_road(False) if paved else t_dirt_road(False)
    c = 32 * SS  # bottom-right corner of the centre tile on the 3x3 canvas

    def arc(r, w, a0=180, a1=270):
        m = Image.new("L", s.size, 0)
        o = (r + w / 2) * SS
        ImageDraw.Draw(m).arc([c - o, c - o, c + o, c + o], a0, a1, fill=255, width=max(1, int(w * SS)))
        return m

    disc = Image.new("L", s.size, 0)
    ImageDraw.Draw(disc).ellipse([c - 16 * SS, c - 16 * SS, c + 16 * SS, c + 16 * SS], fill=255)
    s.img = Image.composite(road.img, s.img, disc.filter(ImageFilter.GaussianBlur(0.2 * SS)))
    if paved:
        fill(s.img, arc(8, 0.9, 203, 247), P["road_line"])  # one dash mid-curve, gaps at the edges like the straight tiles
    else:
        tracks = ImageChops.lighter(arc(4.6, 1.5), arc(11.4, 1.5))  # the straight tiles' tracks sit 3.4 off the middle
        fill(s.img, tracks.filter(ImageFilter.GaussianBlur(0.3 * SS)), dk(P["dirt"][0], 0.82) + (110,))
        mid = Image.new("L", s.size, 0)
        for a in (0.25, 0.75, 1.25):
            x, y = c - 8 * SS * math.cos(a), c - 8 * SS * math.sin(a)
            ImageDraw.Draw(mid).ellipse([x - 0.6 * SS, y - 0.6 * SS, x + 0.6 * SS, y + 0.6 * SS], fill=255)
        fill(s.img, mid, P["tuft"] + (90,))
    return s


def t_parking():
    """Asphalt with two parking bays; lines run from the top edge (turned by ACROSS)."""
    s = t_asphalt()
    m = s.m().rect(-0.2, 0, 0.2, 10.5).rect(7.8, 0, 8.2, 10.5)
    fill(s.img, m.im, P["paint"] + (200,))
    stops = s.m().rect(2.5, 1.2, 5.5, 1.9, 0.3).rect(10.5, 1.2, 13.5, 1.9, 0.3)
    fill(s.img, stops.im, P["pave"][1] + (220,))
    fill(s.img, s.m().ell(12, 6, 1.4, 2).im.filter(ImageFilter.GaussianBlur(0.6 * SS)), dk(P["road"][0], 0.6) + (90,))
    return s


def t_plaza():
    """Village square cobbles."""
    s = Spr(16, 16, True)
    s.img = ground(P["stone"], 101, 0.5)
    rnd = random.Random(102)
    joints = s.m()
    for y in range(0, 16, 2):
        off = 1 if (y // 2) % 2 else 0
        joints.rect(0, y - 0.12, 16, y + 0.12)
        for x in range(off, 16 + off, 2):
            joints.rect(x - 0.12, y, x + 0.12, y + 2)
    fill(s.img, joints.im, dk(P["stone"][0], 0.72) + (170,))
    m = s.m()
    for _ in range(12):
        y = rnd.randrange(8) * 2
        x = rnd.randrange(8) * 2 + y // 2 % 2
        m.rect(x + 0.2, y + 0.2, x + 1.8, y + 1.8, 0.3)
    fill(s.img, m.im, mix(P["stone"][1], (255, 255, 255), 0.1) + (90,))
    return s


def t_pad():
    """Concrete foundation under big props (church, barn, silo, tanks): not landable."""
    s = Spr(16, 16, True)
    s.img = ground(P["pave"], 111, 0.45)
    hatch(s)
    detail(s, 112, dk(P["pave"][0], 0.8) + (110,), 20, 0.1, 0.3)
    return s


def t_bridge():
    """Plank bridge over water, running along y like the roads (ACROSS turns it): rails on both sides."""
    s = t_water()
    deck = Spr(16, 16, True)
    deck.paint(deck.m().rect(2.2, -1, 13.8, 17), P["wood"], sh=0, edge=False)
    planks = deck.m()
    for y in range(0, 16, 2):
        planks.rect(2.2, y - 0.12, 13.8, y + 0.12)
    fill(deck.img, planks.im, dk(P["wood"], 0.7) + (200,))
    deck.paint(deck.m().rect(1.4, -1, 2.6, 17).rect(13.4, -1, 14.6, 17), dk(P["wood"], 0.8), sh=0.4)
    s.img.alpha_composite(deck.img)
    return s


TILES = (  # index = chunk_manager.gd T enum
    t_grass, t_forest, t_water, t_sand, t_road, t_building, t_ruin, t_floor,
    lambda: t_grass(11, 6, P["grass2"]), lambda: t_grass(21, 1, P["grass3"], P["grass3"]),
    t_field, t_dirt_road, t_rock, t_tree_edge, t_yard, t_asphalt,
    t_hedge, t_marsh, t_warehouse, t_ash, t_crater, t_parking, t_plaza, t_pad,
    lambda: t_bend(True), lambda: t_bend(False), lambda: t_dirt_road(False), t_bridge,
)


def tiles():
    strip = Image.new("RGBA", (len(TILES) * 16 * OUT, 16 * OUT))
    for i, f in enumerate(TILES):
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


def eyes(s, pts, r):
    m = s.m()
    for x, y in pts:
        m.ell(x, y, r)
    s.paint(m, P["eye"], sh=0)


def gore(s, pts):
    """Dark blood stains on clothes/skin, soft edged."""
    m = s.m()
    for x, y, r in pts:
        m.ell(x, y, r, r * 0.8)
    fill(s.img, m.im.filter(ImageFilter.GaussianBlur(0.25 * SS)), P["blood"] + (190,))


def zombie(s, skin, cloth, body, head, arms, tears=(), blood=()):
    """Top-down pawn like the survivor, facing up: arms first, then torso (two-tone), torn spots, head."""
    s.paint(arms, skin, sh=0.3)
    s.paint(s.m().ell(*body), cloth)
    m = s.m()
    for x, y, r in tears:  # skin showing through torn clothes
        m.poly([(x - r, y), (x - r * 0.2, y - r * 0.8), (x + r, y - r * 0.2), (x + r * 0.3, y + r * 0.7)])
    s.paint(m, skin, sh=0, edge=False)
    gore(s, blood)
    s.paint(s.m().ell(*head), skin, sh=head[2] * 0.4)
    return s


def shambler():
    s = Spr(16, 16)
    arms = s.m().line([(5.2, 9.2), (4.9, 6.2), (5.5, 3.6)], 1.3).line([(10.8, 9.2), (11.3, 6.6), (10.4, 4.4)], 1.3)
    zombie(s, P["zskin"], P["zcloth"], (8, 10, 4.1, 3.0), (7.4, 7.6, 2.3, 2.1), arms,
           tears=((6.2, 11.2, 0.9), (10.2, 9.8, 0.7)), blood=((9.3, 11.6, 0.8),))
    s.paint(s.m().ell(6.6, 7.2, 1.0, 0.7).ell(8.3, 6.6, 0.6), dk(P["zskin"], 0.7), sh=0, edge=False)  # patchy scalp
    return s.drop(0.6)


def runner():
    s = Spr(16, 16)
    skin = mix(P["zskin"], P["zred"], 0.55)
    cloth = mix(P["zcloth"], P["blood"], 0.45)
    arms = s.m().line([(5.6, 9.0), (4.2, 11.2), (4.6, 13.2)], 1.0).line([(10.4, 9.0), (11.8, 11.0), (11.2, 13.4)], 1.0)
    zombie(s, skin, cloth, (8, 9.6, 3.0, 2.5), (8.2, 6.0, 1.9, 2.0), arms,
           tears=((7.0, 10.4, 0.7),), blood=((8.8, 9.0, 0.7), (6.8, 8.8, 0.4)))
    s.paint(s.m().ell(8.2, 5.4, 1.1, 0.8), dk(skin, 0.68), sh=0, edge=False)
    return s.drop(0.6)


def brute():
    s = Spr(24, 24)
    skin = dk(P["zskin"], 0.84)
    cloth = dk(P["zcloth"], 0.85)
    arms = s.m().line([(5.4, 12.0), (4.4, 8.0), (6.2, 4.6)], 2.3).line([(18.6, 12.0), (20.0, 8.6), (18.4, 5.2)], 2.3)
    s.paint(s.m().ell(5.2, 11.6, 3.4, 3.0).ell(18.8, 11.6, 3.4, 3.0), skin, sh=0.9)  # shoulders
    zombie(s, skin, cloth, (12, 14.2, 7.6, 6.2), (12, 9.4, 2.9, 2.6), arms,
           tears=((8.6, 16.6, 1.6), (15.2, 13.0, 1.2), (12.2, 18.4, 1.0)), blood=((14.6, 17.2, 1.3), (9.2, 12.6, 0.8)))
    s.paint(s.m().ell(12.6, 15.4, 3.0, 2.4), mix(skin, P["flesh"], 0.6), sh=0.8, edge=False)  # bloated, burst belly
    gore(s, ((12.0, 16.2, 1.0),))
    s.paint(s.m().ell(12, 9.0, 1.5, 1.1), dk(skin, 0.7), sh=0, edge=False)
    return s.drop(0.9)


def boss():
    s = Spr(48, 48)
    skin = dk(P["zskin"], 0.9)
    arms = s.m()
    ends = ((8, 5), (40, 6.5), (3.5, 17), (44.5, 19), (5, 31), (43, 33))
    for (x0, y0), (xm, ym), end in zip(((17, 18), (31, 18), (14, 24), (34, 24), (14, 31), (34, 31)),
                                       ((12, 12), (36, 12.5), (7, 21), (41, 22), (8, 29), (40, 30.5)), ends):
        arms.line([(x0, y0), (xm, ym), end], 3.4)  # all reaching forward/out, unlike legs
    s.paint(arms, skin, sh=0.8)
    hands = s.m()
    for x, y in ends:
        hands.ell(x, y, 2.2)
    s.paint(hands, dk(skin, 0.85), sh=0.5)
    s.paint(s.m().ell(24, 27, 13, 15), P["zcloth"], sh=3.0)  # bulk wrapped in rags
    flesh = s.m().ell(24, 26, 10, 11.5).ell(16.5, 32, 4, 3.5)
    s.paint(flesh, P["flesh"], sh=2.0, edge=False)
    ribs = s.m()
    for k in range(5):
        y = 20 + k * 3.2
        ribs.line([(17.5, y + 1), (24, y), (30.5, y + 1)], 0.8)
    s.paint(ribs, mix(P["flesh"], (255, 240, 220), 0.45), sh=0, edge=False)
    gore(s, ((22, 30, 3.0), (29, 24, 1.8), (17, 33, 1.6), (26, 37, 2.0)))
    s.paint(s.m().ell(17, 11, 4.2, 3.8), P["zskin"], sh=1.2)  # two heads
    s.paint(s.m().ell(30, 10, 5.2, 4.6), dk(P["zskin"], 0.9), sh=1.4)
    s.paint(s.m().ell(29.4, 8.6, 2.2, 1.4).ell(16.4, 9.8, 1.6, 1.1), dk(P["zskin"], 0.65), sh=0, edge=False)
    return s.drop(1.4)


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


NESW = ((0, -1), (1, 0), (0, 1), (-1, 0))  # neighbour bits 1 2 4 8 of the sandbag / wire strips


def connected(frame_fn):
    """16 frames of 16x16, frame = neighbour mask (N 1, E 2, S 4, W 8): base.gd picks the one matching its neighbours."""
    strip = Image.new("RGBA", (256 * OUT, 16 * OUT))
    for mask in range(16):
        strip.paste(frame_fn(mask).out(), (mask * 16 * OUT, 0))
    return strip


def sandbag_frame(mask):
    """Two rows of bags along every connected side, a pile in the middle."""
    s = Spr(16, 16)
    rnd = random.Random(mask)

    def bag(cx, cy, along_x):
        w, h = (2.6, 2.2) if along_x else (2.2, 2.6)
        s.paint(s.m().rect(cx - w, cy - h, cx + w, cy + h, 1.8), mix(P["tan"], (0, 0, 0), rnd.uniform(0, 0.12)), sh=0.9)

    for bit, (dx, dy) in enumerate(NESW):
        if mask >> bit & 1:
            for side in (-2.3, 2.3):
                bag(8 + dx * 5.33 + dy * side, 8 + dy * 5.33 + dx * side, dx != 0)
    for side in (-2.3, 2.3):
        horizontal = mask & 10 or not mask & 5
        bag(8 + (0 if horizontal else side), 8 + (side if horizontal else 0), horizontal)
    return s.drop(0.5)


def wire_frame(mask):
    """Concertina coils along every connected side, a wooden post in the middle."""
    s = Spr(16, 16)
    steel = mix(P["metal"], (255, 255, 255), 0.35)
    for bit, (dx, dy) in enumerate(NESW):
        if mask >> bit & 1:
            for k in range(5):
                d = 1.0 + k * 1.75
                m = s.m().ell(8 + dx * d, 8 + dy * d, 2.6)
                m.ell(8 + dx * d, 8 + dy * d, 2.2, v=0)
                s.paint(m, steel, sh=0, edge=False)
    s.paint(s.m().rect(7, 7, 9, 9, 0.4), dk(P["wood"], 0.8), sh=0.4)
    return s.drop(0.3)


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


def den():
    """Zombie den: a caved-in house heaped with bodies and debris."""
    s = Spr(32, 32)
    fill(s.img, s.m().ell(16, 17, 14.5, 12.5).im.filter(ImageFilter.GaussianBlur(2 * SS)), P["char"] + (190,))
    fill(s.img, s.m().ell(15, 18, 8, 6).ell(22, 12, 4, 3).im.filter(ImageFilter.GaussianBlur(1.2 * SS)), P["blood"] + (170,))
    s.paint(s.m().poly([(3, 4), (17, 3), (17, 5.4), (5.5, 6.4), (5, 17), (2.6, 19)]), P["bwall"], sh=0.7)
    s.paint(s.m().poly([(29, 15), (29.4, 28.5), (16, 29), (17, 26.6), (26.6, 26), (26.8, 16)]), P["bwall"], sh=0.7)
    s.paint(s.m().poly([(7, 8), (22, 6), (27, 15), (20, 24), (8, 22)]), dk(P["roof"], 0.9), sh=1.4)  # collapsed roof slab
    s.paint(s.m().line([(9, 10), (24, 21)], 0.7).line([(20, 8), (11, 20)], 0.7), dk(P["roof"], 0.6), sh=0)  # beams
    rnd = random.Random(21)
    for _ in range(16):
        x, y, r = rnd.uniform(4, 28), rnd.uniform(5, 28), rnd.uniform(0.6, 1.4)
        s.paint(s.m().poly([(x - r, y), (x, y - r * 0.8), (x + r, y + r * 0.2), (x + r * 0.2, y + r)]),
                P["rubble"] if rnd.random() < 0.6 else dk(P["rubble"], 0.75), sh=0.3)
    for x, y, a in ((10, 25, 0.4), (23, 9.5, -0.9), (25, 21, 1.9), (6.5, 14, 1.3)):  # bodies
        dx, dy = math.cos(a), math.sin(a)
        s.paint(s.m().line([(x - dx * 1.6, y - dy * 1.6), (x + dx * 1.6, y + dy * 1.6)], 2.2), P["zcloth"], sh=0.4)
        s.paint(s.m().ell(x + dx * 2.9, y + dy * 2.9, 1.1), P["zskin"], sh=0.3)
    gore(s, ((12, 24, 1.2), (24, 22, 1.0), (15, 15, 1.4)))
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


# ---------------------------------------------------------------- props (decorative, placed by chunk_manager.gd)

def gable(s, x0, y0, x1, y1, col, horizontal=True):
    """Pitched roof seen from above: lit half up/left, shaded half down/right, dark ridge."""
    s.paint(s.m().rect(x0, y0, x1, y1, 0.3), col, sh=0)
    if horizontal:
        ym = (y0 + y1) / 2
        s.paint(s.m().rect(x0 + 0.3, ym, x1 - 0.3, y1 - 0.3), dk(col, 0.8), sh=0, edge=False)
        s.paint(s.m().rect(x0 + 0.3, ym - 0.35, x1 - 0.3, ym + 0.35), dk(col, 0.62), sh=0, edge=False)
    else:
        xm = (x0 + x1) / 2
        s.paint(s.m().rect(xm, y0 + 0.3, x1 - 0.3, y1 - 0.3), dk(col, 0.8), sh=0, edge=False)
        s.paint(s.m().rect(xm - 0.35, y0 + 0.3, xm + 0.35, y1 - 0.3), dk(col, 0.62), sh=0, edge=False)


def shingles(s, x0, y0, x1, y1, col, step=1.6):
    m = s.m()
    y = y0 + step
    while y < y1:
        m.rect(x0 + 0.4, y - 0.08, x1 - 0.4, y + 0.08)
        y += step
    fill(s.img, m.im, dk(col, 0.7) + (70,))


def house(w, h):
    """Gable-roofed house that covers its whole footprint (light neutral roof, tinted in game with modulate)."""
    def f():
        s = Spr(w, h)
        col = P["hroof"]
        gable(s, 0.3, 0.3, w - 0.3, h - 0.3, col, horizontal=w >= h)
        shingles(s, 0.3, 0.3, w - 0.3, h - 0.3, col)
        cx = w * 0.72 if w >= h else w * 0.3
        s.paint(s.m().rect(cx - 1, h * 0.22, cx + 1, h * 0.22 + 1.8, 0.2), P["bwall"], sh=0.5)  # chimney
        return s.drop(0.5)
    return f


def barn():
    s = Spr(32, 24)
    gable(s, 0.3, 2, 31.7, 22, P["barn"])
    m = s.m()
    for x in range(2, 31, 2):
        m.rect(x - 0.1, 2.3, x + 0.1, 21.7)
    fill(s.img, m.im, dk(P["barn"], 0.7) + (80,))
    s.paint(s.m().rect(0.3, 2, 1.3, 22).rect(30.7, 2, 31.7, 22), P["white"], sh=0)  # gable trim
    s.paint(s.m().rect(13, 5.5, 19, 8.5, 0.3), P["vent"], sh=0.4)  # cupola
    return s.drop(0.7)


def church():
    s = Spr(32, 40)
    roof = mix(P["roof"], P["hroof"], 0.3)
    walls = P["stone"][1]
    s.paint(s.m().rect(5, 11, 27, 39.5, 0.3), walls, sh=0.6)
    gable(s, 5.6, 11.5, 26.4, 39, roof, horizontal=False)
    s.paint(s.m().rect(0.5, 22, 31.5, 30, 0.3), walls, sh=0.6)  # transept
    gable(s, 1.1, 22.5, 30.9, 29.5, roof, horizontal=True)
    s.paint(s.m().rect(10, 1, 22, 13, 0.3), walls, sh=0.8)  # tower with a pyramid roof
    s.paint(s.m().poly([(10.6, 1.6), (21.4, 1.6), (16, 7)]), mix(roof, (255, 255, 255), 0.12), sh=0, edge=False)
    s.paint(s.m().poly([(10.6, 1.6), (16, 7), (10.6, 12.4)]), roof, sh=0, edge=False)
    s.paint(s.m().poly([(21.4, 1.6), (21.4, 12.4), (16, 7)]), dk(roof, 0.82), sh=0, edge=False)
    s.paint(s.m().poly([(10.6, 12.4), (16, 7), (21.4, 12.4)]), dk(roof, 0.7), sh=0, edge=False)
    s.paint(s.m().rect(15.5, 4, 16.5, 10).rect(13.8, 5.6, 18.2, 6.6), P["white"], sh=0)  # cross
    return s.drop(1.0)


def silo():
    s = Spr(16, 24)
    s.paint(s.m().rect(6, 13, 10, 23, 0.4), P["metal"], sh=0.4)  # loading chute
    s.paint(s.m().ell(8, 8, 7), P["metalroof"], sh=1.4, light=0.8)
    ring = s.m().ell(8, 8, 5)
    ring.ell(8, 8, 4.5, v=0)
    fill(s.img, ring.im, dk(P["metalroof"], 0.75) + (180,))
    s.paint(s.m().ell(8, 8, 1.6), dk(P["metalroof"], 0.7), sh=0.3)
    return s.drop(1.0)


def tree():
    s = Spr(16, 16)
    s.paint(s.m().ell(8, 7.6, 6.2, 5.9), P["canopy"], sh=2.2)
    rnd = random.Random(31)
    m = s.m()
    for _ in range(5):
        m.ell(rnd.uniform(5.5, 9), rnd.uniform(5, 8.5), rnd.uniform(1.2, 2.0))
    fill(s.img, m.im, P["canopy_lt"] + (200,))
    return s.drop(0.8)


def dead_tree():
    s = Spr(16, 16)
    col = mix(P["wood"], P["char"], 0.55)
    m = s.m()
    rnd = random.Random(41)
    for k in range(6):
        a = k / 6 * 6.283 + rnd.uniform(-0.3, 0.3)
        r = rnd.uniform(4.5, 6.8)
        ex, ey = 8 + math.cos(a) * r, 8 + math.sin(a) * r
        m.line([(8, 8), (ex, ey)], 0.55)
        b = a + rnd.choice((-0.7, 0.7))
        mx, my = 8 + math.cos(a) * r * 0.6, 8 + math.sin(a) * r * 0.6
        m.line([(mx, my), (mx + math.cos(b) * 2.2, my + math.sin(b) * 2.2)], 0.35)
    s.paint(m, col, sh=0)
    s.paint(s.m().ell(8, 8, 1.4), dk(col, 0.8), sh=0.4)
    return s.drop(0.5)


def fence():
    s = Spr(16, 4)
    s.paint(s.m().rect(0, 1.2, 16, 1.8).rect(0, 2.4, 16, 3.0), P["wood"], sh=0, edge=False)
    s.paint(s.m().rect(0, 0.8, 1.2, 3.4).rect(7.4, 0.8, 8.6, 3.4).rect(14.8, 0.8, 16, 3.4), dk(P["wood"], 0.85), sh=0)
    return s.drop(0.25)


def jetty():
    """Wooden jetty, shore end at the bottom."""
    s = Spr(8, 24)
    s.paint(s.m().rect(1, 0.5, 7, 24), P["wood"], sh=0.4)
    m = s.m()
    for k in range(16):
        m.rect(1.2, k * 1.5 + 0.6, 6.8, k * 1.5 + 0.75)
    fill(s.img, m.im, dk(P["wood"], 0.65) + (170,))
    s.paint(s.m().ell(1.2, 1.2, 0.8).ell(6.8, 1.2, 0.8).ell(1.2, 12, 0.8).ell(6.8, 12, 0.8), dk(P["wood"], 0.6), sh=0)
    return s.drop(0.5)


def gas_station():
    s = Spr(32, 16)
    s.paint(s.m().rect(0.5, 1, 31.5, 15, 0.5), P["white"], sh=0.8)
    s.paint(s.m().rect(0.5, 1, 31.5, 2.6, 0.3).rect(0.5, 13.4, 31.5, 15, 0.3), P["red"], sh=0, edge=False)  # fascia
    m = s.m()
    for x in (8, 16, 24):
        m.rect(x - 0.15, 3, x + 0.15, 13)
    fill(s.img, m.im, dk(P["white"], 0.8) + (150,))
    s.paint(s.m().ell(4, 8, 1.2).ell(28, 8, 1.2), P["skylight"], sh=0)
    return s.drop(0.6)


def fuel_tank():
    s = Spr(16, 16)
    s.paint(s.m().ell(8, 8, 7.2), P["white"], sh=1.4, light=0.6)
    ring = s.m().ell(8, 8, 6.4)
    ring.ell(8, 8, 6.0, v=0)
    fill(s.img, ring.im, dk(P["white"], 0.75) + (170,))
    s.paint(s.m().ell(8, 8, 1.4), P["metal"], sh=0.3)
    s.paint(s.m().line([(8, 8), (13.5, 11)], 0.5), P["metal"], sh=0)  # walkway
    return s.drop(0.8)


def woodpile():
    s = Spr(12, 8)
    for y in (1.6, 3.6, 5.6):
        s.paint(s.m().rect(1, y - 1, 11, y + 1, 1.0), P["wood"], sh=0.4)
    m = s.m()
    for y in (1.6, 3.6, 5.6):
        m.ell(1.8, y, 0.75)
    s.paint(m, mix(P["wood"], (255, 230, 180), 0.35), sh=0, edge=False)  # cut ends
    return s.drop(0.4)


def water_tower():
    s = Spr(16, 24)
    s.paint(s.m().line([(4, 9), (2, 23)], 0.6).line([(12, 9), (14, 23)], 0.6).line([(3, 17), (13, 17)], 0.4), P["metal"], sh=0)
    s.paint(s.m().ell(8, 8, 6.5), P["metalroof"], sh=1.2, light=0.6)
    s.paint(s.m().poly([(8, 3), (12.5, 8), (8, 13), (3.5, 8)]), mix(P["metalroof"], (255, 255, 255), 0.1), sh=0, edge=False)
    s.paint(s.m().ell(8, 8, 1.0), P["metal"], sh=0)
    return s.drop(1.4)


def car():
    """Car seen from above, front to the right. Light paint: tinted in game with modulate."""
    s = Spr(12, 6)
    s.paint(s.m().rect(0.4, 0.5, 11.6, 5.5, 1.6), P["car"], sh=0.6)
    s.paint(s.m().rect(7.2, 1.1, 8.8, 4.9, 0.4).rect(2.2, 1.2, 3.2, 4.8, 0.3), P["glass"], sh=0, edge=False)
    s.paint(s.m().rect(3.4, 1.2, 7.0, 4.8, 0.5), mix(P["car"], (255, 255, 255), 0.15), sh=0, edge=False)
    return s.drop(0.25)


SPRITES = {
    "heli": heli, "rotor": rotor, "bullet": bullet, "shambler": shambler, "runner": runner, "brute": brute,
    "boss": boss, "survivor": survivor, "helipad": helipad, "turret": turret, "hangar": hangar,
    "crate": crate, "radio_tower": radio_tower, "wreck": wreck, "den": den, "muzzle": muzzle,
    "church": church, "barn": barn, "silo": silo, "tree": tree, "dead_tree": dead_tree, "fence": fence,
    "jetty": jetty, "gas_station": gas_station, "fuel_tank": fuel_tank, "woodpile": woodpile,
    "water_tower": water_tower, "car": car, "house": house(16, 16), "house_2x1": house(32, 16), "house_2x2": house(32, 32),
}
SIZES = {  # logical sizes, see assets/sprites/README.md
    "heli": (32, 32), "rotor": (32, 32), "bullet": (4, 4), "shambler": (16, 16), "runner": (16, 16),
    "brute": (24, 24), "boss": (48, 48), "survivor": (8, 8), "tiles": (16 * len(TILES), 16), "helipad": (48, 48),
    "turret": (16, 16), "hangar": (32, 32), "sandbag": (256, 16), "wire": (256, 16), "crate": (16, 16), "radio_tower": (16, 32),
    "wreck": (32, 32), "den": (32, 32), "muzzle": (8, 8), "explosion": (96, 16),
    "church": (32, 40), "barn": (32, 24), "silo": (16, 24), "tree": (16, 16), "dead_tree": (16, 16), "fence": (16, 4),
    "jetty": (8, 24), "gas_station": (32, 16), "fuel_tank": (16, 16), "woodpile": (12, 8), "water_tower": (16, 24),
    "car": (12, 6), "house": (16, 16), "house_2x1": (32, 16), "house_2x2": (32, 32),
}


def main():
    global P
    for variant, style in STYLES.items():
        if variant != "b":  # Field Map is the only shipped style; a/c kept in STYLES for reference
            continue
        P = style
        out = os.path.join(ROOT, variant)
        os.makedirs(out, exist_ok=True)
        images = {name: f().out() for name, f in SPRITES.items()}
        images["tiles"] = tiles()
        images["explosion"] = explosion()
        images["sandbag"] = connected(sandbag_frame)
        images["wire"] = connected(wire_frame)
        images.update(avatars())
        images.update(infected())
        for name, im in images.items():
            w, h = SIZES[name]
            assert im.size == (w * OUT, h * OUT), (name, im.size)
            im.save(os.path.join(out, name + ".png"))
        avatar_sheet(images)
        print(variant, len(images), "images")


# ---------------------------------------------------------------- profile portraits (P4)

# One row per portrait, drawn back to front in avatar(). Sex only sets lips and jaw.
AVATARS = (
    dict(seed=1, bg=(160, 166, 132), skin=(206, 156, 116), hair=(52, 40, 32), jacket=(116, 124, 86), jaw=True,
         style="buzz", head="helmet", gear=(92, 100, 70), headset=True, bandolier=True, beard="stubble"),
    dict(seed=2, bg=(176, 160, 130), skin=(234, 196, 160), hair=(120, 84, 52), jacket=(96, 94, 84), lips=True,
         style="long", head="helmet", gear=(176, 166, 132), headset=True),
    dict(seed=3, bg=(146, 160, 150), skin=(176, 128, 92), hair=(70, 52, 38), jacket=(162, 140, 96), jaw=True,
         style=None, head="cap", gear=(78, 96, 70), beard="full"),
    dict(seed=4, bg=(164, 152, 140), skin=(232, 190, 156), hair=(186, 150, 96), jacket=(70, 98, 126), lips=True,
         style="long", head=None, sunglasses=True),
    dict(seed=5, bg=(150, 156, 142), skin=(120, 82, 58), hair=(40, 34, 30), jacket=(116, 124, 86), jaw=True,
         style="short", head="cap", gear=(170, 160, 120), camo=((116, 124, 86), (64, 70, 50), (176, 160, 116))),
    dict(seed=6, bg=(140, 148, 160), skin=(216, 168, 128), hair=(60, 46, 36), jacket=(64, 62, 60),
         style="buzz", head="helmet", gear=(54, 54, 52), mask=True),
    dict(seed=7, bg=(172, 164, 146), skin=(158, 108, 76), hair=(44, 32, 26), jacket=(96, 104, 70), lips=True,
         style="ponytail", head="cap", gear=(86, 102, 118)),
    dict(seed=8, bg=(156, 150, 130), skin=(226, 186, 150), hair=(30, 28, 26), jacket=(116, 124, 86), jaw=True,
         style="buzz", head=None, beard="full", sunglasses=True),
    dict(seed=9, bg=(160, 162, 150), skin=(110, 72, 50), hair=(28, 22, 20), jacket=(96, 104, 70), lips=True,
         style="curly", head="helmet", gear=(116, 124, 86), headset=True),
    dict(seed=10, bg=(170, 158, 138), skin=(222, 178, 136), hair=(92, 70, 48), jacket=(136, 118, 92), jaw=True,
         style="short", head="cap", gear=(96, 104, 70), beard="stubble", camo=((116, 124, 86), (64, 70, 50), (176, 160, 116))),
    dict(seed=11, bg=(148, 158, 160), skin=(186, 140, 100), hair=(64, 46, 34), jacket=(70, 70, 68),
         style="long", head=None, mask=True),
    dict(seed=12, bg=(164, 154, 156), skin=(196, 146, 108), hair=(120, 96, 70), jacket=(70, 98, 126), lips=True,
         style="long", head=None, headset=True),
)
SIZES.update({f"avatar_{i:02d}": (48, 48) for i in range(len(AVATARS))})


def camo_blobs(s, mask_im, seed, cols):
    """Blotchy face camo: each colour is a set of random blobs clipped to the face."""
    rnd = random.Random(seed)
    for col in cols:
        blobs = s.m()
        for _ in range(12):
            blobs.ell(rnd.uniform(13, 35), rnd.uniform(12, 30), rnd.uniform(2.4, 4.2), rnd.uniform(1.8, 3.2))
        fill(s.img, ImageChops.multiply(blobs.im, mask_im).filter(ImageFilter.GaussianBlur(0.25 * SS)), col + (235,))


def avatar(a):
    """Head-and-shoulders bust, 48 px logical. Layers: backdrop, back hair, jacket, neck, head, face, hair, headgear, gear."""
    s = Spr(48, 48)
    skin, hair, gear, style = a["skin"], a["hair"], a.get("gear"), a["style"]
    s.paint(s.m().rect(0, 0, 48, 48, 5), a["bg"], sh=0, edge=False)
    if style == "long":
        s.paint(s.m().ell(24, 24.5, 11.6, 14.2), hair, sh=0)
    if style == "ponytail":
        s.paint(s.m().ell(33.4, 25, 3.4, 8.2), hair, sh=0.6)
    s.paint(s.m().rect(6.5, 37, 41.5, 52, 7), a["jacket"], sh=1.0)
    s.paint(s.m().poly([(19.4, 37), (24, 43.2), (28.6, 37)]), dk(a["jacket"], 0.55), sh=0, edge=False)
    if a.get("bandolier"):
        s.paint(s.m().line([(9.6, 38), (35.5, 52)], 1.4), P["strap"], sh=0, edge=False)
    s.paint(s.m().rect(20.6, 28, 27.4, 39.5, 1.2), dk(skin, 0.9), sh=0.3, edge=False)
    s.paint(s.m().ell(15.4, 22.2, 1.9, 2.6).ell(32.6, 22.2, 1.9, 2.6), skin, sh=0.3)
    head = s.m().ell(24, 20.6, 8.6, 9.8)
    if a.get("jaw"):
        head.ell(24, 25.6, 7.9, 5.0)
    s.paint(head, skin, sh=0.9)
    if a.get("camo"):
        camo_blobs(s, head.im, a["seed"], a["camo"])
    if a.get("beard"):  # cheeks and chin of the head silhouette, plus a chin tuft
        zone = s.m().rect(0, 24.2, 48, 48).im
        beard = s.m()
        beard.im = ImageChops.lighter(ImageChops.multiply(head.im, zone), s.m().ell(24, 31.2, 5.2, 3.4).im)
        s.paint(beard, hair if a["beard"] == "full" else mix(skin, hair, 0.3), sh=0.3, edge=False)
    s.paint(s.m().line([(24.5, 22.6), (23.6, 25.4), (25.0, 25.7)], 0.45), dk(skin, 0.7), sh=0, edge=False)
    if not a.get("sunglasses") and not a.get("mask"):
        s.paint(s.m().ell(20.6, 21.4, 1.25, 1.0).ell(27.4, 21.4, 1.25, 1.0), (52, 42, 36), sh=0, edge=False)
        fill(s.img, s.m().line([(18.4, 19.4), (22.6, 19.0)], 0.7).line([(25.4, 19.0), (29.6, 19.4)], 0.7).im,
             dk(hair, 0.9) + (255,))
    if style in ("short", "long", "ponytail"):
        side = 33.5 if style == "long" else 19.2  # long hair falls past the ears
        top = s.m().ell(24, 14.0, 9.0, 5.2).rect(14.4, 14, 17.6, side, 1.4).rect(30.4, 14, 33.6, side, 1.4)
        s.paint(top, hair, sh=0.5)
    elif style == "buzz":
        s.paint(s.m().ell(24, 14.8, 8.7, 4.4), hair, sh=0.5)  # cropped, hugs the scalp
    elif style == "curly":
        curls = s.m()
        for x, y in ((15.8, 16), (17.6, 11.6), (21.6, 9.4), (26.4, 9.4), (30.4, 11.6), (32.2, 16)):
            curls.ell(x, y, 2.9, 2.7)
        s.paint(curls.ell(24, 13.6, 7.8, 4.6), hair, sh=0.6)
    if a.get("head") == "helmet":
        s.paint(s.m().ell(24, 15.0, 10.2, 8.0).rect(0, 19.2, 48, 48, 0, v=0), gear, sh=1.2, light=0.6)
        s.paint(s.m().rect(13.6, 17.6, 34.4, 19.6, 1.0), dk(gear, 0.7), sh=0, edge=False)
    elif a.get("head") == "cap":
        s.paint(s.m().ell(24, 14.6, 9.2, 6.0).rect(0, 18.4, 48, 48, 0, v=0), gear, sh=1.0)
        s.paint(s.m().rect(14.6, 16.6, 33.4, 18.2, 0.6), dk(gear, 0.7), sh=0, edge=False)  # hatband
        s.paint(s.m().ell(24, 18.4, 11.4, 1.6), dk(gear, 0.85), sh=0.4)  # brim
    if a.get("headset"):
        band = (40, 40, 40, 255)
        fill(s.img, s.m().line([(13.6, 21.0), (13.8, 15.4), (18.4, 8.9), (24, 7.9), (29.6, 8.9), (34.2, 15.4), (34.4, 21.0)], 0.9).im, band)
        s.paint(s.m().ell(13.6, 22.6, 2.2, 2.9), band[:3], sh=0.3)
        s.paint(s.m().line([(13.8, 25.2), (15.2, 28.8), (19.4, 30.6)], 0.7).ell(19.8, 30.9, 1.0, 0.9), band[:3], sh=0, edge=False)
    if a.get("mask"):  # gas mask: body over nose and mouth, eyepieces, filter, straps
        s.paint(s.m().rect(15.2, 22.0, 32.8, 34.4, 4.5), P["metal"], sh=0.9)
        s.paint(s.m().ell(19.2, 21.6, 3.5, 2.5).ell(28.8, 21.6, 3.5, 2.5), P["glass"], sh=0.5)
        s.paint(s.m().ell(24, 36.2, 3.6, 2.8), dk(P["metal"], 0.7), sh=0.6)
        s.paint(s.m().line([(15.4, 27.4), (9.4, 25.6)], 0.9).line([(32.6, 27.4), (38.6, 25.6)], 0.9), dk(P["metal"], 0.6), sh=0, edge=False)
    elif a.get("lips"):
        fill(s.img, s.m().ell(24, 29.4, 2.2, 0.9).im, P["red"] + (255,))
    else:
        fill(s.img, s.m().line([(21.6, 29.6), (24, 30.1), (26.4, 29.6)], 0.5).im, (70, 44, 36, 255))
    if a.get("sunglasses"):
        lens = s.m().rect(14.4, 19.4, 23.4, 23.4, 1.6).rect(24.6, 19.4, 33.6, 23.4, 1.6)
        s.paint(lens, P["glass"], sh=0, edge=False)
        fill(s.img, s.m().line([(23.4, 20.4), (24.6, 20.4)], 0.6).line([(14.4, 20.4), (13.0, 20.6)], 0.6)
             .line([(33.6, 20.4), (35.0, 20.6)], 0.6).im, (30, 30, 30, 255))
        fill(s.img, s.m().ell(17.4, 21.0, 0.9, 0.6).ell(27.6, 21.0, 0.9, 0.6).im, (170, 186, 190, 200))
    return s.out()


def avatars():
    return {f"avatar_{i:02d}": avatar(a) for i, a in enumerate(AVATARS)}


def avatar_sheet(images):
    """docs/avatars.png: the portraits large, then at the 48 px they have in game (Art.SCALE 0.25)."""
    names = [f"avatar_{i:02d}" for i in range(len(AVATARS))]
    big, pad, n = 4 * 48, 24, len(names) // 2
    small_w = 48
    w = n * big + (n + 1) * pad
    h = 2 * big + 3 * pad + small_w + pad
    sheet = Image.new("RGBA", (w, h), (196, 192, 166, 255))
    for i, name in enumerate(names):
        x, y = pad + (i % n) * (big + pad), pad + (i // n) * (big + pad)
        sheet.paste(images[name], (x, y), images[name])
    for i, name in enumerate(names):
        im = images[name].resize((small_w, small_w), Image.LANCZOS)
        sheet.paste(im, (pad + i * (small_w + 16), 2 * (big + pad) + pad), im)
    sheet.save(os.path.join(ROOT, "..", "..", "docs", "avatars.png"))


# ---------------------------------------------------------------- new infected (P9)

def screamer():
    """Thin, hunched, jaw hanging open; a pale throat sac and raised claws."""
    s = Spr(16, 16)
    skin = mix(P["zskin"], (230, 226, 210), 0.35)
    arms = s.m().line([(5.4, 9.0), (3.8, 6.2), (4.6, 3.4)], 1.0).line([(10.6, 9.0), (12.2, 6.2), (11.4, 3.4)], 1.0)
    zombie(s, skin, dk(P["zcloth"], 0.9), (8, 10.4, 3.0, 3.0), (8, 6.8, 2.3, 2.1), arms, tears=((7.0, 11.4, 0.8),), blood=((9.0, 11.0, 0.7),))
    s.paint(s.m().ell(8, 9.4, 1.9, 1.4), mix(P["flesh"], (240, 200, 190), 0.4), sh=0.4, edge=False)  # throat sac
    s.paint(s.m().ell(8, 7.6, 1.2, 1.5), (60, 28, 28), sh=0, edge=False)  # open mouth
    return s.drop(0.6)


def spitter():
    """Swollen, yellow-green neck and cheeks, dripping acid; arms held low."""
    s = Spr(16, 16)
    skin = mix(P["zskin"], (180, 190, 70), 0.45)
    arms = s.m().line([(5.4, 9.4), (4.6, 11.4), (5.6, 13.0)], 1.2).line([(10.6, 9.4), (11.4, 11.4), (10.4, 13.0)], 1.2)
    zombie(s, skin, P["zcloth"], (8, 10.2, 3.6, 3.0), (8, 7.0, 2.3, 2.1), arms, tears=((6.4, 11.0, 0.8),), blood=((9.4, 11.4, 0.7),))
    acid = (176, 200, 60)
    s.paint(s.m().ell(5.6, 8.6, 1.4, 1.2).ell(10.4, 8.6, 1.4, 1.2), acid, sh=0.3, edge=False)  # swollen glands
    s.paint(s.m().ell(8, 5.4, 0.9, 1.1).ell(8, 3.8, 0.5), acid, sh=0, edge=False)  # spit
    return s.drop(0.6)


def crawler():
    """Flat, legless torso dragging itself forward on both arms."""
    s = Spr(16, 16)
    skin = dk(P["zskin"], 0.92)
    arms = s.m().line([(4.0, 8.6), (2.6, 6.0), (4.0, 3.6)], 1.2).line([(12.0, 8.6), (13.4, 6.0), (12.0, 3.6)], 1.2)
    zombie(s, skin, dk(P["zcloth"], 0.85), (8, 9.6, 3.3, 3.6), (8, 5.6, 1.9, 1.8), arms, tears=((6.8, 10.6, 0.8),), blood=((9.4, 11.4, 0.9), (7.2, 12.4, 0.6)))
    s.paint(s.m().ell(8, 13.4, 1.8, 1.1), P["flesh"], sh=0, edge=False)  # torn-off stump
    return s.drop(0.5)


def bloater():
    """Huge round gas bag with a taut, translucent belly and tiny limbs."""
    s = Spr(28, 28)
    skin = mix(P["zskin"], (170, 180, 110), 0.4)
    s.paint(s.m().line([(8, 14), (5, 10), (6.4, 6)], 2.2).line([(20, 14), (23, 10), (21.6, 6)], 2.2), skin, sh=0.6)
    s.paint(s.m().ell(14, 16, 10.4, 9.8), mix(skin, P["zcloth"], 0.35), sh=2.0)
    belly = s.m().ell(14, 16.6, 8.2, 7.6)
    s.paint(belly, mix(skin, (210, 214, 130), 0.5), sh=1.6, light=1.2, edge=False)
    veins = s.m()
    for x0, y0, x1, y1 in ((9, 13, 13, 17), (18, 12, 15, 18), (11, 21, 15, 19), (19, 20, 16, 17)):
        veins.line([(x0, y0), (x1, y1)], 0.35)
    s.paint(veins, dk(P["flesh"], 0.9), sh=0, edge=False)
    s.paint(s.m().ell(14, 6.4, 3.0, 2.8), skin, sh=1.0)
    s.paint(s.m().ell(14, 5.8, 1.1, 0.8), dk(skin, 0.65), sh=0, edge=False)
    return s.drop(1.0)


def brute_armored():
    """Brute in welded plates: a riveted front shield and shoulder guards (the face of the sprite is up)."""
    s = brute()
    plate = P["metal"]
    s.paint(s.m().ell(5.2, 11.4, 3.6, 3.2).ell(18.8, 11.4, 3.6, 3.2), plate, sh=0.9, light=0.5)  # pauldrons
    s.paint(s.m().rect(6.4, 6.6, 17.6, 12.4, 1.6), dk(plate, 1.05), sh=1.0, light=0.6)  # front plate
    s.paint(s.m().rect(7.6, 7.6, 16.4, 8.2, 0.2), mix(plate, (255, 255, 255), 0.25), sh=0, edge=False)
    rivets = s.m()
    for x, y in ((8, 10.8), (12, 11.4), (16, 10.8), (8, 7.0), (16, 7.0)):
        rivets.ell(x, y, 0.35)
    s.paint(rivets, mix(plate, (255, 255, 255), 0.5), sh=0, edge=False)
    s.paint(s.m().ell(12, 5.2, 2.6, 2.0), dk(plate, 0.9), sh=0.7)  # helmet
    s.paint(s.m().rect(10.2, 5.4, 13.8, 6.0, 0.2), P["glass"], sh=0, edge=False)
    return s.drop(0.9)


def infected():
    return {n: f().out() for n, f in (("screamer", screamer), ("spitter", spitter), ("crawler", crawler),
                                      ("bloater", bloater), ("brute_armored", brute_armored))}


SIZES.update({"screamer": (16, 16), "spitter": (16, 16), "crawler": (16, 16), "bloater": (28, 28), "brute_armored": (24, 24)})


if __name__ == "__main__":
    main()
