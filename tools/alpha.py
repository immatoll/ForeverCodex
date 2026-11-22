# Background removal for the concept art: near-black background -> transparent, glow -> soft alpha.
from collections import deque
import numpy as np
from PIL import Image

T = 60  # below this brightness a pixel counts as background


def cut(img, everywhere):
    a = np.asarray(img).astype(np.float32)
    h, w = a.shape[:2]
    m = a.max(axis=2)
    dark = m < T
    if everywhere:
        bg = dark
    else:  # only what is connected to the outside (dark insides of an icon are part of it)
        bg = np.zeros((h, w), bool)
        todo = deque((y, x) for y in range(h) for x in range(w) if (y in (0, h - 1) or x in (0, w - 1)) and dark[y, x])
        for y, x in todo:
            bg[y, x] = True
        while todo:
            y, x = todo.popleft()
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h and 0 <= nx < w and dark[ny, nx] and not bg[ny, nx]:
                    bg[ny, nx] = True
                    todo.append((ny, nx))
    base = np.array([34, 32, 30], np.float32)
    lit = np.clip(a - base, 0, None)
    alpha = np.clip(lit.max(axis=2) / 50, 0, 1)
    rgb = np.where(alpha[..., None] > 0, lit / np.maximum(alpha[..., None], 1e-3), 0)
    rgb = np.clip(rgb, 0, 255)
    alpha = np.where(bg, alpha, 1.0)
    rgb = np.where(bg[..., None], rgb, a)
    return Image.fromarray(np.dstack([rgb, alpha * 255]).astype(np.uint8), "RGBA")
