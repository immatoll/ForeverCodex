# Cuts the concept sheet into single images with a transparent background (Media/concepts/*.png).
# The sheet has a near-black background. Pixels of it that touch the outside become transparent; glow on it is turned
# into a soft alpha (so it still looks right on any dark surface). Dark parts inside an icon stay.
# Usage: python tools/cut_concepts.py <sheet.png>
import os, sys
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from alpha import cut

sheet = Image.open(sys.argv[1]).convert("RGB")
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Media", "concepts")
os.makedirs(out, exist_ok=True)

boxes = {"main-icon": (40, 15, 440, 350), "title-logo": (450, 15, 1110, 400), "minimap-icon": (1120, 15, 1490, 366)}
names = [["auction-house", "inventory", "loot-overview", "quests", "database", "settings"],
         ["map", "character", "professions", "economy", "statistics", "help"]]
xs, ys = [36, 288, 538, 788, 1038, 1286], [428, 706]
for r, row in enumerate(names):
    for c, n in enumerate(row):
        boxes[n] = (xs[c], ys[r], xs[c] + 218, ys[r] + 214)

for n, b in boxes.items():
    res = cut(sheet.crop(b), n == "title-logo")
    if n == "minimap-icon":  # the dark disc inside the ring is part of the icon (the ring has gaps at the points)
        w, h = res.size
        disc = Image.new("L", (w, h), 0)
        ImageDraw.Draw(disc).ellipse((183 - 150, 178 - 150, 183 + 150, 178 + 150), fill=255)
        res.paste(sheet.crop(b), (0, 0), disc)
    res.save(os.path.join(out, n + ".png"))
print("ok")
