#!/usr/bin/env python3
"""Tests for the native Windows runner logic that can run on Linux.

windows/runner/platform_channel.cpp is only compiled by MSVC in CI, so the
logic that does not need Windows (clipboard DIB -> .bmp conversion, PNG
trimming, CF_HDROP parsing, OCR image preparation and scoring) lives between
the PURE-BEGIN / PURE-END markers and uses only the C++ standard library. This
script cuts that text out of the real source file, compiles it with g++ (with
-Werror and ASan/UBSan) into a small harness (harness.cpp) and checks it
against independent Python / Pillow / NumPy references. Optionally it also
syntax-checks the whole file with mingw-w64 (stubbing the WinRT part).

Run:  python3 tool/native_tests/run_tests.py            (all tests)
      python3 tool/native_tests/run_tests.py -k Dib     (unittest filters)
Needs: g++ (C++20), Pillow, NumPy. mingw-w64 g++ and the Flutter engine
sources (/opt/flutter/engine) are optional (the syntax check is skipped).

Test data is synthetic: never put real credentials in here.
"""
import io
import os
import random
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, '..', '..', 'windows', 'runner',
                      'platform_channel.cpp')
BUILD = tempfile.mkdtemp(prefix='vaultsnap-native-tests-')
HARNESS = os.path.join(BUILD, 'harness')


def region(text, begin, end):
    """Text strictly between the marker lines containing `begin` and `end`."""
    lines = text.split('\n')
    start = next(i for i, l in enumerate(lines) if l.startswith('// ' + begin))
    stop = next(i for i, l in enumerate(lines) if l.startswith('// ' + end))
    # skip the '// ====' rule lines around the markers
    return '\n'.join(lines[start + 1:stop])


def build_harness():
    with open(SOURCE, encoding='utf-8') as f:
        pure = region(f.read(), 'PURE-BEGIN', 'PURE-END')
    with open(os.path.join(BUILD, 'pure_region.inc'), 'w') as f:
        f.write(pure)
    cmd = ['g++', '-std=c++20', '-O1', '-g', '-Wall', '-Wextra', '-Wshadow',
           '-Wconversion', '-Wsign-conversion', '-Werror',
           '-fsanitize=address,undefined', '-fno-sanitize-recover=all',
           '-I', BUILD, os.path.join(HERE, 'harness.cpp'), '-o', HARNESS]
    subprocess.run(cmd, check=True)


def run(args, stdin=None):
    p = subprocess.run([HARNESS] + [str(a) for a in args], input=stdin,
                       capture_output=True)
    if p.returncode not in (0, 2):
        raise AssertionError('harness crashed (%d): %s' %
                             (p.returncode, p.stderr.decode(errors='replace')))
    return p


def tmp(name, data=b''):
    path = os.path.join(BUILD, name)
    with open(path, 'wb') as f:
        f.write(data)
    return path


def read(path):
    with open(path, 'rb') as f:
        return f.read()


# ---------------------------------------------------------------------------
# DIB construction and the Python reference conversion
# ---------------------------------------------------------------------------

def pack_rows(width, height, bpp, rows, top_down):
    """rows: `height` lists (top to bottom) of per-pixel values.
    24: (r,g,b)  32: (r,g,b,a)  16: int  8/4/1: palette index."""
    stride = ((width * bpp + 31) // 32) * 4
    out = bytearray()
    for r in (rows if top_down else rows[::-1]):
        row = bytearray()
        if bpp == 24:
            for (R, G, B) in r:
                row += bytes((B, G, R))
        elif bpp == 32:
            for (R, G, B, A) in r:
                row += bytes((B, G, R, A))
        elif bpp == 16:
            for v in r:
                row += struct.pack('<H', v)
        elif bpp == 8:
            row += bytes(r)
        elif bpp == 4:
            for i in range(0, len(r), 2):
                hi = r[i]
                lo = r[i + 1] if i + 1 < len(r) else 0
                row.append((hi << 4) | lo)
        elif bpp == 1:
            for i in range(0, len(r), 8):
                byte = 0
                for k in range(8):
                    bit = r[i + k] if i + k < len(r) else 0
                    byte |= bit << (7 - k)
                row.append(byte)
        else:
            raise ValueError(bpp)
        row += b'\0' * (stride - len(row))
        out += row
    return bytes(out)


def info_header(size, width, height, bpp, comp=0, size_image=0, clr_used=0):
    return struct.pack('<IiiHHIIiiII', size, width, height, 1, bpp, comp,
                       size_image, 2835, 2835, clr_used, 0)


def make_dib(width, height, bpp, rows, *, top_down=False, comp=0,
             header='v1', masks=None, palette=None, clr_used=0,
             size_image=0, pad=b''):
    """A packed DIB. header: 'core' | 'v1' | 'v2' | 'v3' | 'v4' | 'v5'."""
    pixels = pack_rows(width, height, bpp, rows, top_down)
    sizes = {'v1': 40, 'v2': 52, 'v3': 56, 'v4': 108, 'v5': 124}
    if header == 'core':
        head = struct.pack('<IHHHH', 12, width, height, 1, bpp)
        pal = b''.join(bytes((b, g, r)) for (r, g, b) in (palette or []))
        return head + pal + pixels + pad
    h = -height if top_down else height
    head = info_header(sizes[header], width, h, bpp, comp, size_image,
                       clr_used)
    mask_bytes = b''
    if header == 'v1':
        if comp == 3:
            mask_bytes = struct.pack('<III', *(masks or (0, 0, 0))[:3])
        elif comp == 6:
            mask_bytes = struct.pack('<IIII', *masks)
    else:
        rgba = masks or (0xFF0000, 0xFF00, 0xFF, 0xFF000000)
        rgba = tuple(rgba) + (0,) * (4 - len(rgba))
        if header == 'v2':
            head += struct.pack('<III', *rgba[:3])
        else:
            head += struct.pack('<IIII', *rgba)
        if header in ('v4', 'v5'):
            head += struct.pack('<I', 0x73524742)          # CSType 'sRGB'
            head += b'\0' * 36 + b'\0' * 12                # endpoints, gamma
        if header == 'v5':
            head += struct.pack('<IIII', 4, 0, 0, 0)       # intent, profile
    assert len(head) == sizes[header], (header, len(head))
    pal = b''.join(bytes((b, g, r, 0)) for (r, g, b) in (palette or []))
    return head + mask_bytes + pal + pixels + pad


def ref_bmp(dib):
    """Independent reference for BuildBmpFromDib: the .bmp file bytes for a
    packed DIB, or None if it must be rejected."""
    if len(dib) < 12 or len(dib) > 512 * 1024 * 1024:
        return None
    (hs,) = struct.unpack_from('<I', dib, 0)
    entry, mask_bytes, comp, size_image, clr_used = 4, 0, 0, 0, 0
    standard = True
    if hs == 12:
        w, h, _planes, bpp = struct.unpack_from('<HHHH', dib, 4)
        entry = 3
    elif hs in (40, 52, 56, 108, 124):
        if len(dib) < hs:
            return None
        (w, h, _p, bpp, comp, size_image, _x, _y, clr_used,
         _imp) = struct.unpack_from('<iiHHIIiiII', dib, 4)
        if w <= 0 or h == 0:
            return None
        h = abs(h)
        if comp == 3:
            mask_bytes = 12 if hs == 40 else 0
        elif comp == 6:
            mask_bytes = 16 if hs == 40 else 0
        elif comp not in (0, 1, 2):
            return None
        if comp in (3, 6):
            if bpp not in (16, 32) or len(dib) < 52:
                return None
            standard = struct.unpack_from('<III', dib, 40) == (
                0xFF0000, 0xFF00, 0xFF)
    else:
        return None
    if bpp not in (1, 4, 8, 16, 24, 32):
        return None
    if (comp == 1 and bpp != 8) or (comp == 2 and bpp != 4):
        return None
    if w == 0 or h == 0 or w > 1 << 24 or h > 1 << 24:
        return None
    colors = clr_used
    if bpp <= 8:
        if colors == 0:
            colors = 1 << bpp
        if colors > 1 << bpp:
            return None
    elif colors > 65536:
        return None
    bits = hs + mask_bytes + colors * entry
    if bits >= len(dib):
        return None
    if comp in (1, 2):
        total = len(dib)
        if size_image and bits + size_image <= len(dib):
            total = bits + size_image
    else:
        stride = ((w * bpp + 31) // 32) * 4
        total = bits + stride * h
        if total > len(dib):
            return None
    body = bytearray(dib[:total])
    if bpp == 32 and standard:
        alpha = body[bits + 3:total:4]
        if not any(alpha):
            for i in range(bits + 3, total, 4):
                body[i] = 0xFF
    if 14 + total > 0xFFFFFFFF:
        return None
    return b'BM' + struct.pack('<IHHI', 14 + total, 0, 0, 14 + bits) + \
        bytes(body)


def convert(dib):
    p = run(['dib2bmp', tmp('in.dib', dib), os.path.join(BUILD, 'out.bmp')])
    return read(os.path.join(BUILD, 'out.bmp')) if p.returncode == 0 else None


def rand_rows(rng, w, h, make):
    return [[make(rng) for _ in range(w)] for _ in range(h)]


def rgb(rng):
    return (rng.randrange(256), rng.randrange(256), rng.randrange(256))


def rgba(rng, alpha=None):
    return rgb(rng) + (rng.randrange(256) if alpha is None else alpha,)


def open_bmp(data):
    im = Image.open(io.BytesIO(data))
    im.load()
    return im


class DibToBmp(unittest.TestCase):
    def check(self, dib, *, expect_bytes_equal_ref=True):
        got = convert(dib)
        want = ref_bmp(dib)
        if expect_bytes_equal_ref:
            self.assertEqual(got, want)
        return got

    def test_24bit_bottom_up_and_top_down_all_row_paddings(self):
        rng = random.Random(1)
        for w in range(1, 9):
            for h in (1, 2, 5):
                for top_down in (False, True):
                    rows = rand_rows(rng, w, h, rgb)
                    dib = make_dib(w, h, 24, rows, top_down=top_down)
                    bmp = self.check(dib)
                    im = open_bmp(bmp)
                    self.assertEqual(im.size, (w, h))
                    self.assertEqual(
                        np.asarray(im.convert('RGB')).tolist(),
                        [[list(p) for p in r] for r in rows])

    def test_globalsize_padding_after_the_pixels_is_trimmed(self):
        rng = random.Random(2)
        rows = rand_rows(rng, 5, 3, rgb)
        plain = make_dib(5, 3, 24, rows)
        padded = make_dib(5, 3, 24, rows, pad=b'\xAB' * 13)
        self.assertEqual(convert(plain), convert(padded))
        self.assertEqual(len(convert(plain)), 14 + len(plain))

    def test_32bit_bi_rgb_zero_alpha_becomes_opaque(self):
        rng = random.Random(3)
        rows = rand_rows(rng, 7, 4, lambda r: rgba(r, 0))
        dib = make_dib(7, 4, 32, rows)
        bmp = self.check(dib)
        im = open_bmp(bmp).convert('RGBA')
        want = [[list(p[:3]) + [255] for p in r] for r in rows]
        self.assertEqual(np.asarray(im).tolist(), want)
        # the X byte really is 0xFF in the file (decoders that honor alpha)
        body = bmp[14 + 40:]
        self.assertTrue(all(b == 255 for b in body[3::4]))

    def test_32bit_real_alpha_is_left_alone(self):
        rng = random.Random(4)
        rows = rand_rows(rng, 6, 3, rgba)
        rows[0][0] = rows[0][0][:3] + (7,)  # make sure some alpha is non-zero
        dib = make_dib(6, 3, 32, rows, header='v4', comp=3,
                       masks=(0xFF0000, 0xFF00, 0xFF, 0xFF000000))
        bmp = self.check(dib)
        self.assertEqual(bmp[14:], dib)
        im = open_bmp(bmp)
        self.assertEqual(im.mode, 'RGBA')
        self.assertEqual(np.asarray(im).tolist(),
                         [[list(p) for p in r] for r in rows])

    def test_32bit_bitfields_v1_masks_after_header(self):
        rng = random.Random(5)
        rows = rand_rows(rng, 5, 5, lambda r: rgba(r, 0))
        dib = make_dib(5, 5, 32, rows, comp=3,
                       masks=(0xFF0000, 0xFF00, 0xFF))
        bmp = self.check(dib)
        self.assertEqual(struct.unpack_from('<I', bmp, 10)[0], 14 + 40 + 12)
        im = open_bmp(bmp)
        self.assertEqual(np.asarray(im.convert('RGB')).tolist(),
                         [[list(p[:3]) for p in r] for r in rows])

    def test_alpha_bitfields_v1_offset_counts_four_masks(self):
        rng = random.Random(6)
        rows = rand_rows(rng, 3, 3, lambda r: rgba(r, 0))
        dib = make_dib(3, 3, 32, rows, comp=6,
                       masks=(0xFF0000, 0xFF00, 0xFF, 0xFF000000))
        bmp = self.check(dib)
        self.assertEqual(struct.unpack_from('<I', bmp, 10)[0], 14 + 40 + 16)

    def test_v2_v3_v4_v5_headers(self):
        rng = random.Random(7)
        for header, size in (('v2', 52), ('v3', 56), ('v4', 108),
                             ('v5', 124)):
            rows = rand_rows(rng, 4, 3, lambda r: rgba(r, 0))
            dib = make_dib(4, 3, 32, rows, header=header, comp=3)
            bmp = self.check(dib)
            self.assertEqual(struct.unpack_from('<I', bmp, 10)[0],
                             14 + size, header)
            im = open_bmp(bmp).convert('RGBA')
            self.assertEqual(np.asarray(im).tolist(),
                             [[list(p[:3]) + [255] for p in r] for r in rows],
                             header)

    def test_palette_8bit_default_and_explicit_color_count(self):
        rng = random.Random(8)
        palette = [rgb(rng) for _ in range(256)]
        rows = rand_rows(rng, 7, 4, lambda r: r.randrange(256))
        dib = make_dib(7, 4, 8, rows, palette=palette)
        bmp = self.check(dib)
        self.assertEqual(struct.unpack_from('<I', bmp, 10)[0],
                         14 + 40 + 256 * 4)
        im = open_bmp(bmp).convert('RGB')
        self.assertEqual(np.asarray(im).tolist(),
                         [[list(palette[i]) for i in r] for r in rows])
        small = palette[:5]
        rows = rand_rows(rng, 7, 4, lambda r: r.randrange(5))
        dib = make_dib(7, 4, 8, rows, palette=small, clr_used=5)
        bmp = self.check(dib)
        self.assertEqual(struct.unpack_from('<I', bmp, 10)[0],
                         14 + 40 + 5 * 4)
        im = open_bmp(bmp).convert('RGB')
        self.assertEqual(np.asarray(im).tolist(),
                         [[list(small[i]) for i in r] for r in rows])

    def test_palette_4bit_and_1bit(self):
        rng = random.Random(9)
        for bpp, n in ((4, 16), (1, 2)):
            palette = [rgb(rng) for _ in range(n)]
            rows = rand_rows(rng, 9, 3, lambda r: r.randrange(n))
            dib = make_dib(9, 3, bpp, rows, palette=palette)
            bmp = self.check(dib)
            im = open_bmp(bmp).convert('RGB')
            self.assertEqual(np.asarray(im).tolist(),
                             [[list(palette[i]) for i in r] for r in rows])

    def test_16bit_565_bitfields_and_555(self):
        rng = random.Random(10)
        rows = rand_rows(rng, 5, 3, lambda r: r.randrange(65536))
        dib = make_dib(5, 3, 16, rows, comp=3, masks=(0xF800, 0x7E0, 0x1F))
        bmp = self.check(dib)
        self.assertEqual(struct.unpack_from('<I', bmp, 10)[0], 14 + 40 + 12)
        open_bmp(bmp)  # Pillow decodes it
        dib = make_dib(5, 3, 16, rows)
        self.check(dib)

    def test_core_header_os2(self):
        rng = random.Random(11)
        palette = [rgb(rng) for _ in range(256)]
        rows = rand_rows(rng, 5, 4, lambda r: r.randrange(256))
        dib = make_dib(5, 4, 8, rows, header='core', palette=palette)
        bmp = self.check(dib)
        self.assertEqual(struct.unpack_from('<I', bmp, 10)[0],
                         14 + 12 + 256 * 3)
        im = open_bmp(bmp).convert('RGB')
        self.assertEqual(np.asarray(im).tolist(),
                         [[list(palette[i]) for i in r] for r in rows])
        rows = rand_rows(rng, 3, 3, rgb)
        self.check(make_dib(3, 3, 24, rows, header='core'))

    def test_rle8(self):
        palette = [(i, 255 - i, (i * 7) % 256) for i in range(256)]
        # two rows: 4 x index 9, then 3 x index 200; end-of-line, end-of-bitmap
        rle = bytes([4, 9, 0, 0, 3, 200, 0, 0, 0, 1])
        head = info_header(40, 4, 2, 8, comp=1, size_image=len(rle))
        pal = b''.join(bytes((b, g, r, 0)) for (r, g, b) in palette)
        dib = head + pal + rle
        bmp = self.check(dib + b'\x00' * 9)  # GlobalSize padding
        self.assertEqual(len(bmp), 14 + len(dib))
        im = open_bmp(bmp).convert('RGB')
        self.assertEqual(tuple(im.getpixel((0, 1))), palette[9])
        self.assertEqual(tuple(im.getpixel((0, 0))), palette[200])

    def test_rejects_malformed(self):
        rng = random.Random(12)
        rows = rand_rows(rng, 4, 4, rgb)
        good = make_dib(4, 4, 24, rows)
        self.assertIsNotNone(convert(good))
        bad = {
            'empty': b'',
            'three bytes': b'\x28\x00\x00',
            'truncated pixels': good[:-1],
            'header only': good[:40],
            'header size 41': struct.pack('<I', 41) + good[4:],
            'header size 64 (OS/2 v2)': struct.pack('<I', 64) + good[4:],
            'zero width': good[:4] + struct.pack('<i', 0) + good[8:],
            'negative width': good[:4] + struct.pack('<i', -4) + good[8:],
            'zero height': good[:8] + struct.pack('<i', 0) + good[12:],
            'bit count 0': good[:14] + struct.pack('<H', 0) + good[16:],
            'bit count 3': good[:14] + struct.pack('<H', 3) + good[16:],
            'jpeg': good[:16] + struct.pack('<I', 4) + good[20:],
            'png': good[:16] + struct.pack('<I', 5) + good[20:],
            'bitfields on 24 bit': good[:16] + struct.pack('<I', 3) +
            good[20:],
            'rle8 on 24 bit': good[:16] + struct.pack('<I', 1) + good[20:],
            'huge color table': good[:32] + struct.pack('<I', 0xFFFFFFFF) +
            good[36:],
            'huge dimensions': good[:4] + struct.pack('<ii', 1 << 30,
                                                      1 << 30) + good[12:],
            'dimension 2^24+1': good[:4] + struct.pack('<i', (1 << 24) + 1) +
            good[8:],
        }
        for name, dib in bad.items():
            self.assertIsNone(convert(dib), name)
            self.assertIsNone(ref_bmp(dib), name)

    def test_color_count_over_bit_depth_rejected(self):
        rows = [[0, 1, 0, 1]] * 2
        dib = make_dib(4, 2, 1, rows, palette=[(0, 0, 0)] * 3, clr_used=3)
        self.assertIsNone(convert(dib))

    def test_differential_fuzz(self):
        rng = random.Random(1234)
        palette = [rgb(rng) for _ in range(256)]
        seeds = [
            make_dib(5, 3, 24, rand_rows(rng, 5, 3, rgb)),
            make_dib(5, 3, 32, rand_rows(rng, 5, 3, lambda r: rgba(r, 0)),
                     header='v5', comp=3),
            make_dib(5, 3, 32, rand_rows(rng, 5, 3, rgba), comp=3,
                     masks=(0xFF0000, 0xFF00, 0xFF)),
            make_dib(5, 3, 8, rand_rows(rng, 5, 3, lambda r: r.randrange(256)),
                     palette=palette),
            make_dib(5, 3, 4, rand_rows(rng, 5, 3, lambda r: r.randrange(16)),
                     palette=palette[:16], header='core'),
        ]
        accepted = rejected = 0
        for _ in range(400):
            dib = bytearray(rng.choice(seeds))
            for _ in range(rng.randrange(1, 4)):
                kind = rng.randrange(3)
                if kind == 0 and dib:
                    dib[rng.randrange(min(len(dib), 60))] = rng.randrange(256)
                elif kind == 1 and dib:
                    del dib[rng.randrange(len(dib)):]
                else:
                    dib += bytes(rng.randrange(256)
                                 for _ in range(rng.randrange(20)))
            dib = bytes(dib)
            got = convert(dib)
            want = ref_bmp(dib)
            self.assertEqual(got, want, dib.hex())
            if got is None:
                rejected += 1
            else:
                accepted += 1
                self.assertEqual(got[:2], b'BM')
                self.assertEqual(struct.unpack_from('<I', got, 2)[0],
                                 len(got))
                self.assertLess(struct.unpack_from('<I', got, 10)[0],
                                len(got))
        self.assertGreater(accepted, 20)
        self.assertGreater(rejected, 20)


# ---------------------------------------------------------------------------
# PNG trimming, CF_HDROP, file names
# ---------------------------------------------------------------------------

def png_bytes(w=9, h=5, seed=0):
    rng = np.random.default_rng(seed)
    arr = rng.integers(0, 256, (h, w, 3), dtype=np.uint8)
    out = io.BytesIO()
    Image.fromarray(arr).save(out, 'PNG')
    return out.getvalue()


def png_length(data):
    return int(run(['png', tmp('x.png', data)]).stdout)


def chunk(kind, data=b''):
    body = kind + data
    return struct.pack('>I', len(data)) + body + struct.pack(
        '>I', zlib.crc32(body) & 0xFFFFFFFF)


class PngTrim(unittest.TestCase):
    def test_exact_png(self):
        png = png_bytes()
        self.assertEqual(png_length(png), len(png))

    def test_padding_after_iend_is_cut(self):
        png = png_bytes(31, 17, 1)
        for pad in (b'\0' * 7, b'\0' * 4096, b'\xFF' * 3, b'IEND' * 9):
            self.assertEqual(png_length(png + pad), len(png))

    def test_missing_iend_is_kept_whole(self):
        png = png_bytes(40, 40, 2)
        cut = png[:-12]  # drop IEND
        self.assertEqual(png_length(cut), len(cut))
        self.assertEqual(png_length(cut + b'\0' * 16), len(cut) + 16)

    def test_truncated_mid_chunk_is_kept_whole_with_valid_ihdr(self):
        png = png_bytes(40, 40, 3)
        cut = png[:60]
        self.assertEqual(png_length(cut), len(cut))

    def test_not_png(self):
        self.assertEqual(png_length(b''), 0)
        self.assertEqual(png_length(b'\x89PNG\r\n\x1a\n'), 0)
        self.assertEqual(png_length(b'BM' + b'\0' * 100), 0)
        self.assertEqual(png_length(b'\xFF\xD8\xFF' + b'\0' * 100), 0)
        png = png_bytes()
        self.assertEqual(png_length(b'\0' + png), 0)

    def test_first_chunk_must_be_ihdr_of_13_bytes(self):
        sig = b'\x89PNG\r\n\x1a\n'
        bad = sig + chunk(b'IDAT', b'x' * 13) + chunk(b'IEND')
        self.assertEqual(png_length(bad), 0)
        bad = sig + chunk(b'IHDR', b'x' * 12) + chunk(b'IEND') + b'\0' * 9
        self.assertEqual(png_length(bad), 0)

    def test_chunk_length_beyond_buffer_does_not_overrun(self):
        sig = b'\x89PNG\r\n\x1a\n'
        hdr = chunk(b'IHDR', b'\0' * 13)
        evil = sig + hdr + struct.pack('>I', 0xFFFFFFFF) + b'IDAT' + b'\0' * 8
        self.assertEqual(png_length(evil), len(evil))


def drop_block(paths, *, wide, offset=20, pt=(5, 7), nc=1, double_nul=True):
    enc = 'utf-16-le' if wide else 'cp1252'
    names = b''.join(p.encode(enc) + (b'\0\0' if wide else b'\0')
                     for p in paths)
    if double_nul:
        names += b'\0\0' if wide else b'\0'
    head = struct.pack('<IiiII', offset, pt[0], pt[1], nc, 1 if wide else 0)
    return head + b'\0' * (offset - 20) + names


def drop_entries(data):
    p = run(['drop', tmp('x.drop', data)])
    if p.returncode != 0:
        return None
    lines = p.stdout.decode().split()
    wide = lines[0] == 'wide=1'
    enc = 'utf-16-le' if wide else 'cp1252'
    return wide, [bytes.fromhex(h).decode(enc) for h in lines[1:]]


class RandomBuffers(unittest.TestCase):
    """Garbage and mutated input must never crash or overrun (ASan/UBSan
    abort the harness, which run() reports)."""

    def test_png_and_drop_parsers_survive_garbage(self):
        rng = random.Random(77)
        png = png_bytes(12, 7, 4)
        drop = drop_block(['C:\\a.png', 'D:\\b.jpg'], wide=True)
        for seed in (png, drop, b''):
            for _ in range(120):
                data = bytearray(seed or bytes(rng.randrange(256)
                                               for _ in range(64)))
                for _ in range(rng.randrange(1, 5)):
                    kind = rng.randrange(3)
                    if kind == 0 and data:
                        data[rng.randrange(len(data))] = rng.randrange(256)
                    elif kind == 1 and data:
                        del data[rng.randrange(len(data)):]
                    else:
                        data += bytes(rng.randrange(256) for _ in range(9))
                run(['png', tmp('f.bin', bytes(data))])
                run(['drop', tmp('f.bin', bytes(data))])


class DropFiles(unittest.TestCase):
    def test_wide_and_ansi_lists(self):
        paths = ['C:\\Users\\me\\a.png', 'D:\\x y\\b.JPG', 'E:\\\u00e9.bmp']
        self.assertEqual(drop_entries(drop_block(paths, wide=True)),
                         (True, paths))
        self.assertEqual(drop_entries(drop_block(paths, wide=False)),
                         (False, paths))

    def test_unicode_beyond_ascii_in_wide_lists(self):
        paths = ['C:\\\u0645\u0644\u0641.png', 'C:\\\U0001F600.png']
        self.assertEqual(drop_entries(drop_block(paths, wide=True)),
                         (True, paths))

    def test_entries_after_the_empty_string_are_ignored(self):
        data = drop_block(['C:\\a.png'], wide=True) + 'C:\\b.png'.encode(
            'utf-16-le') + b'\0\0\0\0'
        self.assertEqual(drop_entries(data), (True, ['C:\\a.png']))

    def test_list_may_end_with_the_buffer_and_cut_off_entry_is_dropped(self):
        paths = ['C:\\a.png', 'C:\\b.png']
        for wide, unit in ((True, 2), (False, 1)):
            data = drop_block(paths, wide=wide, double_nul=False)
            # no list terminator, but every entry is terminated: both count
            self.assertEqual(drop_entries(data), (wide, paths))
            # cut inside the last entry: it is dropped
            self.assertEqual(drop_entries(data[:-unit - 1]), (wide, paths[:1]))

    def test_larger_pfiles_offset(self):
        data = drop_block(['C:\\a.png'], wide=True, offset=32)
        self.assertEqual(drop_entries(data), (True, ['C:\\a.png']))

    def test_bad_blocks(self):
        for data in (b'', b'\x14' + b'\0' * 18,
                     drop_block(['C:\\a.png'], wide=True, offset=19),
                     struct.pack('<IiiII', 4096, 0, 0, 0, 1) + b'\0' * 8,
                     drop_block([], wide=True)):
            self.assertIsNone(drop_entries(data))

    def test_odd_offset_in_wide_block_does_not_overrun(self):
        data = struct.pack('<IiiII', 21, 0, 0, 0, 1) + b'\0\0' + b'a\0b'
        drop_entries(data)  # must not crash (ASan)

    def test_drive_paths_only(self):
        for mode in ('char', 'u16'):
            ok = {'C:\\a.png': 1, 'c:/a.png': 1, 'z:\\': 0, '\\\\server\\s\\a.png': 0,
                  '\\\\?\\C:\\a.png': 0, '\\\\.\\PhysicalDrive0': 0,
                  'a.png': 0, '1:\\a.png': 0, 'C:a.png': 0, 'C:': 0, '': 0}
            for path, want in ok.items():
                got = int(run(['drivepath', mode, path]).stdout)
                self.assertEqual(got, want, (mode, path))

    def test_extensions(self):
        table = {'C:\\a.PNG': '.png', 'C:\\a.JpEg': '.jpeg', 'C:\\a.tif': '.tif',
                 'C:\\dir.png\\file': '-', 'C:\\a': '-', 'C:\\a.txt': '-',
                 'C:\\a.png.exe': '-', 'C:\\a.png:stream': '-',
                 'C:\\a. png': '-', 'C:\\.webp': '.webp',
                 'C:\\a.heic': '.heic', 'C:\\a.pngx': '-',
                 'C:\\a.png\u0131': '-', 'C:\\a.': '-',
                 'C:\\very.longextensionname': '-'}
        for mode in ('char', 'u16'):
            for path, want in table.items():
                got = run(['extension', mode, path]).stdout.decode().strip()
                self.assertEqual(got, want, (mode, path))


# ---------------------------------------------------------------------------
# OCR image preparation and text scoring
# ---------------------------------------------------------------------------

def luma(a):
    a = a.astype(np.uint32)
    return ((299 * a[..., 2] + 587 * a[..., 1] + 114 * a[..., 0] + 500) //
            1000).astype(np.uint8)


def ref_gray(bgra, invert):
    y = luma(bgra)
    hist = np.bincount(y.ravel(), minlength=256)
    total = y.size
    cum = np.cumsum(hist)
    low = int(np.argmax(cum >= (total + 99) // 100))
    high = int(np.argmax(cum >= (total * 99 + 99) // 100))
    if high < low + 24:
        low, high = 0, 255
    lut = np.zeros(256, dtype=np.uint32)
    for v in range(256):
        g = 0 if v <= low else (255 if v >= high else
                                (v - low) * 255 // (high - low))
        lut[v] = 255 - g if invert else g
    g = lut[y].astype(np.uint8)
    out = np.empty(bgra.shape, dtype=np.uint8)
    out[..., 0] = out[..., 1] = out[..., 2] = g
    out[..., 3] = 255
    return out


def ref_flatten(bgra):
    if (bgra[..., 3] == 255).all():
        return bgra, False
    a = bgra[..., 3].astype(np.uint64)
    visible = a > 0
    luma_sum = int(luma(bgra)[visible].astype(np.uint64).sum())
    alpha_sum = int(a.sum())
    light = alpha_sum > 0 and (luma_sum * 255) // alpha_sum >= 128
    bg = 0 if light else 255
    behind = 255 - bgra[..., 3].astype(np.uint32)
    out = bgra.copy()
    for c in range(3):
        v = bgra[..., c].astype(np.uint32) + (bg * behind + 127) // 255
        out[..., c] = np.minimum(v, 255).astype(np.uint8)
    out[..., 3] = 255
    return out, True


class OcrPrep(unittest.TestCase):
    def pixels(self, h, w, seed, alpha=None):
        rng = np.random.default_rng(seed)
        a = rng.integers(0, 256, (h, w, 4), dtype=np.uint8)
        if alpha is not None:
            a[..., 3] = alpha
        return a

    def test_gray_matches_reference(self):
        for seed, (h, w) in enumerate([(1, 1), (3, 5), (20, 31), (62, 175)]):
            a = self.pixels(h, w, seed)
            for invert in (0, 1):
                run(['gray', invert, tmp('in.raw', a.tobytes()),
                     os.path.join(BUILD, 'out.raw')])
                got = np.frombuffer(read(os.path.join(BUILD, 'out.raw')),
                                    np.uint8).reshape(a.shape)
                np.testing.assert_array_equal(got, ref_gray(a, invert))

    def test_gray_of_dark_mode_text_makes_dark_on_light(self):
        a = np.zeros((40, 100, 4), np.uint8)
        a[..., :3] = 18
        a[..., 3] = 255
        a[10:14, 10:90, :3] = 205  # a light text line
        run(['gray', 1, tmp('in.raw', a.tobytes()),
             os.path.join(BUILD, 'out.raw')])
        got = np.frombuffer(read(os.path.join(BUILD, 'out.raw')),
                            np.uint8).reshape(a.shape)
        self.assertEqual(int(got[0, 0, 0]), 255)    # background -> white
        self.assertLess(int(got[11, 50, 0]), 40)    # text -> near black
        self.assertTrue((got[..., 3] == 255).all())

    def test_flat_image_is_not_stretched(self):
        a = np.full((10, 10, 4), 255, np.uint8)
        a[..., :3] = 77
        run(['gray', 0, tmp('in.raw', a.tobytes()),
             os.path.join(BUILD, 'out.raw')])
        got = np.frombuffer(read(os.path.join(BUILD, 'out.raw')), np.uint8)
        self.assertTrue((got.reshape(a.shape)[..., :3] == luma(a)[..., None]).all())

    def test_flatten_alpha_matches_reference(self):
        for seed, (h, w) in enumerate([(1, 1), (4, 7), (30, 30)]):
            for alpha in (None, 0, 128):
                a = self.pixels(h, w, seed + 10, alpha)
                # premultiplied input: color channels cannot exceed alpha
                a[..., :3] = np.minimum(a[..., :3], a[..., 3:4])
                p = run(['flatten', tmp('in.raw', a.tobytes()),
                         os.path.join(BUILD, 'out.raw')])
                got = np.frombuffer(read(os.path.join(BUILD, 'out.raw')),
                                    np.uint8).reshape(a.shape)
                want, changed = ref_flatten(a)
                np.testing.assert_array_equal(got, want)
                self.assertEqual(int(p.stdout), int(changed))

    def test_flatten_picks_contrasting_background(self):
        light = np.zeros((4, 4, 4), np.uint8)   # transparent...
        light[1, 1] = (250, 250, 250, 255)      # ...with one white pixel
        dark = np.zeros((4, 4, 4), np.uint8)
        dark[1, 1] = (10, 10, 10, 255)
        for a, want in ((light, 0), (dark, 255)):
            run(['flatten', tmp('in.raw', a.tobytes()),
                 os.path.join(BUILD, 'out.raw')])
            got = np.frombuffer(read(os.path.join(BUILD, 'out.raw')),
                                np.uint8).reshape(a.shape)
            self.assertEqual(int(got[0, 0, 0]), want)
            self.assertTrue((got[..., 3] == 255).all())

    def test_translucent_and_median(self):
        a = self.pixels(8, 8, 3, 255)
        self.assertEqual(int(run(['translucent', tmp('a.raw', a.tobytes())]).stdout), 0)
        a[3, 3, 3] = 254
        self.assertEqual(int(run(['translucent', tmp('a.raw', a.tobytes())]).stdout), 1)
        for seed in range(5):
            a = self.pixels(11, 13, seed)
            y = np.sort(luma(a).ravel())
            want = int(y[(y.size + 1) // 2 - 1])  # first v with cum*2 >= n
            got = int(run(['median', tmp('a.raw', a.tobytes())]).stdout)
            self.assertEqual(got, want)

    def test_pad(self):
        a = self.pixels(3, 4, 5, 255)
        p = run(['pad', 4, 3, 5, 77, tmp('in.raw', a.tobytes()),
                 os.path.join(BUILD, 'out.raw')])
        self.assertEqual(p.stdout.decode().split(), ['14', '13'])
        got = np.frombuffer(read(os.path.join(BUILD, 'out.raw')),
                            np.uint8).reshape(13, 14, 4)
        want = np.zeros((13, 14, 4), np.uint8)
        want[..., :3] = 77
        want[..., 3] = 255
        want[5:8, 5:9] = a
        np.testing.assert_array_equal(got, want)
        p = run(['pad', 4, 3, 0, 77, tmp('in.raw', a.tobytes()),
                 os.path.join(BUILD, 'out.raw')])
        self.assertEqual(p.stdout.decode().split(), ['4', '3'])

    def test_fit_dimensions(self):
        cases = {(100, 50, 2600): (100, 50), (2600, 1000, 2600): (2600, 1000),
                 (5200, 2600, 2600): (2600, 1300), (3840, 2160, 2600): (2600, 1463),
                 (1000, 10000, 2600): (260, 2600), (10000, 1, 2600): (2600, 1),
                 (4001, 3001, 2600): (2600, 1950)}
        for (w, h, m), want in cases.items():
            got = tuple(int(x) for x in run(['fit', w, h, m]).stdout.split())
            self.assertEqual(got, want, (w, h, m))
            self.assertLessEqual(max(got), m)

    def test_pad_amount_keeps_the_image_within_the_engine_limit(self):
        self.assertEqual(int(run(['padamount', 525, 186, 2600]).stdout), 23)
        self.assertEqual(int(run(['padamount', 50, 20, 2600]).stdout), 12)
        self.assertEqual(int(run(['padamount', 2000, 2000, 2600]).stdout), 48)
        self.assertEqual(int(run(['padamount', 2600, 1000, 2600]).stdout), 0)
        self.assertEqual(int(run(['padamount', 2590, 100, 2600]).stdout), 5)

    def plan(self, w, h, median, max_dim=2600, pre=1):
        out = run(['plan', w, h, median, max_dim, pre]).stdout.decode()
        return [l.split(' ', 3) for l in out.strip().split('\n')]

    def test_plan_for_a_tiny_dark_mode_crop(self):
        plan = self.plan(175, 62, 18)
        # tiny: the enlarged attempts come before the same-size one
        self.assertEqual([p[3] for p in plan], [
            'original', 'x3-inverted', 'x2-inverted', 'x4-inverted',
            'x6-inverted', 'x3', 'inverted'])
        self.assertEqual(plan[0][:3], ['1', '0', '0'])         # as decoded
        self.assertEqual(plan[1][:3], ['3', '1', '1'])         # gray, inverted
        self.assertEqual(plan[-1][:3], ['1', '1', '1'])        # 1x, inverted

    def test_plan_for_a_tiny_light_crop(self):
        plan = self.plan(175, 62, 230)
        self.assertEqual([p[3] for p in plan], [
            'original', 'x3-contrast', 'x2-contrast', 'x4-contrast',
            'x6-contrast', 'contrast'])
        self.assertTrue(all(p[2] == '0' for p in plan))

    def test_plan_for_a_mid_size_image_keeps_same_size_attempts_first(self):
        names = [p[3] for p in self.plan(600, 400, 20)]
        self.assertEqual(names[:2], ['original', 'inverted'])
        self.assertEqual(names[2], 'x2-inverted')  # 3x would pass 1600 px

    def test_plan_for_ambiguous_midtones_tries_both_polarities(self):
        names = [p[3] for p in self.plan(300, 100, 130)]
        self.assertIn('contrast', names)
        self.assertIn('inverted', names)

    def test_plan_for_full_screenshots_does_not_upscale(self):
        self.assertEqual([p[3] for p in self.plan(1920, 1080, 240)],
                         ['original'])
        self.assertEqual([p[3] for p in self.plan(1200, 700, 240)],
                         ['original', 'contrast'])
        self.assertEqual([p[3] for p in self.plan(1920, 1080, 20)],
                         ['original', 'inverted'])

    def test_plan_scales_never_exceed_the_engine_limit(self):
        for w, h in ((175, 62), (400, 300), (850, 600), (890, 880)):
            for m in (400, 1200, 2600):
                for p in self.plan(w, h, 20, m):
                    self.assertLessEqual(max(w, h) * int(p[0]), max(m, max(w, h)))

    def test_plan_without_preprocessing_is_just_the_original(self):
        self.assertEqual([p[3] for p in self.plan(175, 62, 18, pre=0)],
                         ['original'])

    def score(self, lines):
        out = run(['score'], stdin='\n'.join(lines).encode() + b'\n').stdout
        s, e, c = (int(x) for x in out.split())
        return s, bool(e), bool(c)

    def test_scoring_prefers_email_and_password_over_one_of_them(self):
        both = self.score(['abcde07@hotmail.com', 'xQmR42abCD5k'])
        pw_only = self.score(['xQmR42abCD5k'])
        garbage = self.score(['|', '~ ~', '\\'])
        self.assertTrue(both[1] and both[2])
        self.assertFalse(pw_only[1] or pw_only[2])
        self.assertGreater(both[0], pw_only[0])
        self.assertGreater(pw_only[0], garbage[0])
        self.assertEqual(self.score([]), (0, False, False))

    def test_email_shape_detection(self):
        yes = ['abcde07@hotmail.com', 'a b c d e @ h o t m a i l . c o m',
               'abcde07 @ hotmail . com', 'Email: abcde07@mail.co.uk now',
               'x_y.z+tag@sub.example.org']
        no = ['abcde07@hotmail', 'abcde07@hotmail.c', 'a@b.com',
              '@hotmail.com', 'abcde07.hotmail.com', 'abcde07@.com',
              'user@@', 'nothing here']
        for line in yes:
            self.assertTrue(self.score([line])[1], line)
        for line in no:
            self.assertFalse(self.score([line])[1], line)

    def test_complete_needs_email_plus_a_second_substantial_line(self):
        self.assertFalse(self.score(['abcde07@hotmail.com'])[2])
        self.assertFalse(self.score(['abcde07@hotmail.com', 'ab'])[2])
        self.assertTrue(self.score(['abcde07@hotmail.com', 'xQmR42'])[2])
        self.assertFalse(self.score(['xQmR42abCD5k', 'another line'])[2])

    def test_non_ascii_text_counts_as_letters(self):
        self.assertGreater(self.score(['\u0645\u0631\u062d\u0628\u0627 \u0628\u0643'])[0], 5)

    def despace(self, lines):
        out = run(['despace'], stdin='\n'.join(lines).encode() + b'\n').stdout
        return out.decode().split('\n')[:-1]

    def test_letter_spaced_lines_are_joined(self):
        self.assertEqual(
            self.despace(['a b c d e @ h o t m a i l . c o m',
                          'x Q m R 4 2 a b C D 5 k',
                          'Password: xQmR42abCD5k',
                          'abcde07@hotmail.com',
                          'a b c d',          # too short to be sure
                          'I am a b c d e f g h h h',
                          'Sign in to your account']),
            ['abcde@hotmail.com', 'xQmR42abCD5k', 'Password: xQmR42abCD5k',
             'abcde07@hotmail.com', 'a b c d', 'Iamabcdefghhh',
             'Sign in to your account'])

    def merge(self, attempts, best):
        stdin = '\n---\n'.join(
            '%d %d\n%s' % (score, complete, '\n'.join(lines))
            for (score, complete, lines) in attempts) + '\n'
        out = run(['merge', best], stdin=stdin.encode()).stdout.decode()
        return out.split('\n')[:-1]

    def test_merge_keeps_a_complete_best_attempt_unchanged(self):
        best = (60, 1, ['abcde07@hotmail.com', 'xQmR42abCD5k'])
        other = (30, 0, ['something else entirely'])
        self.assertEqual(self.merge([other, best], 1),
                         ['abcde07@hotmail.com', 'xQmR42abCD5k'])

    def test_merge_adds_the_email_found_only_by_another_attempt(self):
        plain = (14, 0, ['xQmR42abCD5k'])
        upscaled = (40, 0, ['abcde07@hotmail.com'])
        self.assertEqual(self.merge([plain, upscaled], 0),
                         ['xQmR42abCD5k', 'abcde07@hotmail.com'])
        # the better attempt is first, whichever index it has
        self.assertEqual(self.merge([plain, upscaled], 1),
                         ['abcde07@hotmail.com', 'xQmR42abCD5k'])

    def test_merge_skips_rereadings_of_a_line_already_present(self):
        best = (45, 0, ['abcde07@hotmail.com', 'xQmR42abCD5k'])
        again = (44, 0, ['abcde07@hotrnail.com', 'xQmR42abCD5K',
                         'xQmR42abCD5', 'abcde07@hotmail.com'])
        self.assertEqual(self.merge([best, again], 0), best[2])

    def test_merge_ignores_junk_and_caps_the_count(self):
        best = (10, 0, ['abcde07@hotmail.com'])
        junk = (5, 0, ['|', 'l I', '~~~ ^^', 'a1', '. , ; :'])
        self.assertEqual(self.merge([best, junk], 0), best[2])
        many = (9, 0, ['Welcome back dear user', 'Forgot your password',
                       'Remember this device', 'Create new account',
                       'Terms of service apply', 'Privacy policy here',
                       'Contact support team', 'Download our app now',
                       'Language settings menu', 'Accessibility options'])
        merged = self.merge([best, many], 0)
        self.assertEqual(len(merged), 8)
        self.assertEqual(merged[0], 'abcde07@hotmail.com')

    def test_merge_keeps_unrelated_lines_from_other_attempts(self):
        best = (12, 0, ['Sign in to Example'])
        other = (11, 0, ['abcde07@hotmail.com', 'xQmR42abCD5k'])
        self.assertEqual(self.merge([best, other], 0),
                         ['Sign in to Example', 'abcde07@hotmail.com',
                          'xQmR42abCD5k'])

    def test_lower_ascii(self):
        out = run(['lower'], stdin='En-US \u00c9AR-sa\n'.encode()).stdout
        self.assertEqual(out.decode(), 'en-us \u00c9ar-sa\n')

    def test_blank(self):
        for line, want in (('', 1), ('   \t', 1), (' a ', 0)):
            out = run(['blank'], stdin=line.encode() + b'\n').stdout
            self.assertEqual(int(out), want, line)


# ---------------------------------------------------------------------------
# mingw syntax check of the Windows-only parts (optional)
# ---------------------------------------------------------------------------

FLUTTER_ENGINE = '/opt/flutter/engine/src/flutter/shell/platform'
FLUTTER_WRAPPERS = [FLUTTER_ENGINE + '/windows/client_wrapper/include/flutter',
                    FLUTTER_ENGINE + '/common/client_wrapper/include/flutter']
FLUTTER_PUBLIC = [FLUTTER_ENGINE + '/windows/public',
                  FLUTTER_ENGINE + '/common/public']


def flutter_include_dir():
    """Merges the two client wrapper header dirs, like the ephemeral
    cpp_client_wrapper/include/flutter directory of a real Windows build."""
    root = os.path.join(BUILD, 'cpp_client_wrapper')
    merged = os.path.join(root, 'flutter')
    os.makedirs(merged, exist_ok=True)
    for src in FLUTTER_WRAPPERS:
        for name in os.listdir(src):
            if name.endswith('.h'):
                shutil.copy(os.path.join(src, name), merged)
    return root


class MingwSyntax(unittest.TestCase):
    """-fsyntax-only with mingw-w64 against the real windows.h and the
    Flutter wrapper headers. If VAULTSNAP_WINRT_HEADERS points at the output
    of fetch_winrt_headers.py the OCR section is compiled against the real
    C++/WinRT API too (this caught a wrong enum name); otherwise that section
    is replaced by a stub and only reviewed by hand."""

    @unittest.skipUnless(shutil.which('x86_64-w64-mingw32-g++'),
                         'mingw-w64 g++ not installed')
    @unittest.skipUnless(os.path.isdir(FLUTTER_WRAPPERS[0]),
                         'Flutter engine headers not found')
    def test_runner_code_compiles(self):
        with open(SOURCE, encoding='utf-8') as f:
            src = f.read()
        winrt = os.environ.get('VAULTSNAP_WINRT_HEADERS')
        extra = []
        if winrt and os.path.isdir(os.path.join(winrt, 'winrt')):
            # the headers are lowercase, the code includes <winrt/Windows.X.h>
            src = re.sub(r'#include <winrt/([^>]+)>',
                         lambda m: '#include <winrt/%s>' % m.group(1).lower(),
                         src)
            extra = ['-fcoroutines', '-isystem', winrt]
        else:
            src = re.sub(r'#include <winrt/[^>]+>\n', '', src)
            lines = src.split('\n')
            begin = next(i for i, l in enumerate(lines)
                         if l.startswith('// WINRT-BEGIN'))
            end = next(i for i, l in enumerate(lines)
                       if l.startswith('// WINRT-END'))
            lines[begin:end] = [
                'OcrOutcome RunOcr(const std::wstring& path, bool pre) {',
                '  (void)path; (void)pre;',
                '  return OcrOutcome();', '}']
            src = '\n'.join(lines)
        path = os.path.join(BUILD, 'platform_channel_check.cpp')
        with open(path, 'w') as f:
            f.write(src)
        shutil.copy(os.path.join(os.path.dirname(SOURCE), 'platform_channel.h'),
                    BUILD)
        cmd = ['x86_64-w64-mingw32-g++', '-std=c++20', '-fsyntax-only',
               '-Wall', '-Wextra', '-Wshadow', '-Wconversion', '-DUNICODE',
               '-D_UNICODE', '-DNOMINMAX', '-I', BUILD] + extra
        for inc in [flutter_include_dir()] + FLUTTER_PUBLIC:
            cmd += ['-isystem', inc]
        p = subprocess.run(cmd + [path], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr[-4000:])
        self.assertEqual(p.stderr.strip(), '', p.stderr[-4000:])


if __name__ == '__main__':
    build_harness()
    try:
        unittest.main(argv=[sys.argv[0]] + sys.argv[1:], verbosity=1)
    finally:
        shutil.rmtree(BUILD, ignore_errors=True)
