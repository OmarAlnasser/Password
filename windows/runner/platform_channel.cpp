#include "platform_channel.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

#include <functional>
#include <memory>
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
