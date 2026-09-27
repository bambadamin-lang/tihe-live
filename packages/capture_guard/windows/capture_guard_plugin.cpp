#include "capture_guard_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <tlhelp32.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cctype>
#include <memory>
#include <string>

namespace capture_guard {

namespace {

// Windows 10 2004+. Older SDK headers do not define it.
constexpr DWORD kWdaExcludeFromCapture = 0x00000011;

std::string Utf8(const wchar_t* wide) {
  const int size =
      WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) return std::string();
  std::string out(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), size, nullptr, nullptr);
  return out;
}

std::string Lower(std::string text) {
  std::transform(text.begin(), text.end(), text.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return text;
}

std::string StringArg(const flutter::EncodableValue* args, const char* key,
                      const std::string& fallback) {
  const auto* map = std::get_if<flutter::EncodableMap>(args);
  if (!map) return fallback;
  auto it = map->find(flutter::EncodableValue(key));
  if (it == map->end()) return fallback;
  const auto* value = std::get_if<std::string>(&it->second);
  return value ? *value : fallback;
}

flutter::EncodableList RunningProcesses() {
  flutter::EncodableList names;
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return names;
  PROCESSENTRY32W entry;
  entry.dwSize = sizeof(entry);
  if (Process32FirstW(snapshot, &entry)) {
    do {
      names.push_back(flutter::EncodableValue(Lower(Utf8(entry.szExeFile))));
    } while (Process32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);
  return names;
}

}  // namespace

// static
void CaptureGuardPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "tihe/capture_guard",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<CaptureGuardPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

CaptureGuardPlugin::CaptureGuardPlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

CaptureGuardPlugin::~CaptureGuardPlugin() {}

HWND CaptureGuardPlugin::RootWindow() const {
  flutter::FlutterView* view = registrar_->GetView();
  if (!view) return nullptr;
  return GetAncestor(view->GetNativeWindow(), GA_ROOT);
}

void CaptureGuardPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "enableBlocking") {
    HWND root = RootWindow();
    const bool exclude =
        StringArg(method_call.arguments(), "windowsAffinity", "monitor") == "exclude";
    // Students get WDA_MONITOR: a capture shows a black box, which reads as "censored".
    // Presenters get WDA_EXCLUDEFROMCAPTURE: the window vanishes from their own screen share
    // instead of leaving a black hole in it. If exclusion is unavailable (before Windows 10
    // 2004), fall back to MONITOR. See ADR-0011.
    BOOL ok = root && SetWindowDisplayAffinity(
                          root, exclude ? kWdaExcludeFromCapture : WDA_MONITOR);
    std::string mechanism = exclude ? "wda_exclude" : "wda_monitor";
    if (!ok && exclude && root) {
      ok = SetWindowDisplayAffinity(root, WDA_MONITOR);
      mechanism = "wda_monitor";
    }
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("active"), flutter::EncodableValue(ok == TRUE)},
        {flutter::EncodableValue("mechanism"),
         flutter::EncodableValue(ok ? mechanism : std::string("none"))},
        {flutter::EncodableValue("failed"), flutter::EncodableValue(ok != TRUE)},
    }));
  } else if (method == "disableBlocking") {
    HWND root = RootWindow();
    if (root) SetWindowDisplayAffinity(root, WDA_NONE);
    result->Success();
  } else if (method == "readFacts") {
    // No OS signal for "being recorded" exists on Windows; the process scan covers it.
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("osRecording"), flutter::EncodableValue(false)},
        {flutter::EncodableValue("externalDisplay"), flutter::EncodableValue(false)},
        {flutter::EncodableValue("remoteSession"),
         flutter::EncodableValue(GetSystemMetrics(SM_REMOTESESSION) != 0)},
    }));
  } else if (method == "runningProcesses") {
    result->Success(flutter::EncodableValue(RunningProcesses()));
  } else {
    result->NotImplemented();
  }
}

}  // namespace capture_guard
