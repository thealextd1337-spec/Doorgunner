"""Procedurally generate the pixel art sprites for Doorgunner into assets/sprites/."""
import os
import random

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sprites")
random.seed(1337)

# palette
CLEAR = (0, 0, 0, 0)
OLIVE = (96, 110, 64, 255)
OLIVE_DK = (62, 72, 40, 255)
GLASS = (36, 44, 52, 255)
GRAY = (120, 120, 120, 255)
GRAY_DK = (70, 70, 70, 255)
GRAY_LT = (160, 160, 160, 255)
BLACK = (24, 24, 24, 255)
PURPLE = (120, 60, 150, 255)
PURPLE_LT = (160, 100, 190, 255)
PURPLE_DK = (70, 30, 90, 255)
MAGENTA = (220, 60, 200, 255)
MAGENTA_LT = (255, 150, 240, 255)
PALE = (230, 220, 240, 255)
SLIME = (110, 150, 80, 255)
YELLOW = (255, 220, 80, 255)
WHITE = (255, 255, 230, 255)
ORANGE = (240, 130, 40, 255)
RED = (190, 50, 30, 255)
SKIN = (230, 190, 150, 255)
BLUE = (60, 90, 170, 255)
TAN = (190, 170, 120, 255)
TAN_DK = (130, 110, 70, 255)
GRASS_A = (84, 120, 60, 255)
GRASS_B = (100, 136, 70, 255)
FOREST = (46, 80, 44, 255)
FOREST_LT = (64, 100, 56, 255)
WATER = (50, 90, 150, 255)
WATER_LT = (90, 130, 190, 255)
SAND = (200, 184, 130, 255)
SAND_DK = (176, 160, 110, 255)
ASPHALT = (80, 80, 84, 255)
CONCRETE = (140, 140, 136, 255)
CONCRETE_DK = (100, 100, 96, 255)


def new(w, h, bg=CLEAR):
    img = Image.new("RGBA", (w, h), bg)
    return img, ImageDraw.Draw(img)


def outline(img, color):
    """1px darker outline: fill transparent pixels 4-adjacent to opaque ones."""
    w, h = img.size
    px = img.load()
    edge = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] > 0:
                        edge.append((x, y))
                        break
    for x, y in edge:
        px[x, y] = color


def noise(d, box, a, b, ratio=0.3):
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            d.point((x, y), b if random.random() < ratio else a)


def save(img, name, w, h):
    assert img.size == (w, h), (name, img.size)
    img.save(os.path.join(OUT, name))


def heli():
    img, d = new(32, 32)
    d.rectangle((12, 4, 19, 19), OLIVE)
    d.rectangle((13, 3, 18, 3), OLIVE)
    d.rectangle((13, 5, 18, 9), GLASS)
    d.rectangle((15, 19, 16, 28), OLIVE_DK)
    d.rectangle((17, 24, 17, 28), OLIVE_DK)
    d.rectangle((12, 27, 19, 27), GRAY_DK)  # tail rotor
    d.rectangle((9, 8, 9, 18), GRAY_DK)  # skids
    d.rectangle((22, 8, 22, 18), GRAY_DK)
    d.rectangle((10, 11, 11, 11), GRAY_DK)
    d.rectangle((20, 11, 21, 11), GRAY_DK)
    outline(img, BLACK)
    save(img, "heli.png", 32, 32)


def rotor():
    img, d = new(32, 32)
    c = (70, 70, 70, 170)
    d.rectangle((15, 1, 16, 30), c)
    d.rectangle((1, 15, 30, 16), c)
    save(img, "rotor.png", 32, 32)


def bullets():
    img, d = new(4, 4)
    d.rectangle((0, 0, 3, 3), YELLOW)
    d.rectangle((1, 1, 2, 2), WHITE)
    save(img, "bullet.png", 4, 4)
    img, d = new(6, 6)
    d.ellipse((0, 0, 5, 5), MAGENTA)
    d.rectangle((2, 2, 3, 3), MAGENTA_LT)
    save(img, "enemy_bullet.png", 6, 6)


def walker():
    img, d = new(16, 16)
    for y in (5, 9):  # 4 legs
        d.line((2, y + 2, 5, y), PURPLE_DK)
        d.line((10, y, 13, y + 2), PURPLE_DK)
    d.ellipse((5, 4, 10, 11), PURPLE)
    d.point((6, 6), PALE)
    d.point((9, 6), PALE)
    outline(img, BLACK)
    save(img, "walker.png", 16, 16)


def runner():
    img, d = new(16, 16)
    d.line((3, 10, 6, 7), PURPLE)
    d.line((9, 7, 12, 10), PURPLE)
    d.line((4, 3, 6, 5), PURPLE)
    d.line((9, 5, 11, 3), PURPLE)
    d.rectangle((6, 2, 9, 12), PURPLE_LT)
    d.point((6, 4), PALE)
    d.point((9, 4), PALE)
    outline(img, PURPLE_DK)
    save(img, "runner.png", 16, 16)


def spitter():
    img, d = new(16, 16)
    d.ellipse((2, 3, 13, 13), PURPLE)
    d.ellipse((4, 6, 11, 12), SLIME)
    d.rectangle((6, 2, 9, 4), BLACK)  # mouth
    d.point((5, 4), PALE)
    d.point((10, 4), PALE)
    outline(img, PURPLE_DK)
    save(img, "spitter.png", 16, 16)


def flyer():
    img, d = new(16, 16)
    d.polygon(((1, 7), (7, 5), (7, 9)), PURPLE)  # wings
    d.polygon(((14, 7), (8, 5), (8, 9)), PURPLE)
    d.rectangle((6, 3, 9, 11), PURPLE_DK)
    d.point((6, 4), PALE)
    d.point((9, 4), PALE)
    outline(img, BLACK)
    save(img, "flyer.png", 16, 16)


def boss():
    img, d = new(48, 48)
    for i, y in enumerate((14, 22, 30)):  # 6 legs
        d.line((3, y + 8, 14, y), PURPLE_DK, 2)
        d.line((44, y + 8, 33, y), PURPLE_DK, 2)
    d.ellipse((12, 10, 35, 42), PURPLE)
    d.ellipse((16, 4, 31, 16), PURPLE_LT)
    d.ellipse((17, 22, 30, 35), MAGENTA)  # glowing core
    d.ellipse((20, 25, 27, 32), MAGENTA_LT)
    d.rectangle((20, 8, 21, 9), PALE)
    d.rectangle((26, 8, 27, 9), PALE)
    outline(img, BLACK)
    save(img, "boss.png", 48, 48)


def survivor():
    img, d = new(8, 8)
    d.rectangle((3, 1, 4, 2), SKIN)
    d.rectangle((2, 3, 5, 5), BLUE)
    d.point((3, 6), GRAY_DK)
    d.point((4, 6), GRAY_DK)
    outline(img, BLACK)
    save(img, "survivor.png", 8, 8)


def tiles():
    img, d = new(128, 16)
    t = lambda i: (i * 16, 0, i * 16 + 16, 16)
    noise(d, t(0), GRASS_A, GRASS_B)
    d.rectangle((16, 0, 31, 15), FOREST)
    for cx, cy in ((19, 4), (27, 6), (22, 12), (29, 13)):
        d.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), FOREST_LT)
    d.rectangle((32, 0, 47, 15), WATER)
    for y in (3, 8, 13):
        d.line((34 + (y % 2) * 4, y, 38 + (y % 2) * 4, y), WATER_LT)
    noise(d, t(3), SAND, SAND_DK, 0.15)
    noise(d, t(4), ASPHALT, GRAY_DK, 0.1)
    d.rectangle((71, 2, 72, 6), YELLOW)
    d.rectangle((71, 10, 72, 14), YELLOW)
    d.rectangle((80, 0, 95, 15), CONCRETE_DK)
    d.rectangle((82, 2, 93, 13), CONCRETE)
    d.rectangle((88, 4, 91, 6), GRAY_DK)  # vent
    noise(d, t(6), GRAY_DK, BLACK, 0.2)
    d.line((98, 2, 104, 9), BLACK)
    d.line((104, 9, 110, 13), BLACK)
    for px in ((100, 12), (108, 4), (104, 3), (110, 10)):
        d.point(px, GRAY)
    noise(d, t(7), CONCRETE, CONCRETE_DK, 0.15)
    d.rectangle((112, 7, 113, 8), YELLOW)  # small marker only; full stripes tile badly
    save(img, "tiles.png", 128, 16)


def helipad():
    img, d = new(48, 48)
    d.ellipse((1, 1, 46, 46), CONCRETE_DK)
    d.ellipse((4, 4, 43, 43), WHITE)
    d.ellipse((6, 6, 41, 41), CONCRETE_DK)
    d.rectangle((16, 14, 19, 33), WHITE)
    d.rectangle((28, 14, 31, 33), WHITE)
    d.rectangle((16, 22, 31, 25), WHITE)
    save(img, "helipad.png", 48, 48)


def turret():
    img, d = new(16, 16)
    d.ellipse((3, 5, 12, 14), GRAY)
    d.ellipse((5, 7, 10, 12), GRAY_LT)
    d.rectangle((7, 1, 8, 9), GRAY_DK)
    outline(img, BLACK)
    save(img, "turret.png", 16, 16)


def hangar():
    img, d = new(32, 32)
    d.rectangle((0, 0, 31, 31), OLIVE_DK)
    d.rectangle((2, 2, 29, 29), OLIVE)
    d.rectangle((15, 2, 16, 25), OLIVE_DK)  # roof ridge
    d.rectangle((9, 25, 22, 31), BLACK)  # door
    save(img, "hangar.png", 32, 32)


def wall():
    img, d = new(16, 16)
    d.rectangle((0, 0, 15, 15), TAN)
    for y in (0, 5, 10):
        off = 4 if y == 5 else 0
        d.line((0, y + 4, 15, y + 4), TAN_DK)
        for x in range(off, 16, 8):
            d.line((x, y, x, y + 4), TAN_DK)
    d.line((0, 15, 15, 15), TAN_DK)
    save(img, "wall.png", 16, 16)


def crate():
    img, d = new(16, 16)
    d.rectangle((0, 0, 15, 15), OLIVE_DK)
    d.rectangle((1, 1, 14, 14), OLIVE)
    d.rectangle((7, 1, 8, 14), TAN)
    d.rectangle((1, 7, 14, 8), TAN)
    save(img, "crate.png", 16, 16)


def radio_tower():
    img, d = new(16, 32)
    d.line((7, 2, 3, 31), GRAY)
    d.line((8, 2, 12, 31), GRAY)
    for y in range(6, 32, 5):
        hw = 1 + (y - 2) * 4 // 29
        d.line((7 - hw, y, 8 + hw, y), GRAY_DK)
    d.rectangle((7, 0, 8, 1), RED)
    save(img, "radio_tower.png", 16, 32)


def wreck():
    img, d = new(32, 32)
    d.rectangle((9, 9, 18, 21), GRAY_DK)
    d.rectangle((10, 10, 17, 13), BLACK)
    d.line((18, 20, 27, 26), GRAY_DK, 2)  # bent tail
    d.line((4, 6, 24, 14), BLACK, 2)  # broken blades
    d.line((16, 2, 10, 22), BLACK, 2)
    for _ in range(14):
        d.point((random.randint(4, 27), random.randint(4, 27)), BLACK)
    for _ in range(8):
        d.point((random.randint(9, 20), random.randint(9, 22)), ORANGE)
    outline(img, BLACK)
    save(img, "wreck.png", 32, 32)


def nest():
    img, d = new(32, 32)
    d.ellipse((2, 5, 29, 30), PURPLE_DK)
    d.ellipse((4, 7, 27, 27), PURPLE)
    d.ellipse((8, 9, 22, 18), PURPLE_LT)
    for cx, cy in ((11, 13), (21, 16), (15, 23)):
        d.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), BLACK)
    save(img, "nest.png", 32, 32)


def muzzle():
    img, d = new(8, 8)
    d.line((3, 0, 3, 7), YELLOW)
    d.line((4, 0, 4, 7), YELLOW)
    d.line((0, 3, 7, 3), YELLOW)
    d.line((0, 4, 7, 4), YELLOW)
    d.line((1, 1, 6, 6), ORANGE)
    d.line((6, 1, 1, 6), ORANGE)
    d.rectangle((3, 3, 4, 4), WHITE)
    save(img, "muzzle.png", 8, 8)


def explosion():
    img, d = new(96, 16)
    frames = (
        (3, ORANGE, WHITE),
        (5, ORANGE, YELLOW),
        (7, RED, ORANGE),
        (7, GRAY_DK, RED),
        (6, (110, 110, 110, 200), GRAY_DK),
        (5, (140, 140, 140, 110), (110, 110, 110, 130)),
    )
    for i, (r, outer, inner) in enumerate(frames):
        cx, cy = i * 16 + 8, 8
        d.ellipse((cx - r, cy - r, cx + r - 1, cy + r - 1), outer)
        r2 = max(1, r // 2)
        d.ellipse((cx - r2, cy - r2, cx + r2 - 1, cy + r2 - 1), inner)
    save(img, "explosion.png", 96, 16)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for f in (heli, rotor, bullets, walker, runner, spitter, flyer, boss, survivor, tiles,
              helipad, turret, hangar, wall, crate, radio_tower, wreck, nest, muzzle, explosion):
        f()
    for name in sorted(os.listdir(OUT)):
        if name.endswith(".png"):
            print(name, Image.open(os.path.join(OUT, name)).size)
