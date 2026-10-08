#include "platform_channel.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <objbase.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

// Method channel "app.vaultsnap/platform" (Windows side).
//
//   readClipboard -> {"imagePath": "<temp .png/.bmp/.jpg...>"} | {"text": ...}
//                    | {} ; an extra "imageError": "image_unreadable" says an
//                    image was on the clipboard but could not be converted.
//                    Error "clipboard_busy" if the clipboard could not be
//                    opened. The image file is a plaintext copy in %TEMP%:
//                    Dart deletes it ("deleteImage") as soon as OCR is done,
//                    and startup sweeps any leftovers.
//   ocr {path, detailed?: bool, preprocess?: bool}
//        default  -> List<String>: the best attempt's lines; if that attempt
//                    did not find an email plus another line, lines that only
//                    other attempts read are appended (at most 8 in all).
//        detailed -> Map: "lines" (the same list), "rawLines" (the best
//                    attempt's, before letter-spacing repair), "text"
//                    (OcrResult.Text of the best attempt, never mixed into
//                    "lines"), "words" (list of
//                    {text,x,y,width,height,line} in the ORIGINAL image's
//                    pixel space), "language", "attempt", "score", "width",
//                    "height" and "attempts" (every attempt with its own
//                    "attempt" name, "language", "score" and "lines").
//                    A word's "line" indexes "lines" (the best attempt's
//                    lines come first in it).
//        preprocess (default true) allows extra attempts (upscaled, inverted,
//        contrast-stretched); false runs the image once, as decoded.
//        Errors: ocr_bad_arguments, ocr_file_unreadable,
//        ocr_unsupported_image, ocr_image_too_large, ocr_no_language (no OCR
//        language pack installed: ask the user to add one in Windows
//        Settings), ocr_failed. Error messages never contain image text.

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

// ===========================================================================
// PURE-BEGIN
//
// Everything up to PURE-END uses only the C++ standard library (no Windows,
// Flutter or WinRT types) so tool/native_tests/run_tests.py can compile this
// exact text with plain g++ and check it against Python/Pillow references.
// ===========================================================================

constexpr uint32_t kBiRgb = 0;
constexpr uint32_t kBiRle8 = 1;
constexpr uint32_t kBiRle4 = 2;
constexpr uint32_t kBiBitfields = 3;
// RGBA masks after a BITMAPINFOHEADER (missing from some wingdi.h versions).
constexpr uint32_t kBiAlphaBitfields = 6;
constexpr size_t kBmpFileHeaderSize = 14;
// Refuse to copy clipboard images bigger than this (memory and temp space).
constexpr uint64_t kMaxClipboardImageBytes = uint64_t{512} << 20;
constexpr uint32_t kMaxDibDimension = uint32_t{1} << 24;

uint16_t ReadLe16(const uint8_t* p) {
  return static_cast<uint16_t>(p[0] | (p[1] << 8));
}

uint32_t ReadLe32(const uint8_t* p) {
  return uint32_t{p[0]} | (uint32_t{p[1]} << 8) | (uint32_t{p[2]} << 16) |
         (uint32_t{p[3]} << 24);
}

uint32_t ReadBe32(const uint8_t* p) {
  return (uint32_t{p[0]} << 24) | (uint32_t{p[1]} << 16) |
         (uint32_t{p[2]} << 8) | uint32_t{p[3]};
}

void AppendLe16(std::vector<uint8_t>* out, uint32_t value) {
  out->push_back(static_cast<uint8_t>(value & 0xFF));
  out->push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
}

void AppendLe32(std::vector<uint8_t>* out, uint32_t value) {
  AppendLe16(out, value & 0xFFFF);
  AppendLe16(out, value >> 16);
}

// What a packed DIB (CF_DIB / CF_DIBV5) looks like inside.
struct DibInfo {
  uint64_t bits_offset = 0;  // from the start of the DIB to the pixels
  uint64_t total = 0;        // bytes of the DIB worth keeping
  uint32_t width = 0;
  uint32_t height = 0;  // absolute value (top-down DIBs are negative)
  bool zero_alpha_fixable = false;  // 32 bpp B,G,R,A byte order
};

// Validates a packed DIB and works out where its pixels start and where they
// end. Rejects anything a .bmp reader would reject or misread (embedded
// JPEG/PNG, bad bit counts, truncated pixel data) so the caller can fall
// back to another clipboard format instead of writing a broken file.
bool ParseDib(const uint8_t* dib, size_t size, DibInfo* info) {
  if (dib == nullptr || size < 12 || size > kMaxClipboardImageBytes) {
    return false;
  }
  const uint32_t header_size = ReadLe32(dib);
  uint32_t width = 0;
  int64_t height = 0;
  uint32_t bit_count = 0;
  uint32_t compression = kBiRgb;
  uint32_t size_image = 0;
  uint32_t colors_used = 0;
  uint64_t entry_size = 4;  // RGBQUAD
  uint64_t mask_bytes = 0;
  bool rgb_masks_standard = true;
  if (header_size == 12) {
    // BITMAPCOREHEADER (OS/2 1.x): 16-bit sizes, RGBTRIPLE palette.
    width = ReadLe16(dib + 4);
    height = ReadLe16(dib + 6);
    bit_count = ReadLe16(dib + 10);
    entry_size = 3;
  } else if (header_size == 40 || header_size == 52 || header_size == 56 ||
             header_size == 108 || header_size == 124) {
    // BITMAPINFOHEADER and the V2-V5 headers, which start with the same
    // fields and (from V2) hold the color masks themselves.
    if (size < header_size) return false;
    const int32_t raw_width = static_cast<int32_t>(ReadLe32(dib + 4));
    const int32_t raw_height = static_cast<int32_t>(ReadLe32(dib + 8));
    if (raw_width <= 0 || raw_height == 0) return false;
    width = static_cast<uint32_t>(raw_width);
    height = raw_height < 0 ? -int64_t{raw_height} : int64_t{raw_height};
    bit_count = ReadLe16(dib + 14);
    compression = ReadLe32(dib + 16);
    size_image = ReadLe32(dib + 20);
    colors_used = ReadLe32(dib + 32);
    if (compression == kBiBitfields) {
      if (header_size == 40) mask_bytes = 12;
    } else if (compression == kBiAlphaBitfields) {
      if (header_size == 40) mask_bytes = 16;
    } else if (compression != kBiRgb && compression != kBiRle8 &&
               compression != kBiRle4) {
      return false;  // JPEG/PNG inside a DIB (printers), Huffman 1D, ...
    }
    if (compression == kBiBitfields || compression == kBiAlphaBitfields) {
      if ((bit_count != 16 && bit_count != 32) || size < 52) return false;
      rgb_masks_standard = ReadLe32(dib + 40) == 0x00FF0000u &&
                           ReadLe32(dib + 44) == 0x0000FF00u &&
                           ReadLe32(dib + 48) == 0x000000FFu;
    }
  } else {
    return false;
  }
  if (bit_count != 1 && bit_count != 4 && bit_count != 8 && bit_count != 16 &&
      bit_count != 24 && bit_count != 32) {
    return false;
  }
  if ((compression == kBiRle8 && bit_count != 8) ||
      (compression == kBiRle4 && bit_count != 4)) {
    return false;
  }
  if (width == 0 || height == 0 || width > kMaxDibDimension ||
      height > kMaxDibDimension) {
    return false;
  }
  uint64_t colors = colors_used;
  if (bit_count <= 8) {
    const uint64_t full = uint64_t{1} << bit_count;
    if (colors == 0) colors = full;
    if (colors > full) return false;
  } else if (colors > 65536) {
    return false;
  }
  const uint64_t bits_offset = header_size + mask_bytes + colors * entry_size;
  if (bits_offset >= size) return false;  // no room left for pixels

  uint64_t total = size;
  if (compression == kBiRle8 || compression == kBiRle4) {
    if (size_image != 0 && bits_offset + size_image <= size) {
      total = bits_offset + size_image;
    }
  } else {
    // Rows are padded to 4 bytes. biSizeImage may be 0, so compute it.
    const uint64_t stride = ((uint64_t{width} * bit_count + 31) / 32) * 4;
    total = bits_offset + stride * static_cast<uint64_t>(height);
    if (total > size) return false;  // truncated pixel data
  }
  info->bits_offset = bits_offset;
  info->total = total;
  info->width = width;
  info->height = static_cast<uint32_t>(height);
  info->zero_alpha_fixable = bit_count == 32 && rgb_masks_standard;
  return true;
}

// GDI screenshots store 32 bpp pixels with the 4th byte left at 0. Readers
// that honor an alpha channel then show a fully transparent image, which
// OCR sees as nothing. If every alpha byte is 0 it carries no information,
// so make the image opaque. Real alpha (any non-zero byte) is left alone.
void MakeOpaqueIfAlphaUnused(uint8_t* pixels, uint64_t pixel_count) {
  for (uint64_t i = 0; i < pixel_count; ++i) {
    if (pixels[i * 4 + 3] != 0) return;
  }
  for (uint64_t i = 0; i < pixel_count; ++i) pixels[i * 4 + 3] = 0xFF;
}

// Turns a packed clipboard DIB into the bytes of a .bmp file: a
// BITMAPFILEHEADER (bfOffBits counts the header, bit masks and color table)
// followed by the DIB without the padding GlobalSize() adds after the pixels.
bool BuildBmpFromDib(const uint8_t* dib, size_t size,
                     std::vector<uint8_t>* bmp) {
  DibInfo info;
  if (!ParseDib(dib, size, &info)) return false;
  const uint64_t file_size = kBmpFileHeaderSize + info.total;
  if (file_size > 0xFFFFFFFFull) return false;
  bmp->clear();
  bmp->reserve(static_cast<size_t>(file_size));
  bmp->push_back(static_cast<uint8_t>('B'));
  bmp->push_back(static_cast<uint8_t>('M'));
  AppendLe32(bmp, static_cast<uint32_t>(file_size));
  AppendLe16(bmp, 0);
  AppendLe16(bmp, 0);
  AppendLe32(bmp, static_cast<uint32_t>(kBmpFileHeaderSize + info.bits_offset));
  bmp->insert(bmp->end(), dib, dib + static_cast<size_t>(info.total));
  if (info.zero_alpha_fixable) {
    MakeOpaqueIfAlphaUnused(bmp->data() + kBmpFileHeaderSize +
                                static_cast<size_t>(info.bits_offset),
                            uint64_t{info.width} * info.height);
  }
  return true;
}

// Length of the PNG stream at the start of [data] (through the IEND chunk),
// or 0 if it is not a PNG. Clipboard memory is rounded up by GlobalSize(), so
// the block can hold padding after IEND. A PNG that has a valid IHDR but is
// cut off before IEND is kept whole: decoders cope with that.
size_t PngStreamLength(const uint8_t* data, size_t size) {
  static const uint8_t kSignature[8] = {0x89, 'P',  'N',  'G',
                                        0x0D, 0x0A, 0x1A, 0x0A};
  if (data == nullptr || size < 8 + 25 ||
      std::memcmp(data, kSignature, sizeof(kSignature)) != 0) {
    return 0;
  }
  size_t pos = sizeof(kSignature);
  bool saw_header = false;
  while (size - pos >= 12) {
    const uint32_t length = ReadBe32(data + pos);
    const uint8_t* type = data + pos + 4;
    if (length > size - pos - 12) break;  // truncated or garbage
    if (!saw_header) {
      if (std::memcmp(type, "IHDR", 4) != 0 || length != 13) return 0;
      saw_header = true;
    }
    const size_t next = pos + 12 + length;
    if (std::memcmp(type, "IEND", 4) == 0) return next;
    pos = next;
  }
  return saw_header ? size : 0;
}

// Splits the double-NUL-terminated file list of a CF_HDROP (DROPFILES) block.
// Each entry holds the raw bytes of one path: UTF-16LE if [*wide], else the
// ANSI code page. Entries after the first empty string are ignored.
bool ParseDropFiles(const uint8_t* data, size_t size, bool* wide,
                    std::vector<std::string>* entries) {
  constexpr size_t kHeaderSize = 20;  // pFiles, POINT pt, fNC, fWide
  constexpr size_t kMaxEntries = 4096;
  constexpr size_t kMaxEntryBytes = 2 * 32768;
  if (data == nullptr || size < kHeaderSize) return false;
  const uint32_t offset = ReadLe32(data);
  *wide = ReadLe32(data + 16) != 0;
  if (offset < kHeaderSize || offset > size) return false;
  const size_t unit = *wide ? 2 : 1;
  entries->clear();
  size_t pos = offset;
  while (pos + unit <= size && entries->size() < kMaxEntries) {
    size_t end = pos;
    while (end + unit <= size) {
      const bool terminator =
          data[end] == 0 && (unit == 1 || data[end + 1] == 0);
      if (terminator) break;
      end += unit;
    }
    if (end + unit > size) break;  // unterminated: cut off
    if (end == pos) break;         // empty string ends the list
    if (end - pos > kMaxEntryBytes) break;
    entries->emplace_back(reinterpret_cast<const char*>(data + pos), end - pos);
    pos = end + unit;
  }
  return !entries->empty();
}

// "C:\..." or "c:/..." only. UNC paths (\\server\share) and device paths
// (\\.\, \\?\) are refused: reading them could make Windows authenticate to
// a server chosen by whoever put the file list on the clipboard.
template <typename Ch>
bool IsLocalDrivePath(const std::basic_string<Ch>& path) {
  if (path.size() < 4) return false;
  const Ch drive = path[0];
  const bool letter = (drive >= Ch('A') && drive <= Ch('Z')) ||
                      (drive >= Ch('a') && drive <= Ch('z'));
  return letter && path[1] == Ch(':') &&
         (path[2] == Ch('\\') || path[2] == Ch('/'));
}

// The lowercase extension (with the dot) of [path] if it is an image type
// the Windows imaging decoders open, else nullptr.
template <typename Ch>
const char* AllowedImageExtension(const std::basic_string<Ch>& path) {
  static const char* const kAllowed[] = {
      ".png", ".jpg", ".jpeg", ".jpe",  ".jfif", ".bmp", ".dib",
      ".gif", ".tif", ".tiff", ".webp", ".heic", ".heif"};
  size_t dot = std::basic_string<Ch>::npos;
  for (size_t i = path.size(); i > 0; --i) {
    const Ch c = path[i - 1];
    if (c == Ch('\\') || c == Ch('/')) break;
    if (c == Ch('.')) {
      dot = i - 1;
      break;
    }
  }
  if (dot == std::basic_string<Ch>::npos) return nullptr;
  std::string ext;
  for (size_t i = dot; i < path.size(); ++i) {
    const Ch c = path[i];
    if (c > Ch(126) || c < Ch(33)) return nullptr;
    char lower = static_cast<char>(c);
    if (lower >= 'A' && lower <= 'Z') lower = static_cast<char>(lower + 32);
    ext.push_back(lower);
    if (ext.size() > 8) return nullptr;
  }
  for (const char* allowed : kAllowed) {
    if (ext == allowed) return allowed;
  }
  return nullptr;
}

// ---- OCR image preparation (BGRA, 4 bytes per pixel) ----------------------

std::string LowerAscii(std::string s) {
  for (char& c : s) {
    if (c >= 'A' && c <= 'Z') c = static_cast<char>(c + 32);
  }
  return s;
}

uint8_t LumaOf(const uint8_t* bgra) {
  return static_cast<uint8_t>(
      (299u * bgra[2] + 587u * bgra[1] + 114u * bgra[0] + 500u) / 1000u);
}

std::array<uint64_t, 256> LumaHistogram(const std::vector<uint8_t>& bgra) {
  std::array<uint64_t, 256> hist = {};
  for (size_t i = 0; i + 3 < bgra.size(); i += 4) ++hist[LumaOf(&bgra[i])];
  return hist;
}

// Median brightness 0..255; dark-mode screenshots are around 20.
int32_t MedianLuma(const std::vector<uint8_t>& bgra) {
  const std::array<uint64_t, 256> hist = LumaHistogram(bgra);
  const uint64_t total = bgra.size() / 4;
  uint64_t seen = 0;
  for (int32_t v = 0; v < 256; ++v) {
    seen += hist[static_cast<size_t>(v)];
    if (seen * 2 >= total) return v;
  }
  return 255;
}

bool HasTranslucentPixels(const std::vector<uint8_t>& bgra) {
  for (size_t i = 3; i < bgra.size(); i += 4) {
    if (bgra[i] != 0xFF) return true;
  }
  return false;
}

// Composites premultiplied BGRA onto an opaque background that contrasts
// with the visible content (black behind light content, else white), so
// text on a transparent background stays readable. False if already opaque.
bool FlattenAlpha(std::vector<uint8_t>* bgra) {
  if (!HasTranslucentPixels(*bgra)) return false;
  uint64_t luma_sum = 0;
  uint64_t alpha_sum = 0;
  for (size_t i = 0; i + 3 < bgra->size(); i += 4) {
    const uint8_t alpha = (*bgra)[i + 3];
    if (alpha == 0) continue;
    luma_sum += LumaOf(&(*bgra)[i]);
    alpha_sum += alpha;
  }
  const bool light_content =
      alpha_sum > 0 && (luma_sum * 255) / alpha_sum >= 128;
  const uint32_t background = light_content ? 0 : 255;
  for (size_t i = 0; i + 3 < bgra->size(); i += 4) {
    const uint32_t behind = 255 - (*bgra)[i + 3];
    for (size_t c = 0; c < 3; ++c) {
      const uint32_t v = (*bgra)[i + c] + (background * behind + 127) / 255;
      (*bgra)[i + c] = static_cast<uint8_t>(std::min<uint32_t>(v, 255));
    }
    (*bgra)[i + 3] = 0xFF;
  }
  return true;
}

// Grayscale + contrast stretch (1st..99th percentile to 0..255), optionally
// inverted so light-on-dark text becomes dark-on-light, which OCR engines
// read far better. Output is opaque BGRA with B == G == R.
void PrepareGray(std::vector<uint8_t>* bgra, bool invert) {
  const std::array<uint64_t, 256> hist = LumaHistogram(*bgra);
  const uint64_t total = bgra->size() / 4;
  uint32_t low = 0;
  uint32_t high = 255;
  if (total > 0) {
    const uint64_t low_target = (total + 99) / 100;
    const uint64_t high_target = (total * 99 + 99) / 100;
    uint64_t seen = 0;
    bool low_found = false;
    for (uint32_t v = 0; v < 256; ++v) {
      seen += hist[v];
      if (!low_found && seen >= low_target) {
        low = v;
        low_found = true;
      }
      if (seen >= high_target) {
        high = v;
        break;
      }
    }
  }
  if (high < low + 24) {  // flat image: stretching would only add noise
    low = 0;
    high = 255;
  }
  std::array<uint8_t, 256> lut = {};
  for (uint32_t v = 0; v < 256; ++v) {
    uint32_t g = 255;
    if (v <= low) {
      g = 0;
    } else if (v < high) {
      g = (v - low) * 255 / (high - low);
    }
    lut[v] = static_cast<uint8_t>(invert ? 255 - g : g);
  }
  for (size_t i = 0; i + 3 < bgra->size(); i += 4) {
    const uint8_t g = lut[LumaOf(&(*bgra)[i])];
    (*bgra)[i] = g;
    (*bgra)[i + 1] = g;
    (*bgra)[i + 2] = g;
    (*bgra)[i + 3] = 0xFF;
  }
}

// Surrounds a gray BGRA image with [pad] pixels of gray level [level]: OCR
// engines miss text that touches the image edge.
void PadGray(std::vector<uint8_t>* bgra, int32_t* width, int32_t* height,
             int32_t pad, uint8_t level) {
  if (pad <= 0) return;
  const size_t old_w = static_cast<size_t>(*width);
  const size_t old_h = static_cast<size_t>(*height);
  const size_t new_w = old_w + 2 * static_cast<size_t>(pad);
  const size_t new_h = old_h + 2 * static_cast<size_t>(pad);
  std::vector<uint8_t> out(new_w * new_h * 4);
  for (size_t i = 0; i < out.size(); i += 4) {
    out[i] = level;
    out[i + 1] = level;
    out[i + 2] = level;
    out[i + 3] = 0xFF;
  }
  for (size_t y = 0; y < old_h; ++y) {
    std::memcpy(&out[((y + static_cast<size_t>(pad)) * new_w +
                      static_cast<size_t>(pad)) *
                     4],
                &(*bgra)[y * old_w * 4], old_w * 4);
  }
  bgra->swap(out);
  *width = static_cast<int32_t>(new_w);
  *height = static_cast<int32_t>(new_h);
}

// Largest size not above [max_dim] on its long side, keeping the aspect ratio.
void FitDimensions(int32_t width, int32_t height, int32_t max_dim,
                   int32_t* out_width, int32_t* out_height) {
  const int32_t long_side = std::max(width, height);
  if (max_dim <= 0 || long_side <= max_dim) {
    *out_width = width;
    *out_height = height;
    return;
  }
  const int64_t w = (int64_t{width} * max_dim + long_side / 2) / long_side;
  const int64_t h = (int64_t{height} * max_dim + long_side / 2) / long_side;
  *out_width = static_cast<int32_t>(std::max<int64_t>(1, w));
  *out_height = static_cast<int32_t>(std::max<int64_t>(1, h));
}

// Border width for a [width]x[height] gray image that still fits [max_dim].
int32_t PadAmount(int32_t width, int32_t height, int32_t max_dim) {
  const int32_t wanted = std::clamp(std::min(width, height) / 8, 12, 48);
  const int32_t room = (max_dim - std::max(width, height)) / 2;
  return std::max(0, std::min(wanted, room));
}

// One way of presenting the image to the OCR engine.
struct OcrPlan {
  int32_t scale = 1;    // integer enlargement of the (possibly shrunk) image
  bool gray = false;    // contrast stretch + padding
  bool invert = false;  // with gray: light text on dark -> dark on light
  std::string name;
};

// The attempts to make, most promising first. The first is always the image
// exactly as decoded (what the app did before). Tiny crops (a pasted 175x62
// login) get enlarged: Windows OCR reads text under ~20 px high poorly, and
// dark-mode (median brightness < 120) images also get inverted variants. For
// a tiny image the enlarged attempts come before the same-size variants: the
// loop stops at the first attempt that holds an email plus another line, and
// a misread at 1x must not end it before the more accurate enlarged reading.
std::vector<OcrPlan> PlanOcrAttempts(int32_t width, int32_t height,
                                     int32_t median_luma, int32_t max_dim,
                                     bool preprocess) {
  std::vector<OcrPlan> plans;
  plans.push_back({1, false, false, "original"});
  if (!preprocess) return plans;
  const bool dark = median_luma < 120;
  const bool ambiguous = median_luma >= 100 && median_luma <= 160;
  const int32_t long_side = std::max(width, height);
  std::vector<OcrPlan> same_size;
  if (dark) {
    same_size.push_back({1, true, true, "inverted"});
  } else {
    if (long_side <= 1400) same_size.push_back({1, true, false, "contrast"});
    if (ambiguous) same_size.push_back({1, true, true, "inverted"});
  }
  std::vector<OcrPlan> enlarged;
  if (long_side < 900) {
    const int32_t scales[] = {3, 2, 4, 6};
    for (const int32_t scale : scales) {
      if (int64_t{long_side} * scale > 1600 ||
          int64_t{long_side} * scale > max_dim ||
          int64_t{width} * scale * height * scale > 16000000) {
        continue;
      }
      enlarged.push_back(
          {scale, true, dark,
           "x" + std::to_string(scale) + (dark ? "-inverted" : "-contrast")});
    }
    if (dark && int64_t{long_side} * 3 <= max_dim) {
      enlarged.push_back({3, false, false, "x3"});
    }
  }
  const bool tiny = long_side < 400;
  const std::vector<OcrPlan>& first = tiny ? enlarged : same_size;
  const std::vector<OcrPlan>& second = tiny ? same_size : enlarged;
  plans.insert(plans.end(), first.begin(), first.end());
  plans.insert(plans.end(), second.begin(), second.end());
  return plans;
}

// ---- OCR text post-processing ----------------------------------------------

bool IsBlank(const std::string& s) {
  for (const char c : s) {
    if (c != ' ' && c != '\t' && c != '\r' && c != '\n') return false;
  }
  return true;
}

// Tiny text often comes back letter-spaced ("a b c d e @ h o t ..."). A line
// that is almost entirely single-character words is joined back up. Normal
// text never has that shape, so other lines are returned unchanged.
std::string RepairLetterSpacing(const std::string& line) {
  std::vector<std::string> tokens;
  size_t pos = 0;
  while (pos < line.size()) {
    while (pos < line.size() && line[pos] == ' ') ++pos;
    const size_t start = pos;
    while (pos < line.size() && line[pos] != ' ') ++pos;
    if (pos > start) tokens.push_back(line.substr(start, pos - start));
  }
  if (tokens.size() < 5) return line;
  size_t single = 0;
  for (const std::string& token : tokens) {
    if (token.size() == 1) ++single;
  }
  if (single * 5 < tokens.size() * 4) return line;
  std::string joined;
  for (const std::string& token : tokens) joined += token;
  return joined;
}

bool IsAsciiAlnum(char c) {
  return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') ||
         (c >= 'a' && c <= 'z');
}

bool IsEmailLocalChar(char c) {
  return IsAsciiAlnum(c) || c == '.' || c == '_' || c == '%' || c == '+' ||
         c == '-';
}

bool IsEmailDomainChar(char c) {
  return IsAsciiAlnum(c) || c == '.' || c == '-';
}

// True if the line, ignoring spaces, contains something shaped like
// local@domain.tld.
bool LineHasEmail(const std::string& line) {
  std::string s;
  s.reserve(line.size());
  for (const char c : line) {
    if (c != ' ') s.push_back(c);
  }
  const size_t at = s.find('@');
  if (at == std::string::npos) return false;
  size_t local = 0;
  for (size_t i = at; i > 0 && IsEmailLocalChar(s[i - 1]); --i) ++local;
  if (local < 2) return false;
  size_t end = at + 1;
  size_t last_dot = std::string::npos;
  while (end < s.size() && IsEmailDomainChar(s[end])) {
    if (s[end] == '.') last_dot = end;
    ++end;
  }
  if (last_dot == std::string::npos || last_dot <= at + 1) return false;
  return end - last_dot - 1 >= 2;
}

// Characters OCR engines emit for specks and borders rather than text.
bool IsNoiseChar(char c) {
  return c == '|' || c == '\\' || c == '~' || c == '`' || c == '^' ||
         c == '<' || c == '>' || c == '{' || c == '}' || c == '[' || c == ']';
}

struct LinesScore {
  int32_t score = 0;
  bool has_email = false;
  // An email and at least one more substantial line: nothing left to find.
  bool complete = false;
};

// Ranks OCR attempts: more letters and digits is better, an email-shaped line
// is a big plus, noise characters count against. Characters outside ASCII
// count as letters (UTF-8 lead bytes) so other scripts are not penalised.
LinesScore ScoreLines(const std::vector<std::string>& lines) {
  LinesScore result;
  int32_t substantial = 0;
  for (const std::string& line : lines) {
    int32_t alnum = 0;
    int32_t noise = 0;
    for (const char c : line) {
      const auto unit = static_cast<unsigned char>(c);
      if (unit >= 0x80) {
        if ((unit & 0xC0) != 0x80) ++alnum;
      } else if (IsAsciiAlnum(c)) {
        ++alnum;
      } else if (IsNoiseChar(c)) {
        ++noise;
      }
    }
    const bool email = LineHasEmail(line);
    if (email) result.has_email = true;
    result.score += alnum - noise + (email ? 25 : 0);
    if (alnum >= 6) ++substantial;
  }
  result.complete = result.has_email && substantial >= 2;
  return result;
}

// ---- OCR results -----------------------------------------------------------

struct OcrWord {
  std::string text;
  int32_t x = 0;
  int32_t y = 0;
  int32_t width = 0;
  int32_t height = 0;
  int32_t line = 0;  // index into OcrAttempt::lines
};

struct OcrAttempt {
  std::string name;
  std::string language;
  int32_t score = 0;
  bool complete = false;
  std::vector<std::string> lines;      // after RepairLetterSpacing
  std::vector<std::string> raw_lines;  // as the engine returned them
  std::vector<OcrWord> words;
  std::string text;  // the engine's own full text (OcrResult.Text)
};

struct OcrOutcome {
  bool ok = false;
  std::string code;     // error code when !ok
  std::string message;  // error message when !ok; never contains image text
  int32_t width = 0;    // of the original image
  int32_t height = 0;
  std::vector<OcrAttempt> attempts;
  size_t best = 0;                 // index into attempts
  std::vector<std::string> lines;  // MergeAttemptLines(attempts, best)
};

// Lower-case ASCII letters and digits only: what two OCR readings of the same
// line have in common.
std::string NormalizeForCompare(const std::string& line) {
  std::string out;
  for (const char c : line) {
    if (IsAsciiAlnum(c))
      out.push_back(c >= 'A' && c <= 'Z' ? static_cast<char>(c + 32) : c);
  }
  return out;
}

size_t EditDistance(const std::string& a, const std::string& b) {
  std::vector<size_t> previous(b.size() + 1);
  std::vector<size_t> current(b.size() + 1);
  for (size_t j = 0; j <= b.size(); ++j) previous[j] = j;
  for (size_t i = 1; i <= a.size(); ++i) {
    current[0] = i;
    for (size_t j = 1; j <= b.size(); ++j) {
      const size_t substitute =
          previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      current[j] = std::min({previous[j] + 1, current[j - 1] + 1, substitute});
    }
    previous.swap(current);
  }
  return previous[b.size()];
}

// Two readings of the same line differ by a few characters; a line that is
// equal, contained in the other, or within ~1/6 of its length in edits is
// the same line.
bool SimilarLine(const std::string& a, const std::string& b) {
  if (a == b) return true;
  const size_t shortest = std::min(a.size(), b.size());
  if (shortest >= 4 &&
      (a.find(b) != std::string::npos || b.find(a) != std::string::npos)) {
    return true;
  }
  if (a.size() > 96 || b.size() > 96) return false;
  const size_t limit = std::max<size_t>(1, shortest / 6);
  const size_t gap =
      a.size() > b.size() ? a.size() - b.size() : b.size() - a.size();
  return gap <= limit && EditDistance(a, b) <= limit;
}

// A line worth adding from another attempt: mostly letters and digits.
bool IsUsefulLine(const std::string& line) {
  int32_t alnum = 0;
  int32_t visible = 0;
  for (const char c : line) {
    const auto unit = static_cast<unsigned char>(c);
    if (c == ' ' || c == '\t' || (unit >= 0x80 && (unit & 0xC0) == 0x80))
      continue;
    ++visible;
    if (IsAsciiAlnum(c) || unit >= 0x80) ++alnum;
  }
  return alnum >= 4 && alnum * 2 >= visible;
}

// The lines handed to Dart. The best attempt's lines are always first. If it
// found everything (an email and another line) they are returned as they
// are. Otherwise lines that only other attempts read (say, the email that the
// upscaled copy found while the plain copy found only the password) are
// appended, best attempts first, skipping lines that merely re-read a line
// already there. Returns at most 8 lines.
std::vector<std::string> MergeAttemptLines(
    const std::vector<OcrAttempt>& attempts, size_t best) {
  std::vector<std::string> merged = attempts[best].lines;
  if (attempts[best].complete) return merged;
  std::vector<size_t> order;
  for (size_t i = 0; i < attempts.size(); ++i) {
    if (i != best) order.push_back(i);
  }
  std::stable_sort(order.begin(), order.end(), [&attempts](size_t a, size_t b) {
    return attempts[a].score > attempts[b].score;
  });
  std::vector<std::string> known;
  for (const std::string& line : merged)
    known.push_back(NormalizeForCompare(line));
  for (const size_t index : order) {
    for (const std::string& line : attempts[index].lines) {
      if (merged.size() >= 8) return merged;
      if (!IsUsefulLine(line)) continue;
      const std::string normalized = NormalizeForCompare(line);
      bool seen = false;
      for (const std::string& other : known) {
        if (SimilarLine(normalized, other)) {
          seen = true;
          break;
        }
      }
      if (seen) continue;
      known.push_back(normalized);
      merged.push_back(line);
    }
  }
  return merged;
}

// ===========================================================================
// PURE-END
// ===========================================================================

// ===========================================================================
// WIN32-BEGIN  (windows.h only; no WinRT)
// ===========================================================================

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return L"";
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring w(static_cast<size_t>(n), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
  return w;
}

std::string WideToUtf8(const std::wstring& w) {
  if (w.empty()) return "";
  int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0,
                              nullptr, nullptr);
  std::string s(static_cast<size_t>(n), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), s.data(), n, nullptr,
                      nullptr);
  return s;
}

void SecureZero(std::wstring& w) {
  SecureZeroMemory(w.data(), w.size() * sizeof(wchar_t));
}

// Zeroes a byte buffer holding image pixels (they can show a password) when
// it goes out of scope, on every path.
class ScopedWipe {
 public:
  explicit ScopedWipe(std::vector<uint8_t>* bytes) : bytes_(bytes) {}
  ~ScopedWipe() {
    if (!bytes_->empty()) SecureZeroMemory(bytes_->data(), bytes_->size());
  }
  ScopedWipe(const ScopedWipe&) = delete;
  ScopedWipe& operator=(const ScopedWipe&) = delete;

 private:
  std::vector<uint8_t>* bytes_;
};

DWORD g_last_sequence = 0;

void SetDwordFormat(const wchar_t* name, DWORD value) {
  UINT fmt = RegisterClipboardFormatW(name);
  HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
  if (!h) return;
  void* p = GlobalLock(h);
  if (!p) {
    GlobalFree(h);
    return;
  }
  memcpy(p, &value, sizeof(value));
  GlobalUnlock(h);
  if (!SetClipboardData(fmt, h)) GlobalFree(h);
}

// Puts text on the clipboard and asks Windows to keep it out of Clipboard
// History (Win+V), cloud clipboard sync and clipboard monitors.
bool CopySensitive(HWND hwnd, const std::string& utf8) {
  std::wstring w = Utf8ToWide(utf8);
  if (!OpenClipboard(hwnd)) return false;
  EmptyClipboard();
  size_t bytes = (w.size() + 1) * sizeof(wchar_t);
  HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (h) {
    void* p = GlobalLock(h);
    if (p) {
      memcpy(p, w.c_str(), bytes);
      GlobalUnlock(h);
      if (!SetClipboardData(CF_UNICODETEXT, h)) GlobalFree(h);
    } else {
      GlobalFree(h);
    }
  }
  // Documented formats: presence of the first excludes from monitors; the
  // DWORD 0 values opt out of history and cloud upload.
  UINT exclude =
      RegisterClipboardFormatW(L"ExcludeClipboardContentFromMonitorProcessing");
  HGLOBAL e = GlobalAlloc(GMEM_MOVEABLE, 1);
  if (e && !SetClipboardData(exclude, e)) GlobalFree(e);
  SetDwordFormat(L"CanIncludeInClipboardHistory", 0);
  SetDwordFormat(L"CanUploadToCloudClipboard", 0);
  CloseClipboard();
  g_last_sequence = GetClipboardSequenceNumber();
  SecureZero(w);
  return true;
}

// Clears only if nobody wrote to the clipboard since our copy.
void ClearIfUnchanged(HWND hwnd) {
  if (g_last_sequence != 0 && GetClipboardSequenceNumber() == g_last_sequence &&
      OpenClipboard(hwnd)) {
    EmptyClipboard();
    CloseClipboard();
  }
  g_last_sequence = 0;
}

// Unconditional clear, e.g. after saving a login read from a pasted
// screenshot.
bool ClearClipboard(HWND hwnd) {
  if (!OpenClipboard(hwnd)) return false;
  EmptyClipboard();
  CloseClipboard();
  g_last_sequence = 0;
  return true;
}

// Keeps the clipboard open for its lifetime, so every path closes it.
class ClipboardLock {
 public:
  explicit ClipboardLock(HWND hwnd) {
    // Another process (e.g. a clipboard manager) may hold it for a moment.
    for (int attempt = 0; attempt < 10 && !open_; ++attempt) {
      if (attempt > 0) Sleep(20);
      open_ = OpenClipboard(hwnd) != FALSE;
    }
  }
  ~ClipboardLock() {
    if (open_) CloseClipboard();
  }
  ClipboardLock(const ClipboardLock&) = delete;
  ClipboardLock& operator=(const ClipboardLock&) = delete;

  bool is_open() const { return open_; }

 private:
  bool open_ = false;
};

// GlobalLock()s clipboard data (still owned by the clipboard) while in scope.
class LockedGlobal {
 public:
  explicit LockedGlobal(HANDLE handle) : handle_(handle) {
    if (handle_) data_ = static_cast<const BYTE*>(GlobalLock(handle_));
    if (data_) size_ = GlobalSize(handle_);
  }
  ~LockedGlobal() {
    if (data_) GlobalUnlock(handle_);
  }
  LockedGlobal(const LockedGlobal&) = delete;
  LockedGlobal& operator=(const LockedGlobal&) = delete;

  const BYTE* data() const { return data_; }
  SIZE_T size() const { return size_; }

 private:
  HANDLE handle_;
  const BYTE* data_ = nullptr;
  SIZE_T size_ = 0;
};

// Pasted images are written to %TEMP% as "<prefix><guid><extension>".
constexpr wchar_t kClipFilePrefix[] = L"hisn-clip-";

// The user's %TEMP% with a trailing backslash, or "" if unavailable.
std::wstring TempDir() {
  wchar_t dir[MAX_PATH + 1] = {};
  DWORD n = GetTempPathW(MAX_PATH + 1, dir);
  if (n == 0 || n > MAX_PATH) return L"";
  return std::wstring(dir, n);
}

// Creates a new file with an unguessable name in %TEMP% holding [data].
// [extension] includes the dot. Returns its path, or "" on failure (nothing
// is left behind). Dart deletes it once OCR is done.
std::wstring WriteTempFile(const std::wstring& extension, const void* data,
                           SIZE_T size) {
  std::wstring dir = TempDir();
  if (dir.empty()) return L"";
  constexpr int kGuidChars = 40;
  GUID guid = {};
  wchar_t guid_str[kGuidChars] = {};
  if (FAILED(CoCreateGuid(&guid)) ||
      StringFromGUID2(guid, guid_str, kGuidChars) == 0) {
    return L"";
  }
  std::wstring id(guid_str);
  id = id.substr(1, id.size() - 2);  // strip the braces
  std::wstring path = dir + kClipFilePrefix + id + extension;
  // CREATE_NEW: never reuse or follow an existing file.
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                            FILE_ATTRIBUTE_TEMPORARY, nullptr);
  if (file == INVALID_HANDLE_VALUE) return L"";
  constexpr DWORD kMaxChunk = 1u << 30;
  const BYTE* p = static_cast<const BYTE*>(data);
  SIZE_T left = size;
  bool ok = true;
  while (ok && left > 0) {
    DWORD chunk = left > kMaxChunk ? kMaxChunk : static_cast<DWORD>(left);
    DWORD written = 0;
    if (!WriteFile(file, p, chunk, &written, nullptr) || written == 0) {
      ok = false;
    } else {
      p += written;
      left -= written;
    }
  }
  CloseHandle(file);
  if (!ok) {
    DeleteFileW(path.c_str());
    return L"";
  }
  return path;
}

// Deletes pasted images left in %TEMP% when the app died before Dart could
// delete them. Recent ones may belong to another running instance.
void DeleteStaleClipFiles() {
  std::wstring dir = TempDir();
  if (dir.empty()) return;
  WIN32_FIND_DATAW found;
  HANDLE find = FindFirstFileW((dir + kClipFilePrefix + L"*").c_str(), &found);
  if (find == INVALID_HANDLE_VALUE) return;
  auto ticks = [](const FILETIME& ft) {
    return (uint64_t{ft.dwHighDateTime} << 32) | ft.dwLowDateTime;
  };
  FILETIME now;
  GetSystemTimeAsFileTime(&now);
  constexpr uint64_t kMinAge = uint64_t{10} * 60 * 10'000'000;  // 10 min
  do {
    if ((found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) continue;
    if (ticks(found.ftLastWriteTime) + kMinAge > ticks(now)) continue;
    DeleteFileW((dir + found.cFileName).c_str());
  } while (FindNextFileW(find, &found));
  FindClose(find);
}

// Largest image file copied when the user copied a file in Explorer. A
// screenshot or a phone photo is a few MB; this keeps a slow drive from
// holding the window up for long.
constexpr uint64_t kMaxCopiedFileBytes = uint64_t{16} << 20;

std::wstring AsciiToWide(const char* ascii) {
  std::wstring w;
  for (const char* c = ascii; *c != '\0'; ++c) {
    w.push_back(static_cast<wchar_t>(*c));
  }
  return w;
}

// Copies the user's image file into %TEMP% (so Dart can delete the copy; the
// original is only ever opened for reading). "" if it cannot be read, is not
// a plain disk file, or is too big.
std::wstring CopyFileToTemp(const std::wstring& source,
                            const std::wstring& extension) {
  HANDLE in =
      CreateFileW(source.c_str(), GENERIC_READ,
                  FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                  nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (in == INVALID_HANDLE_VALUE) return L"";
  std::vector<uint8_t> bytes;
  ScopedWipe wipe(&bytes);
  LARGE_INTEGER file_size = {};
  bool ok = GetFileType(in) == FILE_TYPE_DISK &&
            GetFileSizeEx(in, &file_size) && file_size.QuadPart > 0 &&
            static_cast<uint64_t>(file_size.QuadPart) <= kMaxCopiedFileBytes;
  if (ok) {
    bytes.resize(static_cast<size_t>(file_size.QuadPart));
    size_t done = 0;
    while (ok && done < bytes.size()) {
      const size_t remaining = bytes.size() - done;
      DWORD chunk =
          remaining > (1u << 24) ? (1u << 24) : static_cast<DWORD>(remaining);
      DWORD got = 0;
      if (!ReadFile(in, bytes.data() + done, chunk, &got, nullptr) ||
          got == 0) {
        ok = false;
      } else {
        done += got;
      }
    }
  }
  CloseHandle(in);
  if (!ok) return L"";
  return WriteTempFile(extension, bytes.data(), bytes.size());
}

// An image file the user copied in Explorer, still to be copied to %TEMP%.
struct DroppedImageFile {
  std::wstring path;
  std::wstring extension;  // with the dot
};

// The user copied files in Explorer: the ones that are images on a local
// drive, in order. Only parses the list (no file is opened), so it is cheap
// while the clipboard is open. [saw_image] is set when a file with an image
// extension was listed.
std::vector<DroppedImageFile> ListDroppedImages(const BYTE* data, SIZE_T size,
                                                bool* saw_image) {
  std::vector<DroppedImageFile> files;
  bool wide = false;
  std::vector<std::string> entries;
  if (!ParseDropFiles(data, size, &wide, &entries)) return files;
  for (const std::string& entry : entries) {
    std::wstring path;
    if (wide) {
      static_assert(sizeof(wchar_t) == 2, "CF_HDROP wide paths are UTF-16");
      path.resize(entry.size() / 2);
      memcpy(path.data(), entry.data(), path.size() * sizeof(wchar_t));
    } else {
      int n = MultiByteToWideChar(CP_ACP, 0, entry.data(), (int)entry.size(),
                                  nullptr, 0);
      if (n <= 0) continue;
      path.resize(static_cast<size_t>(n));
      MultiByteToWideChar(CP_ACP, 0, entry.data(), (int)entry.size(),
                          path.data(), n);
    }
    if (!IsLocalDrivePath(path)) continue;
    const char* extension = AllowedImageExtension(path);
    if (extension == nullptr) continue;
    *saw_image = true;
    files.push_back({path, AsciiToWide(extension)});
  }
  return files;
}

// For the "Paste" button. An image goes to a temp file and {"imagePath"} is
// returned; otherwise {"text"}. In order of preference:
//  1. the registered "PNG" format (Snipping Tool, browsers) or "image/png",
//     trimmed to the real PNG stream;
//  2. a DIB converted to a .bmp (CF_DIB first: its 32bpp pixels decode as
//     opaque, while a CF_DIBV5 alpha mask may cover an all-zero alpha channel
//     (GDI screenshots) and decode as fully transparent; OCR doesn't need
//     alpha);
//  3. an image FILE copied in Explorer (CF_HDROP), copied to temp. The file
//     is copied after the clipboard is closed again: reading it can take
//     seconds on a slow drive, and every other program's clipboard would
//     wait for that.
// nullopt if the clipboard could not be opened.
std::optional<EncodableMap> ReadClipboard(HWND hwnd) {
  std::wstring image;
  bool saw_image = false;  // an image was offered, whether or not we got it
  std::vector<DroppedImageFile> dropped;
  std::optional<std::string> text;
  {
    ClipboardLock lock(hwnd);
    if (!lock.is_open()) return std::nullopt;
    const wchar_t* const png_names[] = {L"PNG", L"image/png"};
    for (const wchar_t* name : png_names) {
      if (!image.empty()) break;
      const UINT format = RegisterClipboardFormatW(name);
      if (format == 0 || !IsClipboardFormatAvailable(format)) continue;
      saw_image = true;
      LockedGlobal data(GetClipboardData(format));
      const size_t length = PngStreamLength(data.data(), data.size());
      if (length > 0) image = WriteTempFile(L".png", data.data(), length);
    }
    const UINT dib_formats[] = {CF_DIB, CF_DIBV5};
    for (UINT format : dib_formats) {
      if (!image.empty() || !IsClipboardFormatAvailable(format)) continue;
      saw_image = true;
      LockedGlobal data(GetClipboardData(format));
      std::vector<uint8_t> bmp;
      ScopedWipe wipe(&bmp);
      bool converted = false;
      try {
        converted = BuildBmpFromDib(data.data(), data.size(), &bmp);
      } catch (...) {
        converted = false;  // out of memory on a huge image
      }
      if (converted) image = WriteTempFile(L".bmp", bmp.data(), bmp.size());
    }
    if (image.empty() && IsClipboardFormatAvailable(CF_HDROP)) {
      LockedGlobal data(GetClipboardData(CF_HDROP));
      try {
        dropped = ListDroppedImages(data.data(), data.size(), &saw_image);
      } catch (...) {
        dropped.clear();
      }
    }
    if (image.empty() && IsClipboardFormatAvailable(CF_UNICODETEXT)) {
      LockedGlobal data(GetClipboardData(CF_UNICODETEXT));
      if (data.data()) {
        const auto* chars = reinterpret_cast<const wchar_t*>(data.data());
        std::wstring wide(chars, wcsnlen(chars, data.size() / sizeof(wchar_t)));
        text = WideToUtf8(wide);
        SecureZero(wide);
      }
    }
  }  // the clipboard is closed: other programs can use it again
  for (const DroppedImageFile& file : dropped) {
    if (!image.empty()) break;
    try {
      image = CopyFileToTemp(file.path, file.extension);
    } catch (...) {
      image.clear();  // out of memory on a big file
    }
  }
  EncodableMap out;
  if (!image.empty()) {
    if (text) SecureZeroMemory(text->data(), text->size());
    out.emplace(EncodableValue("imagePath"), EncodableValue(WideToUtf8(image)));
    return out;
  }
  if (text) {
    out.emplace(EncodableValue("text"), EncodableValue(*text));
    SecureZeroMemory(text->data(), text->size());
  }
  if (saw_image) {
    out.emplace(EncodableValue("imageError"),
                EncodableValue("image_unreadable"));
  }
  return out;
}

// ===========================================================================
// WIN32-END
// ===========================================================================

// ===========================================================================
// WINRT-BEGIN  (Windows.Media.Ocr / Windows.Graphics.Imaging)
// ===========================================================================

namespace wg = winrt::Windows::Globalization;
namespace wgi = winrt::Windows::Graphics::Imaging;
namespace wmo = winrt::Windows::Media::Ocr;
namespace wst = winrt::Windows::Storage;
namespace wss = winrt::Windows::Storage::Streams;

// Only decode images up to this many pixels (a 16384 x 12288 photo).
constexpr uint64_t kMaxSourcePixels = uint64_t{200} * 1000 * 1000;

// Where RunOcr was when something threw: picks the error code.
enum class OcrStage { kInit, kOpen, kDecode, kRecognize };

void SetOcrFailure(OcrOutcome* out, const char* code, const char* what,
                   int32_t hresult) {
  out->ok = false;
  out->code = code;
  char text[128] = {};
  if (hresult != 0) {
    std::snprintf(text, sizeof(text), "%s (0x%08X)", what,
                  static_cast<unsigned>(hresult));
  } else {
    std::snprintf(text, sizeof(text), "%s", what);
  }
  out->message = text;
}

void SetOcrFailureForStage(OcrOutcome* out, OcrStage stage, int32_t hresult) {
  switch (stage) {
    case OcrStage::kOpen:
      SetOcrFailure(out, "ocr_file_unreadable", "Could not open the image file",
                    hresult);
      break;
    case OcrStage::kDecode:
      SetOcrFailure(out, "ocr_unsupported_image", "Could not decode the image",
                    hresult);
      break;
    default:
      SetOcrFailure(out, "ocr_failed", "OCR failed", hresult);
      break;
  }
}

// Pairs init_apartment with uninit_apartment on every path.
class ApartmentScope {
 public:
  ApartmentScope() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  }
  ~ApartmentScope() { winrt::uninit_apartment(); }
  ApartmentScope(const ApartmentScope&) = delete;
  ApartmentScope& operator=(const ApartmentScope&) = delete;
};

std::string LanguageTagOf(const wmo::OcrEngine& engine) {
  return WideToUtf8(std::wstring(engine.RecognizerLanguage().LanguageTag()));
}

// Engines to try, best first. Credentials are Latin text, which an English
// engine reads best even when the Windows display language is e.g. Arabic
// (then the profile-language engine is an Arabic one); the user-profile
// engine is kept as a second choice. Empty if no OCR language pack at all.
std::vector<wmo::OcrEngine> CreateOcrEngines() {
  std::vector<wmo::OcrEngine> engines;
  std::vector<std::string> tags;
  auto add = [&](const wmo::OcrEngine& engine) {
    if (!engine) return;
    std::string tag = LowerAscii(LanguageTagOf(engine));
    if (std::find(tags.begin(), tags.end(), tag) != tags.end()) return;
    tags.push_back(tag);
    engines.push_back(engine);
  };
  std::optional<wg::Language> english;
  for (const auto& language : wmo::OcrEngine::AvailableRecognizerLanguages()) {
    const std::string tag =
        LowerAscii(WideToUtf8(std::wstring(language.LanguageTag())));
    if (tag == "en-us") {
      english = language;
      break;
    }
    if (!english && (tag == "en" || tag.rfind("en-", 0) == 0))
      english = language;
  }
  if (english) add(wmo::OcrEngine::TryCreateFromLanguage(*english));
  add(wmo::OcrEngine::TryCreateFromUserProfileLanguages());
  if (engines.empty()) {
    add(wmo::OcrEngine::TryCreateFromLanguage(wg::Language(L"en-US")));
  }
  // Some other pack is installed (say de-DE) although the profile languages
  // do not include it: any Latin-script engine reads credentials fine.
  if (engines.empty()) {
    for (const auto& language :
         wmo::OcrEngine::AvailableRecognizerLanguages()) {
      add(wmo::OcrEngine::TryCreateFromLanguage(language));
      if (engines.size() >= 2) break;
    }
  }
  return engines;
}

// The decoder's frame as Bgra8 + premultiplied alpha (the format Windows
// OCR accepts), optionally resampled to [width] x [height]. Fant suits
// shrinking, Cubic keeps enlarged text edges smooth.
wgi::SoftwareBitmap DecodeBgra(const wgi::BitmapDecoder& decoder, int32_t width,
                               int32_t height, bool resample,
                               wgi::BitmapInterpolationMode mode) {
  if (!resample) {
    return decoder
        .GetSoftwareBitmapAsync(wgi::BitmapPixelFormat::Bgra8,
                                wgi::BitmapAlphaMode::Premultiplied)
        .get();
  }
  wgi::BitmapTransform transform;
  transform.ScaledWidth(static_cast<uint32_t>(width));
  transform.ScaledHeight(static_cast<uint32_t>(height));
  transform.InterpolationMode(mode);
  return decoder
      .GetSoftwareBitmapAsync(wgi::BitmapPixelFormat::Bgra8,
                              wgi::BitmapAlphaMode::Premultiplied, transform,
                              wgi::ExifOrientationMode::IgnoreExifOrientation,
                              wgi::ColorManagementMode::DoNotColorManage)
      .get();
}

// Safety net: converts if a decoder handed back another pixel format.
wgi::SoftwareBitmap EnsureBgra8(const wgi::SoftwareBitmap& bitmap) {
  if (bitmap.BitmapPixelFormat() == wgi::BitmapPixelFormat::Bgra8 &&
      bitmap.BitmapAlphaMode() == wgi::BitmapAlphaMode::Premultiplied) {
    return bitmap;
  }
  return wgi::SoftwareBitmap::Convert(bitmap, wgi::BitmapPixelFormat::Bgra8,
                                      wgi::BitmapAlphaMode::Premultiplied);
}

// Copies the pixels of a Bgra8 bitmap (rows are width * 4 bytes, no padding).
bool CopyPixels(const wgi::SoftwareBitmap& bitmap, std::vector<uint8_t>* pixels,
                int32_t* width, int32_t* height) {
  const int32_t w = bitmap.PixelWidth();
  const int32_t h = bitmap.PixelHeight();
  if (w <= 0 || h <= 0) return false;
  const uint64_t bytes =
      uint64_t{static_cast<uint32_t>(w)} * static_cast<uint32_t>(h) * 4;
  if (bytes > 0x7FFFFFFFull) return false;
  wss::Buffer buffer(static_cast<uint32_t>(bytes));
  buffer.Length(static_cast<uint32_t>(bytes));
  bitmap.CopyToBuffer(buffer);
  if (buffer.Length() < bytes) return false;
  pixels->resize(static_cast<size_t>(bytes));
  wss::DataReader reader = wss::DataReader::FromBuffer(buffer);
  reader.ReadBytes(winrt::array_view<uint8_t>(
      pixels->data(), static_cast<uint32_t>(pixels->size())));
  *width = w;
  *height = h;
  return true;
}

wgi::SoftwareBitmap MakeBitmap(const std::vector<uint8_t>& pixels,
                               int32_t width, int32_t height) {
  wss::DataWriter writer;
  writer.WriteBytes(winrt::array_view<const uint8_t>(
      pixels.data(), static_cast<uint32_t>(pixels.size())));
  wss::IBuffer buffer = writer.DetachBuffer();
  return wgi::SoftwareBitmap::CreateCopyFromBuffer(
      buffer, wgi::BitmapPixelFormat::Bgra8, width, height,
      wgi::BitmapAlphaMode::Premultiplied);
}

// Turns one engine result into an attempt. Word boxes are mapped back to the
// original image: the bitmap held [pad] pixels of border around content
// that was [scale_x] x [scale_y] times smaller (or larger) than the original.
OcrAttempt ExtractAttempt(const wmo::OcrResult& result, const std::string& name,
                          const std::string& language, double scale_x,
                          double scale_y, int32_t pad) {
  OcrAttempt attempt;
  attempt.name = name;
  attempt.language = language;
  auto to_original = [pad](float value, double scale) {
    return static_cast<int32_t>(
        std::lround((static_cast<double>(value) - pad) * scale));
  };
  for (const auto& line : result.Lines()) {
    std::string raw = WideToUtf8(std::wstring(line.Text()));
    if (IsBlank(raw)) continue;
    const int32_t index = static_cast<int32_t>(attempt.lines.size());
    attempt.lines.push_back(RepairLetterSpacing(raw));
    attempt.raw_lines.push_back(std::move(raw));
    for (const auto& word : line.Words()) {
      const auto box = word.BoundingRect();
      OcrWord out;
      out.text = WideToUtf8(std::wstring(word.Text()));
      out.x = to_original(box.X, scale_x);
      out.y = to_original(box.Y, scale_y);
      out.width = static_cast<int32_t>(std::lround(box.Width * scale_x));
      out.height = static_cast<int32_t>(std::lround(box.Height * scale_y));
      out.line = index;
      attempt.words.push_back(std::move(out));
    }
  }
  attempt.text = WideToUtf8(std::wstring(result.Text()));
  const LinesScore score = ScoreLines(attempt.lines);
  attempt.score = score.score;
  attempt.complete = score.complete;
  return attempt;
}

// Runs on a worker thread (WinRT .get() is not allowed on the STA platform
// thread). Never throws: every failure becomes an error code.
//
// The image is decoded as Bgra8 and, if it is larger than
// OcrEngine::MaxImageDimension() (about 2600 px; Windows OCR silently
// returns nothing beyond it), shrunk to fit. Then a few attempts are made
// (see PlanOcrAttempts) and the best-scoring one wins; the first attempt is
// the plain image, so this is never worse than a single pass would be, and
// the loop stops as soon as an attempt holds an email and a second line.
//
// OcrResult.Text is returned separately ("text") rather than appended to the
// lines: it is the same words as Lines() and would only duplicate them.
OcrOutcome RunOcr(const std::wstring& path, bool preprocess) {
  OcrOutcome out;
  OcrStage stage = OcrStage::kInit;
  try {
    ApartmentScope apartment;
    stage = OcrStage::kOpen;
    auto file = wst::StorageFile::GetFileFromPathAsync(path).get();
    auto stream = file.OpenAsync(wst::FileAccessMode::Read).get();
    stage = OcrStage::kDecode;
    auto decoder = wgi::BitmapDecoder::CreateAsync(stream).get();
    const uint32_t source_w = decoder.PixelWidth();
    const uint32_t source_h = decoder.PixelHeight();
    if (source_w == 0 || source_h == 0) {
      SetOcrFailure(&out, "ocr_unsupported_image", "The image has no pixels",
                    0);
      return out;
    }
    if (uint64_t{source_w} * source_h > kMaxSourcePixels) {
      SetOcrFailure(&out, "ocr_image_too_large", "The image is too large", 0);
      return out;
    }
    stage = OcrStage::kRecognize;
    std::vector<wmo::OcrEngine> engines = CreateOcrEngines();
    if (engines.empty()) {
      SetOcrFailure(&out, "ocr_no_language",
                    "No OCR language pack is installed", 0);
      return out;
    }
    const int32_t max_dim =
        static_cast<int32_t>(wmo::OcrEngine::MaxImageDimension());
    const int32_t width = static_cast<int32_t>(source_w);
    const int32_t height = static_cast<int32_t>(source_h);

    int32_t fit_w = 0;
    int32_t fit_h = 0;
    FitDimensions(width, height, max_dim, &fit_w, &fit_h);
    stage = OcrStage::kDecode;
    wgi::SoftwareBitmap base = EnsureBgra8(
        DecodeBgra(decoder, fit_w, fit_h, fit_w != width || fit_h != height,
                   wgi::BitmapInterpolationMode::Fant));
    std::vector<uint8_t> base_pixels;
    ScopedWipe wipe_base(&base_pixels);
    int32_t base_w = base.PixelWidth();
    int32_t base_h = base.PixelHeight();
    // Reading the pixels is only needed for the extra attempts. If it fails,
    // the plain image is still recognized, as it was before preprocessing
    // existed, instead of failing the whole call.
    bool have_pixels = false;
    try {
      have_pixels = CopyPixels(base, &base_pixels, &base_w, &base_h);
    } catch (...) {
      have_pixels = false;
    }
    if (!have_pixels) {
      base_pixels.clear();
      base_w = base.PixelWidth();
      base_h = base.PixelHeight();
    }
    if (base_w <= 0 || base_h <= 0) {
      SetOcrFailure(&out, "ocr_unsupported_image", "The image has no pixels",
                    0);
      return out;
    }
    stage = OcrStage::kRecognize;
    const std::vector<OcrPlan> plans = PlanOcrAttempts(
        base_w, base_h, have_pixels ? MedianLuma(base_pixels) : 128, max_dim,
        preprocess && have_pixels);

    // The bitmap for one plan plus the size it was made at.
    struct Built {
      wgi::SoftwareBitmap bitmap{nullptr};
      int32_t width = 0;
      int32_t height = 0;
      int32_t pad = 0;
    };
    auto build = [&](const OcrPlan& plan) -> Built {
      Built built;
      std::vector<uint8_t> pixels;
      ScopedWipe wipe(&pixels);
      int32_t w = base_w;
      int32_t h = base_h;
      if (plan.scale == 1) {
        if (!plan.gray && !HasTranslucentPixels(base_pixels)) {
          built.bitmap = base;  // exactly as decoded
          built.width = w;
          built.height = h;
          return built;
        }
        pixels = base_pixels;
      } else {
        wgi::SoftwareBitmap scaled = EnsureBgra8(
            DecodeBgra(decoder, base_w * plan.scale, base_h * plan.scale, true,
                       wgi::BitmapInterpolationMode::Cubic));
        if (!CopyPixels(scaled, &pixels, &w, &h)) return built;
        if (!plan.gray && !HasTranslucentPixels(pixels)) {
          built.bitmap = scaled;
          built.width = w;
          built.height = h;
          return built;
        }
      }
      FlattenAlpha(&pixels);
      if (plan.gray) {
        PrepareGray(&pixels, plan.invert);
        built.pad = PadAmount(w, h, max_dim);
        PadGray(&pixels, &w, &h, built.pad,
                static_cast<uint8_t>(MedianLuma(pixels)));
      }
      built.bitmap = MakeBitmap(pixels, w, h);
      built.width = w;
      built.height = h;
      return built;
    };

    int32_t last_failure = 0;  // HRESULT of the last engine failure, or 0
    bool recognized = false;
    bool done = false;
    int32_t best_score = 0;
    for (size_t p = 0; p < plans.size() && !done; ++p) {
      Built built;
      try {
        built = build(plans[p]);
      } catch (...) {
        if (p == 0) throw;  // the plain image must at least decode
        continue;
      }
      if (!built.bitmap) continue;
      const int32_t content_w = built.width - 2 * built.pad;
      const int32_t content_h = built.height - 2 * built.pad;
      if (content_w <= 0 || content_h <= 0) continue;
      const double scale_x = static_cast<double>(width) / content_w;
      const double scale_y = static_cast<double>(height) / content_h;
      for (const wmo::OcrEngine& engine : engines) {
        try {
          wmo::OcrResult result = engine.RecognizeAsync(built.bitmap).get();
          OcrAttempt attempt =
              ExtractAttempt(result, plans[p].name, LanguageTagOf(engine),
                             scale_x, scale_y, built.pad);
          const bool complete = attempt.complete;
          if (out.attempts.empty() || attempt.score > best_score) {
            best_score = attempt.score;
            out.best = out.attempts.size();
          }
          out.attempts.push_back(std::move(attempt));
          recognized = true;  // only once the attempt is stored
          if (complete) {
            done = true;
            break;
          }
        } catch (const winrt::hresult_error& error) {
          last_failure = static_cast<int32_t>(error.code());
        } catch (...) {
          // Not a WinRT error (say, out of memory): no HRESULT to report.
          last_failure = 0;
        }
      }
    }
    if (!recognized) {
      SetOcrFailure(&out, "ocr_failed", "OCR failed", last_failure);
      return out;
    }
    out.ok = true;
    out.width = width;
    out.height = height;
    out.lines = MergeAttemptLines(out.attempts, out.best);
  } catch (const winrt::hresult_error& error) {
    SetOcrFailureForStage(&out, stage, static_cast<int32_t>(error.code()));
  } catch (...) {
    SetOcrFailureForStage(&out, stage, 0);
  }
  return out;
}

// ===========================================================================
// WINRT-END
// ===========================================================================

EncodableList LinesToList(const std::vector<std::string>& lines) {
  EncodableList list;
  for (const std::string& line : lines) list.emplace_back(line);
  return list;
}

EncodableMap WordToMap(const OcrWord& word) {
  EncodableMap map;
  map.emplace(EncodableValue("text"), EncodableValue(word.text));
  map.emplace(EncodableValue("x"), EncodableValue(word.x));
  map.emplace(EncodableValue("y"), EncodableValue(word.y));
  map.emplace(EncodableValue("width"), EncodableValue(word.width));
  map.emplace(EncodableValue("height"), EncodableValue(word.height));
  map.emplace(EncodableValue("line"), EncodableValue(word.line));
  return map;
}

// The Dart-facing result of "ocr": the best attempt's lines, or with
// [detailed] a map with everything (see the channel description at the top).
EncodableValue OcrResponse(const OcrOutcome& outcome, bool detailed) {
  const OcrAttempt& best = outcome.attempts[outcome.best];
  if (!detailed) return EncodableValue(LinesToList(outcome.lines));
  EncodableMap map;
  map.emplace(EncodableValue("lines"),
              EncodableValue(LinesToList(outcome.lines)));
  map.emplace(EncodableValue("rawLines"),
              EncodableValue(LinesToList(best.raw_lines)));
  map.emplace(EncodableValue("text"), EncodableValue(best.text));
  EncodableList words;
  for (const OcrWord& word : best.words) words.emplace_back(WordToMap(word));
  map.emplace(EncodableValue("words"), EncodableValue(words));
  map.emplace(EncodableValue("language"), EncodableValue(best.language));
  map.emplace(EncodableValue("attempt"), EncodableValue(best.name));
  map.emplace(EncodableValue("score"), EncodableValue(best.score));
  map.emplace(EncodableValue("width"), EncodableValue(outcome.width));
  map.emplace(EncodableValue("height"), EncodableValue(outcome.height));
  EncodableList attempts;
  for (const OcrAttempt& attempt : outcome.attempts) {
    EncodableMap entry;
    entry.emplace(EncodableValue("attempt"), EncodableValue(attempt.name));
    entry.emplace(EncodableValue("language"), EncodableValue(attempt.language));
    entry.emplace(EncodableValue("score"), EncodableValue(attempt.score));
    entry.emplace(EncodableValue("lines"),
                  EncodableValue(LinesToList(attempt.lines)));
    attempts.emplace_back(std::move(entry));
  }
  map.emplace(EncodableValue("attempts"), EncodableValue(attempts));
  return EncodableValue(map);
}

}  // namespace

void RunPlatformThreadTask(LPARAM lparam) {
  std::unique_ptr<std::function<void()>> task(
      reinterpret_cast<std::function<void()>*>(lparam));
  (*task)();
}

void RegisterHisnChannel(flutter::FlutterEngine* engine, HWND window) {
  // Exclude the window from screenshots, screen recording and screen
  // sharing (Windows 10 2004+). Shows as black in captures.
  SetWindowDisplayAffinity(window, WDA_EXCLUDEFROMCAPTURE);
  DeleteStaleClipFiles();

  static auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), "app.vaultsnap/platform",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [window](const flutter::MethodCall<EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const auto* args = std::get_if<EncodableMap>(call.arguments());
        auto str_arg = [&](const char* key) -> std::string {
          if (!args) return "";
          auto it = args->find(EncodableValue(key));
          if (it == args->end()) return "";
          const auto* s = std::get_if<std::string>(&it->second);
          return s ? *s : "";
        };
        auto bool_arg = [&](const char* key, bool fallback) -> bool {
          if (!args) return fallback;
          auto it = args->find(EncodableValue(key));
          if (it == args->end()) return fallback;
          const auto* b = std::get_if<bool>(&it->second);
          return b ? *b : fallback;
        };
        const std::string& m = call.method_name();
        if (m == "copySensitive") {
          result->Success(
              EncodableValue(CopySensitive(window, str_arg("text"))));
        } else if (m == "clearClipboardIfMatches") {
          ClearIfUnchanged(window);
          result->Success(EncodableValue(true));
        } else if (m == "readClipboard") {
          std::optional<EncodableMap> content = ReadClipboard(window);
          if (content) {
            result->Success(EncodableValue(*content));
          } else {
            result->Error("clipboard_busy", "Could not open the clipboard");
          }
        } else if (m == "clearClipboard") {
          result->Success(EncodableValue(ClearClipboard(window)));
        } else if (m == "setSecureScreen") {
          bool on = true;
          if (args) {
            auto it = args->find(EncodableValue("enabled"));
            if (it != args->end()) on = std::get<bool>(it->second);
          }
          SetWindowDisplayAffinity(window,
                                   on ? WDA_EXCLUDEFROMCAPTURE : WDA_NONE);
          result->Success();
        } else if (m == "deleteImage") {
          std::wstring p = Utf8ToWide(str_arg("uri"));
          result->Success(EncodableValue(DeleteFileW(p.c_str()) != 0));
        } else if (m == "ocr") {
          std::wstring path = Utf8ToWide(str_arg("path"));
          if (path.empty()) {
            result->Error("ocr_bad_arguments", "Missing image path");
            return;
          }
          const bool detailed = bool_arg("detailed", false);
          const bool preprocess = bool_arg("preprocess", true);
          std::shared_ptr<flutter::MethodResult<EncodableValue>> shared =
              std::move(result);
          // WinRT .get() is not allowed on the (STA) platform thread, and
          // MethodResult must be completed on it: run OCR on a worker and
          // post the completion back through the window's message loop.
          std::thread([window, path, detailed, preprocess,
                       shared = std::move(shared)]() mutable {
            auto outcome =
                std::make_shared<OcrOutcome>(RunOcr(path, preprocess));
            auto* task = new std::function<void()>(
                [shared = std::move(shared), outcome, detailed]() {
                  if (outcome->ok) {
                    shared->Success(OcrResponse(*outcome, detailed));
                  } else {
                    shared->Error(outcome->code, outcome->message);
                  }
                });
            if (!PostMessage(window, kHisnRunOnPlatformThread, 0,
                             reinterpret_cast<LPARAM>(task))) {
              delete task;
            }
          }).detach();
        } else {
          result->NotImplemented();
        }
      });
}
