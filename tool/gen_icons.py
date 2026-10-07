#!/usr/bin/env python3
"""Generate the whole app icon set procedurally (no binary design source).

Design: a bold gradient shield with a keyhole cut-out on a deep violet-black
tile, in the owner's portfolio palette (#07060f / #120e1f background, brand
gradient #8251d4 -> #c9a8ff at 135deg). No text and no letters, so the icon does
not depend on the (still undecided) app name.

Re-run from the repository root (Python 3.9+):

    pip install pillow numpy
    python3 tool/gen_icons.py              # rewrites every generated file
    python3 tool/gen_icons.py --sheet /tmp/icons_sheet.png   # + contact sheet

The output is deterministic (fixed dither seed, no timestamps), so re-running
without changing the script produces byte-identical files and a clean git diff.
Everything is drawn with 4x supersampling and rendered per output size (not
resized from one master), so the 16/24/32/48 px versions stay crisp.

Files written (all paths relative to the repository root):

  Android (android/app/src/main/res/)
    mipmap-anydpi-v26/ic_launcher.xml       adaptive icon (bg + fg + monochrome)
    drawable-{m,h,xh,xxh,xxxh}dpi/ic_launcher_background.png   108dp dark tile
    drawable-*dpi/ic_launcher_foreground.png   glyph inside the 66/108 safe zone
    drawable-*dpi/ic_launcher_monochrome.png   single-colour glyph (Android 13
                                               themed icons)
    mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png   legacy rounded-square icon
  iOS (ios/Runner/Assets.xcassets/)
    AppIcon.appiconset/*.png   every size listed in Contents.json (the file
                               itself is read, never rewritten); opaque RGB,
                               full bleed, iOS applies the corner mask
    LaunchImage.imageset/LaunchImage{,@2x,@3x}.png   centred glyph on alpha
  Windows
    windows/runner/resources/app_icon.ico   16,24,32,48,64,128,256
  In-app brand art (assets/brand/)
    icon.png        1024 rounded tile with transparent corners
    mark.png        512 gradient glyph only, transparent background
    mark_mono.png   512 white silhouette (tint it with a ColorFilter)

assets/brand/ is not declared in pubspec.yaml by this script: list the files
that the UI actually loads there.

Not generated here (edit by hand): the dark launch backgrounds
(res/values/colors.xml, styles.xml, values-night/styles.xml, drawable*/
launch_background.xml) and ios/Runner/Base.lproj/LaunchScreen.storyboard. They
use the same #07060f as BG_DARK below.
"""
from __future__ import annotations

import argparse
import io
import json
import math
import struct
import sys
import xml.dom.minidom
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
APPICON = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
LAUNCHIMG = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
ICO_PATH = ROOT / "windows/runner/resources/app_icon.ico"
BRAND = ROOT / "assets/brand"

SS = 4  # supersampling factor for every shape


def _rgb(hex_color: str) -> np.ndarray:
    h = hex_color.lstrip("#")
    return np.array([int(h[i : i + 2], 16) for i in (0, 2, 4)], np.float32)


# Palette (from the portfolio's styles.css :root).
BG_DARK = _rgb("#07060f")  # --bg
BG_MID = _rgb("#120e1f")  # --surface
ACCENT = _rgb("#a17cf5")  # --accent
ACCENT_STRONG = _rgb("#8251d4")  # --accent-strong, gradient start
ACCENT_SOFT = _rgb("#c9a8ff")  # --accent-2, gradient end
LINE = _rgb("#3a2d50")  # --line-2, hairline around the tile

# --------------------------------------------------------------------------
# Glyph geometry, in a 100 x 100 design box (y down). Shield + keyhole cut-out.
# Sharp polygons are drawn and then rounded by a blur + threshold pass, which
# fillets every corner (the shield's apex/shoulders/tip and the keyhole's neck
# and slot) with the same radius.
# --------------------------------------------------------------------------
ROUND_SIGMA = 2.3  # corner rounding strength, design units


def _cubic(p0, p1, p2, p3, n=40):
    pts = []
    for i in range(1, n + 1):
        t = i / n
        u = 1 - t
        pts.append(
            (
                u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1],
            )
        )
    return pts


def _shield_polygon():
    apex = (50.0, 3.5)
    shoulder = (89.0, 16.5)
    side_end = (89.0, 49.0)
    tip = (50.0, 96.5)
    right = [apex, shoulder, side_end]
    right += _cubic(side_end, (89.0, 69.0), (70.0, 85.0), tip)
    left = [(100.0 - x, y) for x, y in reversed(right[1:-1])]
    return right + left


SHIELD = _shield_polygon()
KEY_CIRCLE = (50.0, 42.0, 12.0)  # cx, cy, r
KEY_SLOT = [(44.3, 47.0), (55.7, 47.0), (62.0, 72.0), (38.0, 72.0)]
KEY_ORIGIN = (50.0, 58.0)  # keyhole scales about this point (small sizes)


def _smooth(im: Image.Image, sigma_px: float) -> np.ndarray:
    """Blur + soft threshold: rounds corners, keeps edges anti-aliased."""
    sigma_px = float(sigma_px)
    blurred = im.filter(ImageFilter.GaussianBlur(sigma_px))
    arr = np.asarray(blurred, np.float32)
    slope = 255.0 / (sigma_px * math.sqrt(2 * math.pi))  # levels per hi-res px
    return np.clip((arr - 127.5) / (slope * 2.0) + 0.5, 0.0, 1.0)


def _box_down(arr: np.ndarray, n: int = SS) -> np.ndarray:
    h, w = arr.shape
    return arr.reshape(h // n, n, w // n, n).mean(axis=(1, 3)).astype(np.float32)


@lru_cache(maxsize=64)
def glyph_coverage(W: int, cx: float, cy: float, ppu: float, key_scale: float = 1.0, fill_hole: bool = False):
    """Coverage (0..1, float32, W x W) of the shield with the keyhole removed
    (or, with fill_hole, of the plain rounded shield silhouette).

    (cx, cy) is where design point (50, 50) lands on the canvas, ppu is pixels
    per design unit.
    """
    s = ppu * SS
    Wh = W * SS

    def T(p):
        return (cx * SS + (p[0] - 50.0) * s, cy * SS + (p[1] - 50.0) * s)

    def K(p):  # keyhole point with the small-size scale applied
        return (
            KEY_ORIGIN[0] + (p[0] - KEY_ORIGIN[0]) * key_scale,
            KEY_ORIGIN[1] + (p[1] - KEY_ORIGIN[1]) * key_scale,
        )

    im = Image.new("L", (Wh, Wh), 0)
    d = ImageDraw.Draw(im)
    d.polygon([T(p) for p in SHIELD], fill=255)
    if not fill_hole:
        kx, ky = K(KEY_CIRCLE[:2])
        kr = KEY_CIRCLE[2] * key_scale
        (x0, y0), (x1, y1) = T((kx - kr, ky - kr)), T((kx + kr, ky + kr))
        d.ellipse([x0, y0, x1, y1], fill=0)
        d.polygon([T(K(p)) for p in KEY_SLOT], fill=0)
    return _box_down(_smooth(im, ROUND_SIGMA * s))


def _measure():
    """Bounding box and farthest-point radius of the rounded glyph (design units)."""
    W, ppu = 400, 3.2
    cov = glyph_coverage(W, 200.0, 200.0, ppu)
    ys, xs = np.nonzero(cov > 0.5)
    to_u = lambda v: (v - 200.0) / ppu + 50.0
    x0, x1 = float(to_u(xs.min())), float(to_u(xs.max() + 1))
    y0, y1 = float(to_u(ys.min())), float(to_u(ys.max() + 1))
    bcx, bcy = (x0 + x1) / 2, (y0 + y1) / 2
    px, py = to_u(xs + 0.5), to_u(ys + 0.5)
    radius = float(np.sqrt((px - bcx) ** 2 + (py - bcy) ** 2).max())
    return (x0, y0, x1, y1), (bcx, bcy), radius


BBOX_U, CENTER_U, RADIUS_U = _measure()
HEIGHT_U = BBOX_U[3] - BBOX_U[1]
WIDTH_U = BBOX_U[2] - BBOX_U[0]


class Layout:
    """Where the glyph sits on a W x W canvas."""

    def __init__(self, W: int, ppu: float, center=(0.5, 0.5), key_scale=1.0):
        self.W, self.ppu, self.key_scale = W, ppu, key_scale
        gx, gy = center[0] * W, center[1] * W  # canvas point for the glyph bbox centre
        self.cx = gx - (CENTER_U[0] - 50.0) * ppu
        self.cy = gy - (CENTER_U[1] - 50.0) * ppu
        self.bbox = (
            self.cx + (BBOX_U[0] - 50.0) * ppu,
            self.cy + (BBOX_U[1] - 50.0) * ppu,
            self.cx + (BBOX_U[2] - 50.0) * ppu,
            self.cy + (BBOX_U[3] - 50.0) * ppu,
        )

    @staticmethod
    def by_height(W, frac, center=(0.5, 0.5), key_scale=1.0):
        return Layout(W, frac * W / HEIGHT_U, center, key_scale)

    @staticmethod
    def adaptive(W, safe_radius_dp=33.0):
        """Android adaptive foreground: farthest glyph point stays inside the
        66dp safe-zone circle of the 108dp canvas."""
        return Layout(W, safe_radius_dp / 108.0 * W / RADIUS_U)

    def coverage(self, fill_hole=False):
        return glyph_coverage(
            self.W, round(self.cx, 3), round(self.cy, 3), round(self.ppu, 5), self.key_scale, fill_hole
        )


# --------------------------------------------------------------------------
# Layers (float arrays, 0..255 colour, 0..1 alpha)
# --------------------------------------------------------------------------
def _grid(W):
    ys, xs = np.mgrid[0:W, 0:W].astype(np.float32)
    return xs + 0.5, ys + 0.5


def background(W):
    """Deep violet-black with a subtle radial violet glow high in the tile."""
    xs, ys = _grid(W)
    d = np.sqrt((xs - 0.30 * W) ** 2 + (ys - 0.16 * W) ** 2) / (0.95 * W)
    g = np.clip(1.0 - d, 0.0, 1.0) ** 1.6
    inner = BG_MID + (ACCENT_STRONG - BG_MID) * 0.34
    base = BG_DARK + (BG_MID - BG_DARK) * np.clip(1.0 - d * 0.8, 0, 1)[..., None] ** 1.2
    return base + (inner - base) * g[..., None]


def glyph_fill(lay: Layout, facet=True):
    """Brand gradient (135deg, #8251d4 -> #c9a8ff) across the glyph bounding box."""
    W = lay.W
    xs, ys = _grid(W)
    x0, y0, x1, y1 = lay.bbox
    t = np.clip(((xs - x0) + (ys - y0)) / ((x1 - x0) + (y1 - y0)), 0.0, 1.0)
    rgb = ACCENT_STRONG + (ACCENT_SOFT - ACCENT_STRONG) * t[..., None]
    if facet:  # right half of the shield catches a little more light
        mid = lay.cx
        f = np.clip((xs - mid) / 1.2 + 0.5, 0.0, 1.0) * 0.10
        rgb = rgb + (255.0 - rgb) * f[..., None]
    return rgb


def glow(lay: Layout, strength=0.26, radius=0.045):
    """Soft violet halo around the shield; the keyhole itself stays dark."""
    solid = lay.coverage(fill_hole=True)
    im = Image.fromarray((solid * 255.0 + 0.5).astype(np.uint8), "L")
    blurred = np.asarray(im.filter(ImageFilter.GaussianBlur(radius * lay.W)), np.float32) / 255.0
    halo = np.clip(blurred * strength * 2.2, 0.0, strength)
    return halo * (1.0 - (solid - lay.coverage()))


def over(dst_rgb, dst_a, src_rgb, src_a):
    """Straight-alpha 'over' compositing."""
    out_a = src_a + dst_a * (1.0 - src_a)
    safe = np.maximum(out_a, 1e-6)[..., None]
    out_rgb = (src_rgb * src_a[..., None] + dst_rgb * (dst_a * (1.0 - src_a))[..., None]) / safe
    return out_rgb, out_a


def rounded_mask(W, radius_frac, inset=0.0):
    im = Image.new("L", (W * SS, W * SS), 0)
    r = radius_frac * W * SS
    i = inset * SS
    ImageDraw.Draw(im).rounded_rectangle([i, i, W * SS - 1 - i, W * SS - 1 - i], radius=max(r - i, 0), fill=255)
    return _box_down(np.asarray(im, np.float32) / 255.0)


def to_image(rgb, alpha=None, seed=7):
    """Quantise with dither (kills banding in the dark gradients)."""
    rng = np.random.default_rng(seed)
    q = np.floor(np.clip(rgb, 0, 255) + rng.random(rgb.shape, dtype=np.float32)).clip(0, 255).astype(np.uint8)
    if alpha is None:
        return Image.fromarray(q, "RGB")
    a = np.floor(np.clip(alpha, 0, 1) * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(np.dstack([q, a]), "RGBA")


# --------------------------------------------------------------------------
# Compositions
# --------------------------------------------------------------------------
def small_layout(W):
    """Glyph size / keyhole boldness tuned per pixel size (optical sizing)."""
    if W >= 128:
        return Layout.by_height(W, 0.64, (0.5, 0.5))
    if W >= 64:
        return Layout.by_height(W, 0.68, (0.5, 0.5), key_scale=1.04)
    if W >= 40:
        return Layout.by_height(W, 0.72, (0.5, 0.5), key_scale=1.08)
    return Layout.by_height(W, 0.78, (0.5, 0.5), key_scale=1.12)


def tile(W, rounded=True, layout=None, border=True, with_glow=None, opaque=False):
    """The full icon: background + glow + glyph (+ hairline), optionally rounded."""
    lay = layout or small_layout(W)
    if with_glow is None:
        with_glow = W >= 40  # a halo only blurs the 16-32 px versions
    rgb = background(W)
    a = np.ones((W, W), np.float32)
    cov = lay.coverage()
    if with_glow:
        ga = glow(lay)
        rgb, a = over(rgb, a, np.broadcast_to(ACCENT, rgb.shape), ga)
    rgb, a = over(rgb, a, glyph_fill(lay), cov)
    if rounded:
        r = 0.2237
        outer = rounded_mask(W, r)
        if border and W >= 24:
            bw = max(1.0, W * 0.008)
            ring = outer - rounded_mask(W, r, inset=bw)
            rgb, _ = over(rgb, a, np.broadcast_to(LINE, rgb.shape), np.clip(ring, 0, 1) * 0.7)
        a = outer
    return to_image(rgb) if opaque and not rounded else to_image(rgb, a)


def adaptive_background(W):
    return to_image(background(W))


def adaptive_foreground(W):
    lay = Layout.adaptive(W)
    cov = lay.coverage()
    rgb = np.broadcast_to(ACCENT, (W, W, 3)).astype(np.float32)
    a = glow(lay, strength=0.24, radius=0.035)
    rgb, a = over(rgb, a, glyph_fill(lay), cov)
    return to_image(rgb, a)


def adaptive_monochrome(W):
    lay = Layout.adaptive(W)
    cov = lay.coverage()
    return to_image(np.full((W, W, 3), 255.0, np.float32), cov)


def mark(W, mono=False):
    lay = Layout.by_height(W, 0.90)
    cov = lay.coverage()
    rgb = np.full((W, W, 3), 255.0, np.float32) if mono else glyph_fill(lay)
    return to_image(rgb, cov)


def launch_image(scale):
    """168 x 185 pt canvas (matches the storyboard), glyph centred, glow, alpha."""
    Wpt, Hpt = 168, 185
    Wd, Hd = Wpt * scale, Hpt * scale
    side = max(Wd, Hd)
    lay = Layout.by_height(side, 96.0 * scale / side)
    # render on a square canvas, then crop to the real canvas around the centre
    cov = lay.coverage()
    rgb = np.broadcast_to(ACCENT, (side, side, 3)).astype(np.float32)
    a = glow(lay, strength=0.24, radius=0.035)
    rgb, a = over(rgb, a, glyph_fill(lay), cov)
    x0, y0 = (side - Wd) // 2, (side - Hd) // 2
    return to_image(rgb[y0 : y0 + Hd, x0 : x0 + Wd], a[y0 : y0 + Hd, x0 : x0 + Wd])


# --------------------------------------------------------------------------
# Writers
# --------------------------------------------------------------------------
WRITTEN: list[Path] = []


def save_png(img: Image.Image, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG", optimize=True)
    WRITTEN.append(path)


def write_text(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    WRITTEN.append(path)


def png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def dib_bytes(img: Image.Image) -> bytes:
    """32-bit BMP payload for an ICO entry (BGRA, bottom-up, empty AND mask)."""
    w, h = img.size
    rgba = np.asarray(img.convert("RGBA"), np.uint8)
    bgra = rgba[..., [2, 1, 0, 3]][::-1]
    header = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0, w * h * 4, 0, 0, 0, 0)
    and_mask = bytes(((w + 31) // 32) * 4 * h)
    return header + bgra.tobytes() + and_mask


def write_ico(path: Path, sizes):
    """PNG for 256 (what rc.exe/Windows expect), classic 32-bit DIB below it."""
    entries = []
    for s in sizes:
        img = tile(s)
        entries.append((s, png_bytes(img) if s >= 256 else dib_bytes(img)))
    head = struct.pack("<HHH", 0, 1, len(entries))
    offset = 6 + 16 * len(entries)
    dirs, blobs = b"", b""
    for s, data in entries:
        dirs += struct.pack("<BBBBHHII", 0 if s >= 256 else s, 0 if s >= 256 else s, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
        blobs += data
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(head + dirs + blobs)
    WRITTEN.append(path)


DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/gen_icons.py; do not edit by hand. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
"""


def gen_android():
    write_text(RES / "mipmap-anydpi-v26/ic_launcher.xml", ADAPTIVE_XML)
    for name, scale in DENSITIES.items():
        layer = round(108 * scale)
        legacy = round(48 * scale)
        save_png(adaptive_background(layer), RES / f"drawable-{name}/ic_launcher_background.png")
        save_png(adaptive_foreground(layer), RES / f"drawable-{name}/ic_launcher_foreground.png")
        save_png(adaptive_monochrome(layer), RES / f"drawable-{name}/ic_launcher_monochrome.png")
        save_png(tile(legacy), RES / f"mipmap-{name}/ic_launcher.png")


def gen_ios():
    contents = json.loads((APPICON / "Contents.json").read_text())
    done = set()
    for item in contents["images"]:
        base = float(item["size"].split("x")[0])
        px = round(base * int(item["scale"].rstrip("x")))
        name = item["filename"]
        if name in done:
            continue
        done.add(name)
        # Full bleed, no alpha: iOS rounds the corners itself.
        lay = Layout.by_height(px, 0.62 if px >= 80 else 0.70, key_scale=1.0 if px >= 80 else 1.06)
        save_png(tile(px, rounded=False, layout=lay, border=False, opaque=True), APPICON / name)
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        save_png(launch_image(scale), LAUNCHIMG / f"LaunchImage{suffix}.png")


def gen_windows():
    write_ico(ICO_PATH, [16, 24, 32, 48, 64, 128, 256])


def gen_brand():
    save_png(tile(1024), BRAND / "icon.png")
    save_png(mark(512), BRAND / "mark.png")
    save_png(mark(512, mono=True), BRAND / "mark_mono.png")


# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------
def validate():
    for p in WRITTEN:
        if p.suffix == ".xml":
            xml.dom.minidom.parse(str(p))
    ref = {p.stem for p in (RES / "drawable-xxxhdpi").glob("*.png")}
    for need in ("ic_launcher_background", "ic_launcher_foreground", "ic_launcher_monochrome"):
        assert need in ref, f"missing drawable {need}"
        for d in DENSITIES:
            assert (RES / f"drawable-{d}/{need}.png").exists(), f"{need} missing for {d}"
        assert f'@drawable/{need}"' in ADAPTIVE_XML
    for d in DENSITIES:
        assert (RES / f"mipmap-{d}/ic_launcher.png").exists()
    contents = json.loads((APPICON / "Contents.json").read_text())
    for item in contents["images"]:
        img = Image.open(APPICON / item["filename"])
        px = round(float(item["size"].split("x")[0]) * int(item["scale"].rstrip("x")))
        assert img.size == (px, px), (item["filename"], img.size, px)
        assert img.mode == "RGB", f"{item['filename']} must have no alpha channel"
    ico = Image.open(ICO_PATH)
    assert sorted(ico.info["sizes"]) == [(s, s) for s in (16, 24, 32, 48, 64, 128, 256)], ico.info["sizes"]


# --------------------------------------------------------------------------
# Contact sheet (preview only; not part of the build)
# --------------------------------------------------------------------------
def contact_sheet(out: Path):
    DARK, LIGHT = (14, 13, 20), (236, 233, 244)
    font = None
    sheet_w = 1560
    rows = []

    def strip(bg, items, pad=22, label=None):
        h = max(i.height for i in items) + 2 * pad
        im = Image.new("RGB", (sheet_w, h), bg)
        x = pad
        for it in items:
            im.paste(it, (x, (h - it.height) // 2), it if it.mode == "RGBA" else None)
            x += it.width + pad
        return im

    def fit(img, s):
        return img.resize((s, s), Image.LANCZOS) if img.size != (s, s) else img

    icon = Image.open(BRAND / "icon.png").convert("RGBA")
    sizes = (256, 128, 96, 64, 48, 32, 24, 16)
    # Real per-size renders (what the .ico contains), not downscales of the 1024.
    per_size = [tile(s) for s in sizes]
    rows.append(strip(DARK, per_size))
    rows.append(strip(LIGHT, per_size))
    rows.append(strip(DARK, [fit(icon, 256), fit(icon, 128), fit(icon, 64)]))

    # Android adaptive with circle and squircle masks (72dp visible).
    bg = Image.open(RES / "drawable-xxxhdpi/ic_launcher_background.png").convert("RGBA")
    fg = Image.open(RES / "drawable-xxxhdpi/ic_launcher_foreground.png").convert("RGBA")
    mono = Image.open(RES / "drawable-xxxhdpi/ic_launcher_monochrome.png").convert("RGBA")
    comp = Image.alpha_composite(bg, fg)
    vis = (432 - 288) // 2
    crop = comp.crop((vis, vis, vis + 288, vis + 288))
    circle = Image.new("L", (288, 288), 0)
    ImageDraw.Draw(circle).ellipse([0, 0, 287, 287], fill=255)
    squircle = Image.new("L", (288, 288), 0)
    ImageDraw.Draw(squircle).rounded_rectangle([0, 0, 287, 287], radius=90, fill=255)
    adaptive = []
    for m in (circle, squircle):
        c = crop.copy()
        c.putalpha(m)
        adaptive += [c, c.resize((144, 144), Image.LANCZOS), c.resize((72, 72), Image.LANCZOS), c.resize((48, 48), Image.LANCZOS)]
    rows.append(strip(DARK, adaptive))
    rows.append(strip(LIGHT, adaptive))

    # Themed (monochrome) icons: tinted glyph on a tonal circle, light + dark.
    def themed(bgc, fgc):
        mc = mono.crop((vis, vis, vis + 288, vis + 288))
        solid = Image.new("RGBA", mc.size, fgc + (255,))
        solid.putalpha(mc.getchannel("A"))
        base = Image.new("RGBA", mc.size, bgc + (255,))
        base = Image.alpha_composite(base, solid)
        base.putalpha(circle)
        return [base, base.resize((96, 96), Image.LANCZOS), base.resize((48, 48), Image.LANCZOS)]

    rows.append(strip((60, 56, 72), themed((226, 214, 255), (52, 28, 100)) + themed((74, 62, 104), (232, 220, 255))))

    # iOS: mask preview with iOS-ish radius, several real sizes.
    ios = []
    for item in json.loads((APPICON / "Contents.json").read_text())["images"]:
        if item["idiom"] == "iphone" and item["scale"] in ("2x", "3x") and item["size"] in ("60x60", "40x40", "29x29"):
            im = Image.open(APPICON / item["filename"]).convert("RGBA")
            m = Image.new("L", im.size, 0)
            ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=im.width * 0.2237, fill=255)
            im.putalpha(m)
            ios.append(im)
    rows.append(strip(DARK, ios))

    # Launch image + in-app marks on checker/dark/light.
    launch = Image.open(LAUNCHIMG / "LaunchImage@2x.png").convert("RGBA")
    base = Image.new("RGBA", launch.size, tuple(int(v) for v in BG_DARK) + (255,))
    launch = Image.alpha_composite(base, launch)
    mk = Image.open(BRAND / "mark.png").convert("RGBA").resize((200, 200), Image.LANCZOS)
    mm = Image.open(BRAND / "mark_mono.png").convert("RGBA").resize((200, 200), Image.LANCZOS)
    tint = Image.new("RGBA", mm.size, (11, 8, 20, 255))
    tint.putalpha(mm.getchannel("A"))
    tile_bg = Image.new("RGBA", (200, 200), (0, 0, 0, 0))
    ImageDraw.Draw(tile_bg).rounded_rectangle([40, 40, 160, 160], radius=36, fill=(130, 81, 212, 255))
    tiny = Image.alpha_composite(tile_bg, tint.resize((120, 120), Image.LANCZOS).crop((0, 0, 120, 120)).transform((200, 200), Image.AFFINE, (1, 0, -40, 0, 1, -40)))
    rows.append(strip(DARK, [launch.resize((168, 185), Image.LANCZOS), mk, mm, tiny]))

    total = sum(r.height for r in rows)
    sheet = Image.new("RGB", (sheet_w, total), DARK)
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"contact sheet: {out}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sheet", type=Path, help="also write a preview contact sheet PNG here")
    args = ap.parse_args(argv)
    gen_android()
    gen_ios()
    gen_windows()
    gen_brand()
    validate()
    for p in WRITTEN:
        print(p.relative_to(ROOT))
    print(f"{len(WRITTEN)} files written and validated")
    if args.sheet:
        contact_sheet(args.sheet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
