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

#include <cstdint>
#include <cstring>
#include <cwchar>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return L"";
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
  return w;
}

std::string WideToUtf8(const std::wstring& w) {
  if (w.empty()) return "";
  int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0,
                              nullptr, nullptr);
  std::string s(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), s.data(), n,
                      nullptr, nullptr);
  return s;
}

void SecureZero(std::wstring& w) {
  SecureZeroMemory(w.data(), w.size() * sizeof(wchar_t));
}

DWORD g_last_sequence = 0;

void SetDwordFormat(const wchar_t* name, DWORD value) {
  UINT fmt = RegisterClipboardFormatW(name);
  HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
  if (!h) return;
  *static_cast<DWORD*>(GlobalLock(h)) = value;
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
    memcpy(GlobalLock(h), w.c_str(), bytes);
    GlobalUnlock(h);
    if (!SetClipboardData(CF_UNICODETEXT, h)) GlobalFree(h);
  }
  // Documented formats: presence of the first excludes from monitors; the
  // DWORD 0 values opt out of history and cloud upload.
  UINT exclude = RegisterClipboardFormatW(
      L"ExcludeClipboardContentFromMonitorProcessing");
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
    for (int attempt = 0; attempt < 5 && !open_; ++attempt) {
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

// Pasted images are written to %TEMP% as "<prefix><guid>.png|.bmp".
constexpr wchar_t kClipFilePrefix[] = L"vaultsnap-clip-";

// The user's %TEMP% with a trailing backslash, or "" if unavailable.
std::wstring TempDir() {
  wchar_t dir[MAX_PATH + 1] = {};
  DWORD n = GetTempPathW(MAX_PATH + 1, dir);
  if (n == 0 || n > MAX_PATH) return L"";
  return std::wstring(dir, n);
}

// Creates a new file with an unguessable name in %TEMP% holding [prefix]
// followed by [data]. Returns its path, or "" on failure (nothing is left
// behind). Dart deletes it once OCR is done.
std::wstring WriteTempFile(const wchar_t* extension, const void* prefix,
                           SIZE_T prefix_size, const void* data, SIZE_T size) {
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
  auto write_all = [file](const void* bytes, SIZE_T len) {
    constexpr DWORD kMaxChunk = 1u << 30;
    const BYTE* p = static_cast<const BYTE*>(bytes);
    while (len > 0) {
      DWORD chunk = len > kMaxChunk ? kMaxChunk : static_cast<DWORD>(len);
      DWORD written = 0;
      if (!WriteFile(file, p, chunk, &written, nullptr) || written == 0) {
        return false;
      }
      p += written;
      len -= written;
    }
    return true;
  };
  bool ok = write_all(prefix, prefix_size) && write_all(data, size);
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

// BI_ALPHABITFIELDS (RGBA masks after a BITMAPINFOHEADER); missing from
// some SDK versions of wingdi.h.
constexpr DWORD kBiAlphaBitfields = 6;

// Offset of the pixels in a packed DIB (CF_DIB / CF_DIBV5): the header, then
// the bit masks unless the header already holds them, then the color table.
// 0 for malformed DIBs and for embedded JPEG/PNG, which .bmp readers reject.
SIZE_T DibBitsOffset(const BYTE* dib, SIZE_T size) {
  DWORD header_size = 0;
  if (!dib || size < sizeof(header_size)) return 0;
  memcpy(&header_size, dib, sizeof(header_size));
  uint64_t offset = 0;
  if (header_size == sizeof(BITMAPCOREHEADER)) {
    if (size < sizeof(BITMAPCOREHEADER)) return 0;
    BITMAPCOREHEADER core;
    memcpy(&core, dib, sizeof(core));
    uint64_t colors = 0;
    if (core.bcBitCount >= 1 && core.bcBitCount <= 8) {
      colors = uint64_t{1} << core.bcBitCount;
    }
    offset = header_size + colors * sizeof(RGBTRIPLE);
  } else {
    // BITMAPINFOHEADER (40 bytes) or a V2-V5 header (52/56/108/124), which
    // all start with the same fields and hold the masks themselves.
    if (header_size < sizeof(BITMAPINFOHEADER) || header_size > size) return 0;
    BITMAPINFOHEADER info;
    memcpy(&info, dib, sizeof(info));
    const bool v1 = header_size == sizeof(BITMAPINFOHEADER);
    uint64_t masks = 0;
    switch (info.biCompression) {
      case BI_RGB:
      case BI_RLE8:
      case BI_RLE4:
        break;
      case BI_BITFIELDS:
        if (v1) masks = 3 * sizeof(DWORD);
        break;
      case kBiAlphaBitfields:
        if (v1) masks = 4 * sizeof(DWORD);
        break;
      default:
        return 0;
    }
    uint64_t colors = info.biClrUsed;
    if (colors == 0 && info.biBitCount >= 1 && info.biBitCount <= 8) {
      colors = uint64_t{1} << info.biBitCount;
    }
    offset = header_size + masks + colors * sizeof(RGBQUAD);
  }
  if (offset >= size) return 0;  // no room left for pixels
  return static_cast<SIZE_T>(offset);
}

// Prepends a BITMAPFILEHEADER so the packed DIB is a valid .bmp file.
std::wstring WriteDibAsBmp(const BYTE* dib, SIZE_T size) {
  SIZE_T bits = DibBitsOffset(dib, size);
  if (bits == 0 || size > MAXDWORD - sizeof(BITMAPFILEHEADER)) return L"";
  BITMAPFILEHEADER header = {};
  header.bfType = 0x4D42;  // "BM"
  header.bfSize = static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + size);
  header.bfOffBits = static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + bits);
  return WriteTempFile(L".bmp", &header, sizeof(header), dib, size);
}

// For the "Paste" button. An image (the registered "PNG" format that the
// Snipping Tool and browsers write, else a DIB saved as .bmp) goes to a temp
// file and {"imagePath"} is returned; otherwise {"text"}. nullopt if the
// clipboard could not be opened.
std::optional<EncodableMap> ReadClipboard(HWND hwnd) {
  ClipboardLock lock(hwnd);
  if (!lock.is_open()) return std::nullopt;
  std::wstring image;
  UINT png = RegisterClipboardFormatW(L"PNG");
  if (png != 0 && IsClipboardFormatAvailable(png)) {
    LockedGlobal data(GetClipboardData(png));
    if (data.size() > 0) {
      image = WriteTempFile(L".png", nullptr, 0, data.data(), data.size());
    }
  }
  // CF_DIB first: its 32bpp pixels decode as opaque, while a CF_DIBV5 alpha
  // mask may cover an all-zero alpha channel (GDI screenshots) and decode as
  // a fully transparent image. OCR doesn't need alpha.
  const UINT dib_formats[] = {CF_DIB, CF_DIBV5};
  for (UINT format : dib_formats) {
    if (!image.empty() || !IsClipboardFormatAvailable(format)) continue;
    LockedGlobal data(GetClipboardData(format));
    image = WriteDibAsBmp(data.data(), data.size());
  }
  EncodableMap out;
  if (!image.empty()) {
    out.emplace(EncodableValue("imagePath"), EncodableValue(WideToUtf8(image)));
  } else if (IsClipboardFormatAvailable(CF_UNICODETEXT)) {
    LockedGlobal data(GetClipboardData(CF_UNICODETEXT));
    if (data.data()) {
      const auto* chars = reinterpret_cast<const wchar_t*>(data.data());
      std::wstring text(chars, wcsnlen(chars, data.size() / sizeof(wchar_t)));
      out.emplace(EncodableValue("text"), EncodableValue(WideToUtf8(text)));
      SecureZero(text);
    }
  }
  return out;
}

std::vector<std::string> RunOcr(const std::wstring& path) {
  using namespace winrt;
  using namespace winrt::Windows::Graphics::Imaging;
  using namespace winrt::Windows::Media::Ocr;
  using namespace winrt::Windows::Storage;
  init_apartment(apartment_type::multi_threaded);
  std::vector<std::string> lines;
  auto file = StorageFile::GetFileFromPathAsync(path).get();
  auto stream = file.OpenAsync(FileAccessMode::Read).get();
  auto decoder = BitmapDecoder::CreateAsync(stream).get();
  auto bitmap = decoder.GetSoftwareBitmapAsync().get();
  // Uses the user's installed OCR languages; fully on-device.
  OcrEngine engine = OcrEngine::TryCreateFromUserProfileLanguages();
  if (!engine) return lines;
  if (bitmap.PixelWidth() > (int)OcrEngine::MaxImageDimension() ||
      bitmap.PixelHeight() > (int)OcrEngine::MaxImageDimension()) {
    return lines;
  }
  auto result = engine.RecognizeAsync(bitmap).get();
  for (auto const& line : result.Lines()) {
    lines.push_back(WideToUtf8(std::wstring(line.Text())));
  }
  return lines;
}

}  // namespace

void RunPlatformThreadTask(LPARAM lparam) {
  std::unique_ptr<std::function<void()>> task(
      reinterpret_cast<std::function<void()>*>(lparam));
  (*task)();
}

void RegisterVaultSnapChannel(flutter::FlutterEngine* engine, HWND window) {
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
        const std::string& m = call.method_name();
        if (m == "copySensitive") {
          result->Success(EncodableValue(CopySensitive(window, str_arg("text"))));
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
          SetWindowDisplayAffinity(window, on ? WDA_EXCLUDEFROMCAPTURE : WDA_NONE);
          result->Success();
        } else if (m == "deleteImage") {
          std::wstring p = Utf8ToWide(str_arg("uri"));
          result->Success(EncodableValue(DeleteFileW(p.c_str()) != 0));
        } else if (m == "ocr") {
          std::wstring path = Utf8ToWide(str_arg("path"));
          std::shared_ptr<flutter::MethodResult<EncodableValue>> shared =
              std::move(result);
          // WinRT .get() is not allowed on the (STA) platform thread, and
          // MethodResult must be completed on it: run OCR on a worker and
          // post the completion back through the window's message loop.
          std::thread([window, path, shared]() {
            auto out = std::make_shared<EncodableList>();
            bool ok = true;
            try {
              for (auto& l : RunOcr(path)) out->emplace_back(l);
            } catch (...) {
              ok = false;
            }
            auto* task = new std::function<void()>([shared, out, ok]() {
              if (ok) {
                shared->Success(EncodableValue(*out));
              } else {
                shared->Error("ocr_failed", "OCR failed");
              }
            });
            if (!PostMessage(window, kVaultSnapRunOnPlatformThread, 0,
                             reinterpret_cast<LPARAM>(task))) {
              delete task;
            }
          }).detach();
        } else {
          result->NotImplemented();
        }
      });
}
