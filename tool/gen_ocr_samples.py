#!/usr/bin/env python3
"""Generate SYNTHETIC credential screenshots for OCR experiments.

The owner's real problem: a tiny crop (about 190x90 px) of a dark-mode
screenshot -- light grey text on a near-black background, two lines: an e-mail
address and below it a 12 character mixed-case + digits password -- that
Windows OCR / ML Kit cannot read. This script renders look-alikes of that
image with Pillow so the preprocessing pipeline (upscale, invert, pad, ...)
can be measured against a real OCR engine offline. Every credential here is
made up; never put real credentials in this file or in its output.

Each sample is a PNG (or JPEG) plus an entry in manifest.json:
    {"file", "email", "password", "bg", "fg", "font", "px", "scale",
     "polarity", "layout", "jpeg", "dpi_blur", "size"}
so a runner can OCR every file, apply a preprocessing variant, and score
whether the e-mail and the password come back exactly.

--extras appends two more families (the default output is unchanged):
  * "clip": crops with the top 1-3 px of line 1 cut off, like the owner's
    real crop (its first line touches the top edge). Shows why padding
    matters: without a border the e-mail line is lost.
  * "big": 2560x1440 / 3840x2160 / 5120x2880 dark-mode screenshots with a
    credentials block among decoy text (Windows OCR refuses images above
    OcrEngine.MaxImageDimension, about 2600 px). Shows that tiling at native
    resolution beats shrinking to fit.

Usage:
    pip install pillow
    python3 tool/gen_ocr_samples.py --out /tmp/ocr_samples            # ~320 images
    python3 tool/gen_ocr_samples.py --out /tmp/ocr_samples --level small
    python3 tool/gen_ocr_samples.py --out /tmp/ocr_samples --extras
    python3 tool/gen_ocr_samples.py --list-fonts

Levels: small (~110 images), default (~320), full (~800). Output is
deterministic for a given --seed.
"""
import argparse
import json
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------------------
# Synthetic credential pairs (email, password). Includes look-alike characters
# (l/I/1, 0/O/Q/D, 5/S, 2/Z, 8/B, u/v, rn/m) that OCR commonly confuses.
# ---------------------------------------------------------------------------
PAIRS = [
    ('abcde07@hotmail.com', 'xQmR42abCD5k'),
    ('kmnop12@hotmail.com', 'Zt9LqW3vB0yH'),
    ('lil1o0@hotmail.com', 'Il1O0lI1O0aB'),
    ('jdoe.test99@hotmail.com', 'pR7wXn2KfL8q'),
    ('mnbvc_31@outlook.com', 'eLm0Qr4tYu6W'),
    ('zxcvb56@hotmail.com', 'tH8sNa3DeR9u'),
    ('qwert-14@live.com', 'gBv5Cz2MxA7j'),
    ('user.name03@hotmail.com', 'lO0kI1jH8gF4'),
    ('fghjk88@hotmail.com', 'rnM5uVw2SsZz'),
    ('tyuio21@hotmail.es', 'Nb4Jd7QqPp1c'),
    ('sample_mail42@hotmail.co.uk', 'hG3fE9aXoO0l'),
    ('vbnm.zx65@hotmail.com', 'W2yU6iT8rE1a'),
]

# Dark backgrounds: near-black greys and violet tints (dark-mode UIs).
DARK_BG = [
    (18, 18, 19), (13, 13, 13), (24, 24, 27), (30, 27, 38),
    (20, 18, 32), (33, 33, 33), (10, 14, 20), (38, 38, 42),
]
# Light-on-dark foregrounds (light greys).
LIGHT_FG = [
    (175, 176, 179), (200, 200, 205), (150, 152, 158), (225, 225, 228),
    (190, 190, 190),
]
# Light mode: off-white backgrounds, dark grey text.
LIGHT_BG = [(255, 255, 255), (246, 246, 248), (236, 236, 240)]
DARK_FG = [(32, 33, 36), (60, 60, 64), (20, 20, 20)]

# (name, candidate paths). The first existing path per name wins.
FONT_CANDIDATES = [
    ('segoe', ['C:/Windows/Fonts/segoeui.ttf']),
    ('arial', ['C:/Windows/Fonts/arial.ttf', '/Library/Fonts/Arial.ttf',
               '/System/Library/Fonts/Supplemental/Arial.ttf']),
    ('inter', ['/usr/share/fonts/opentype/inter/Inter-Regular.otf',
               '/usr/share/fonts/truetype/inter/Inter-Regular.ttf']),
    ('roboto', ['/usr/share/fonts/truetype/roboto/unhinted/RobotoTTF/Roboto-Regular.ttf',
                '/usr/share/fonts/truetype/roboto/Roboto-Regular.ttf']),
    ('opensans', ['/usr/share/fonts/truetype/open-sans/OpenSans-Regular.ttf']),
    ('lato', ['/usr/share/fonts/truetype/lato/Lato-Regular.ttf']),
    ('dejavu', ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']),
    ('liberation', ['/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf']),
    ('freesans', ['/usr/share/fonts/truetype/freefont/FreeSans.ttf']),
]

LAYOUTS = ('real', 'tight', 'roomy')


def find_fonts(extra=()):
    found = {}
    for name, paths in FONT_CANDIDATES:
        for p in paths:
            if os.path.isfile(p):
                found[name] = p
                break
    for i, p in enumerate(extra):
        if os.path.isfile(p):
            found['extra%d' % i] = p
    return found


def load_font(path, px):
    if path:
        try:
            return ImageFont.truetype(path, px)
        except OSError:
            pass
    try:
        return ImageFont.load_default(px)  # Pillow >= 10.1
    except TypeError:
        return ImageFont.load_default()


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
def render(spec, font_path):
    """Render one spec (dict) and return a PIL RGB image."""
    scale = spec['scale']
    px = spec['px']
    layout = spec['layout']
    # dpi_blur: render larger and downsample, mimicking fractional OS scaling
    # (125% / 150% Windows displays) that leaves soft glyph edges.
    ss = 1.5 if spec['dpi_blur'] else 1.0
    font = load_font(font_path, max(6, int(round(px * scale * ss))))
    lines = [spec['email'], spec['password']]
    asc, desc = font.getmetrics()
    line_h = asc + desc
    size_px = px * scale * ss
    if layout == 'real':
        # Like the owner's crop: line 1 almost touching the top edge, a wide
        # gap before line 2, tight bottom/left margins.
        pitch = int(round(3.0 * size_px))
        pad_x, pad_top, pad_bot = (int(6 * scale * ss), 0, int(4 * scale * ss))
        height = pad_top + pitch + line_h + pad_bot
        width = max(int(round(190 * scale * ss)),
                    int(max(font.getlength(l) for l in lines)) + 2 * pad_x)
    elif layout == 'tight':
        pitch = int(round(1.5 * size_px))
        pad_x, pad_top, pad_bot = (int(8 * scale * ss),) * 3
        height = pad_top + pitch + line_h + pad_bot
        width = int(max(font.getlength(l) for l in lines)) + 2 * pad_x
    else:  # roomy: about 190x90 canvas with margins
        pitch = int(round(2.0 * size_px))
        pad_x = int(spec['margin'] * scale * ss)
        pad_top = int(spec['margin'] * scale * ss)
        width = max(int(round(190 * scale * ss)),
                    int(max(font.getlength(l) for l in lines)) + 2 * pad_x)
        height = max(int(round(90 * scale * ss)),
                     pad_top + pitch + line_h + pad_top)
    img = Image.new('RGB', (width, height), tuple(spec['bg']))
    draw = ImageDraw.Draw(img)
    y = pad_top
    for i, line in enumerate(lines):
        draw.text((pad_x, y + i * pitch), line, font=font, fill=tuple(spec['fg']))
    if ss != 1.0:
        img = img.resize((int(round(width / ss)), int(round(height / ss))),
                         Image.BICUBIC)
    clip = spec.get('clip', 0)
    if clip:
        img = img.crop((0, clip, img.width, img.height))
    return img


def save(img, spec, out_dir, name):
    q = spec['jpeg']
    if q:
        fn = name + '.jpg'
        img.save(os.path.join(out_dir, fn), 'JPEG', quality=q, subsampling=0)
    else:
        fn = name + '.png'
        img.save(os.path.join(out_dir, fn), 'PNG')
    return fn


# ---------------------------------------------------------------------------
# Spec generation
# ---------------------------------------------------------------------------
def make_spec(rnd, fonts, pair, px, scale=1, polarity='dark', jpeg=0,
              font=None, layout=None, dpi_blur=None):
    if polarity == 'dark':
        bg = rnd.choice(DARK_BG)
        fg = rnd.choice(LIGHT_FG)
    else:
        bg = rnd.choice(LIGHT_BG)
        fg = rnd.choice(DARK_FG)
    names = sorted(fonts) or ['default']
    return {
        'email': pair[0],
        'password': pair[1],
        'bg': list(bg),
        'fg': list(fg),
        'font': font or rnd.choice(names),
        'px': px,
        'scale': scale,
        'polarity': polarity,
        'layout': layout or rnd.choice(LAYOUTS),
        'margin': rnd.choice([6, 10, 14, 20]),
        'jpeg': jpeg,
        'dpi_blur': bool(rnd.random() < 0.3) if dpi_blur is None else dpi_blur,
    }


def build_specs(level, seed, fonts):
    rnd = random.Random(seed)
    specs = []
    sizes = [11, 12, 13, 14, 15]
    per_cell = {'small': 1, 'default': 3, 'full': 8}[level]
    pairs = PAIRS if level != 'small' else PAIRS[:6]

    # 1) Core grid: 1x light-on-dark, every pair x every font size.
    for pair in pairs:
        for px in sizes:
            for _ in range(per_cell):
                specs.append(make_spec(rnd, fonts, pair, px))

    def some_sizes(idx):
        # Two sizes per pair, rotated so every size is covered across pairs.
        if level == 'full':
            return sizes
        return [sizes[idx % len(sizes)], sizes[(idx + 2) % len(sizes)]]

    # 2) Same text at 2x / 3x (high-DPI captures).
    for idx, pair in enumerate(pairs):
        for px in some_sizes(idx):
            for scale in (2, 3):
                specs.append(make_spec(rnd, fonts, pair, px, scale=scale))
    # 3) JPEG compressed (screenshots re-encoded by chat apps / clipboards).
    for idx, pair in enumerate(pairs):
        for px in some_sizes(idx + 1):
            for q in (85, 60):
                specs.append(make_spec(rnd, fonts, pair, px, jpeg=q))
    # 4) Dark text on light background (the case OCR engines like best).
    for idx, pair in enumerate(pairs):
        for px in some_sizes(idx + 3):
            specs.append(make_spec(rnd, fonts, pair, px, polarity='light'))
    # 5) Every available font once at 13 px (font sensitivity).
    for fname in sorted(fonts):
        for pair in pairs[:3]:
            specs.append(make_spec(rnd, fonts, pair, 13, font=fname))
    return specs


# ---------------------------------------------------------------------------
# Extras: edge-clipped crops and large screenshots (--extras)
# ---------------------------------------------------------------------------
DECOY_LINES = [
    'Settings', 'Account overview', 'Security', 'Sign-in methods',
    'Recovery options', 'Last signed in from Windows, Chrome',
    'Manage how you sign in to your account',
    'Two-step verification is turned on',
    'Notifications  Billing  Privacy  Devices',
    'Copy the details below and keep them somewhere safe',
]
BIG_SIZES = [(2560, 1440), (3840, 2160), (5120, 2880)]
BIG_FONT_PX = [14, 18, 21, 28]


def build_clip_specs(seed, fonts):
    """Dark 'real'-layout crops with 1-3 px cut off the top edge."""
    rnd = random.Random(seed + 1000)
    specs = []
    for pair in PAIRS[:6]:
        for px in (11, 13, 15):
            for clip in (1, 2, 3):
                spec = make_spec(rnd, fonts, pair, px, layout='real')
                spec['clip'] = clip
                spec['kind'] = 'clip'
                specs.append(spec)
    return specs


def render_big(spec, font_path):
    """A dark-mode settings-page screenshot with the credentials block in it."""
    width, height = spec['screen']
    px = spec['px']
    font = load_font(font_path, px)
    big = load_font(font_path, int(px * 1.6))
    bg = tuple(spec['bg'])
    img = Image.new('RGB', (width, height), bg)
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, int(width * 0.16), height],
                   fill=tuple(c + 8 for c in bg))
    for i, text in enumerate(DECOY_LINES[:8]):
        draw.text((int(width * 0.02), int(height * 0.1) + i * int(px * 3.2)),
                  text, font=font, fill=(150, 152, 158))
    draw.text((int(width * 0.22), int(height * 0.06)), DECOY_LINES[0],
              font=big, fill=(225, 225, 228))
    y = int(height * 0.15)
    for text in DECOY_LINES[1:5]:
        draw.text((int(width * 0.22), y), text, font=font,
                  fill=(165, 166, 170))
        y += int(px * 2.2)
    y = int(height * 0.55)
    fg = tuple(spec['fg'])
    draw.text((int(width * 0.22), y), spec['email'], font=font, fill=fg)
    draw.text((int(width * 0.22), y + int(px * 3.0)), spec['password'],
              font=font, fill=fg)
    for text in DECOY_LINES[5:]:
        draw.text((int(width * 0.22), y + int(px * 6)), text, font=font,
                  fill=(120, 122, 128))
        y += int(px * 2.2)
    return img


def build_big_specs(seed, fonts):
    rnd = random.Random(seed + 2000)
    specs = []
    for screen in BIG_SIZES:
        for px in BIG_FONT_PX:
            for pair in PAIRS[:2]:
                specs.append({
                    'email': pair[0],
                    'password': pair[1],
                    'bg': list(rnd.choice(DARK_BG[:4])),
                    'fg': [175, 176, 179],
                    'font': 'inter' if 'inter' in fonts else
                    (sorted(fonts) or ['default'])[0],
                    'px': px,
                    'scale': 1,
                    'polarity': 'dark',
                    'layout': 'screen',
                    'screen': list(screen),
                    'jpeg': 0,
                    'dpi_blur': False,
                    'kind': 'big',
                })
    return specs


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--out', help='output directory (created)')
    ap.add_argument('--level', choices=['small', 'default', 'full'],
                    default='default')
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--font', action='append', default=[],
                    help='extra TTF/OTF path (repeatable)')
    ap.add_argument('--extras', action='store_true',
                    help='also write edge-clipped crops and large screenshots')
    ap.add_argument('--list-fonts', action='store_true')
    args = ap.parse_args(argv)

    fonts = find_fonts(args.font)
    if args.list_fonts:
        for k, v in sorted(fonts.items()):
            print('%-10s %s' % (k, v))
        if not fonts:
            print('no known fonts found; Pillow default font will be used')
        return 0
    if not args.out:
        ap.error('--out is required')
    os.makedirs(args.out, exist_ok=True)
    specs = build_specs(args.level, args.seed, fonts)
    manifest = []
    for i, spec in enumerate(specs):
        img = render(spec, fonts.get(spec['font']))
        name = 's%04d' % i
        fn = save(img, spec, args.out, name)
        entry = dict(spec)
        entry['file'] = fn
        entry['size'] = [img.width, img.height]
        manifest.append(entry)
    if args.extras:
        extra_specs = (build_clip_specs(args.seed, fonts) +
                       build_big_specs(args.seed, fonts))
        for i, spec in enumerate(extra_specs):
            font_path = fonts.get(spec['font'])
            if spec['kind'] == 'big':
                img = render_big(spec, font_path)
            else:
                img = render(spec, font_path)
            name = 'x%04d' % i
            fn = save(img, spec, args.out, name)
            entry = dict(spec)
            entry['file'] = fn
            entry['size'] = [img.width, img.height]
            manifest.append(entry)
    with open(os.path.join(args.out, 'manifest.json'), 'w') as f:
        json.dump(manifest, f, indent=1)
    print('wrote %d samples to %s (fonts: %s)' %
          (len(manifest), args.out, ', '.join(sorted(fonts)) or 'default'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
