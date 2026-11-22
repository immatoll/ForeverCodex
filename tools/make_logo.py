# Draws the Forever Codex logo: a bold gilded codex with a glowing infinity sign. Kept simple on purpose: it has to
# read at 32 px on the minimap. Writes Media/drawn*.tga (the first, hand-drawn idea; the addon uses the logo made by make_addon_logo.py).
# Usage: python tools/make_logo.py        (needs Pillow)
import math, os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 1024                      # drawn large, scaled down for smooth edges
C = S // 2
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Media")
os.makedirs(OUT, exist_ok=True)

GOLD_LIGHT, GOLD_MID, GOLD_DARK = (252, 224, 134), (214, 166, 70), (130, 88, 32)
TEAL = (84, 232, 200)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gold(t):
    return lerp(GOLD_LIGHT, GOLD_MID, t * 2) if t < 0.5 else lerp(GOLD_MID, GOLD_DARK, (t - 0.5) * 2)


def gradient(fn):
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            px[x, y] = fn(x, y)
    return img


def solid(color):
    return Image.new("RGB", (S, S), color)


GOLD_IMG = gradient(lambda x, y: gold(min(1, max(0, (x + y) / (2 * S)))))


def mask_of(draw_fn):
    m = Image.new("L", (S, S), 0)
    draw_fn(ImageDraw.Draw(m))
    return m


def fill(img, mask, source):
    img.paste(source, (0, 0), mask)


def circle(d, x, y, r, fillc):
    d.ellipse((x - r, y - r, x + r, y + r), fill=fillc)


def bevel(img, mask, depth=8):
    hi = ImageChops.subtract(mask, ImageChops.offset(mask, depth, depth))
    lo = ImageChops.subtract(mask, ImageChops.offset(mask, -depth, -depth))
    img.paste((255, 240, 180), (0, 0), hi.point(lambda v: int(v * 0.5)))
    img.paste((20, 10, 4), (0, 0), lo.point(lambda v: int(v * 0.5)))


img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ORANGE, CORE = (255, 160, 30), (255, 236, 170)


def bez(p0, pc, p2, n=24):
    return [((1 - t) ** 2 * p0[0] + 2 * t * (1 - t) * pc[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * t * (1 - t) * pc[1] + t * t * p2[1]) for t in [i / n for i in range(n + 1)]]


# dark disc with a thin gold ring
R = 480
fill(img, mask_of(lambda d: circle(d, C, C, R, 255)),
     gradient(lambda x, y: lerp((54, 36, 22), (14, 9, 6), min(1, math.hypot(x - C, y - C) / R))))
ring = mask_of(lambda d: (circle(d, C, C, R, 255), circle(d, C, C, R - 34, 0)))
fill(img, ring, GOLD_IMG)
bevel(img, ring, 6)

# the open codex: a cover under two pages, bold and simple
def page(side):
    top = bez((C + side * 8, 372), (C + side * 230, 262), (C + side * 372, 330))
    bot = bez((C + side * 372, 664), (C + side * 230, 640), (C + side * 8, 740))
    return top + bot


def grown(pts, dx, dy):
    return [(x + dx * (1 if x > C else -1), y + dy) for x, y in pts]


book = Image.new("RGBA", (S, S), (0, 0, 0, 0))
cover_pts = [(x + (30 if x > C else -30), y + 30) for x, y in page(-1)[::-1]] + [(x + (30 if x > C else -30), y + 30) for x, y in page(1)]
cover_m = mask_of(lambda d: d.polygon(cover_pts, fill=255))
book.paste((0, 0, 0), (0, 0), cover_m.filter(ImageFilter.GaussianBlur(16)).point(lambda v: int(v * 0.7)))
fill(book, cover_m, GOLD_IMG)
bevel(book, cover_m, 8)
for side in (-1, 1):
    pm = mask_of(lambda d, side=side: d.polygon(page(side), fill=255))
    fill(book, pm, gradient(lambda x, y, side=side: lerp((250, 230, 176), (176, 132, 76), min(1, abs(x - C) / 380 * 0.5 + (0.45 if abs(x - C) < 60 else 0)))))
    bevel(book, pm, 5)
fill(book, mask_of(lambda d: d.rectangle((C - 7, 366, C + 7, 742), fill=255)), solid((70, 40, 18)))
img.alpha_composite(book)

# the sign of "forever": a thick glowing infinity above the gutter
ex, ey, a, w = C, 520, 156, 62


def infinity(d):
    for i in range(361):
        t = math.radians(i)
        k = 1 + math.sin(t) ** 2
        circle(d, ex + a * math.cos(t) / k * 1.06, ey + a * math.sin(t) * math.cos(t) / k * 1.3, w / 2, 255)


inf = mask_of(infinity)
img.paste(ORANGE, (0, 0), inf.filter(ImageFilter.GaussianBlur(30)).point(lambda v: min(255, int(v * 1.6))))
fill(img, inf.filter(ImageFilter.MaxFilter(11)), solid((120, 56, 8)))
fill(img, inf, solid(ORANGE))
fill(img, mask_of(lambda d: None) if False else inf.filter(ImageFilter.MinFilter(21)), solid(CORE))

# compass points above and below
for cy, sgn in ((78, 1), (S - 78, -1)):
    pt = mask_of(lambda d, cy=cy, sgn=sgn: d.polygon([(C, cy - sgn * 70), (C + 34, cy), (C, cy + sgn * 70), (C - 34, cy)], fill=255))
    fill(img, pt.filter(ImageFilter.MaxFilter(9)), solid((40, 22, 8)))
    fill(img, pt, GOLD_IMG)
    bevel(img, pt, 4)

for size, name in ((256, "drawn"), (64, "drawn64")):
    small = img.resize((size, size), Image.LANCZOS)
    small.save(os.path.join(OUT, name + ".tga"))
    if size == 256:
        small.save(os.path.join(OUT, "drawn.png"))
print("ok")
