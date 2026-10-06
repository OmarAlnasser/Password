#ifndef RUNNER_PLATFORM_CHANNEL_H_
#define RUNNER_PLATFORM_CHANNEL_H_

#include <flutter/flutter_engine.h>
#include <windows.h>

// Registers the "app.vaultsnap/platform" method channel (clipboard text and
// images, screen-capture exclusion, on-device OCR via Windows.Media.Ocr). The
// methods, their results and error codes are described at the top of
// platform_channel.cpp.
void RegisterVaultSnapChannel(flutter::FlutterEngine* engine, HWND window);

// Window message used to run a completion on the platform thread.
constexpr UINT kVaultSnapRunOnPlatformThread = WM_APP + 0x51;

// Called from FlutterWindow::MessageHandler for the message above.
void RunPlatformThreadTask(LPARAM lparam);

#endif  // RUNNER_PLATFORM_CHANNEL_H_
