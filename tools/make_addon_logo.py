# Makes the addon logo (Media/logo.tga 256 px, Media/logo64.tga for the minimap, Media/logo.png) from the chosen concept.
# Usage: python tools/make_addon_logo.py <concept sheet.png>      (the logo at the top middle of the sheet)
import os, sys
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from alpha import cut

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Media")
sheet = Image.open(sys.argv[1]).convert("RGB")

BOX = (578, 0, 958, 340)          # the logo and its glow on the sheet
CX, CY, RDISC = 190, 165, 143     # the dark disc inside the ring (the ring has gaps, so it is put back by hand)
crop = sheet.crop(BOX)
logo = cut(crop, False)
disc = Image.new("L", crop.size, 0)
ImageDraw.Draw(disc).ellipse((CX - RDISC, CY - RDISC, CX + RDISC, CY + RDISC), fill=255)
logo.paste(crop, (0, 0), disc)

# square canvas around the centre of the ring
side = 372
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.paste(logo, (side // 2 - CX, side // 2 - CY))


def scaled(img, size):
    # resize with premultiplied colour so that no dark fringe appears at the soft edges
    a = np.asarray(img).astype(np.float32)
    al = a[..., 3:4] / 255
    pre = Image.fromarray(np.dstack([a[..., :3] * al, a[..., 3:4]]).astype(np.uint8), "RGBA").resize((size, size), Image.LANCZOS)
    p = np.asarray(pre).astype(np.float32)
    alpha = p[..., 3:4] / 255
    rgb = np.where(alpha > 0.004, p[..., :3] / np.maximum(alpha, 0.004), 0)
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), p[..., 3:4]]).astype(np.uint8), "RGBA")


for size, name in ((256, "logo"), (64, "logo64")):
    out = scaled(square, size)
    out.save(os.path.join(OUT, name + ".tga"))
    if size == 256:
        out.save(os.path.join(OUT, "logo.png"))
print("ok")
