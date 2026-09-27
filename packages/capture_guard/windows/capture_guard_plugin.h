#ifndef FLUTTER_PLUGIN_CAPTURE_GUARD_PLUGIN_H_
#define FLUTTER_PLUGIN_CAPTURE_GUARD_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace capture_guard {

// Blocks screen capture of the app window with SetWindowDisplayAffinity and reports the facts
// the Dart policy needs: Remote Desktop, and the names of running processes. Decisions are made
// in Dart (lib/src/policy.dart), not here.
class CaptureGuardPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit CaptureGuardPlugin(flutter::PluginRegistrarWindows* registrar);
  virtual ~CaptureGuardPlugin();

  CaptureGuardPlugin(const CaptureGuardPlugin&) = delete;
  CaptureGuardPlugin& operator=(const CaptureGuardPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // The top-level window: display affinity applies to top-level windows only.
  HWND RootWindow() const;

  flutter::PluginRegistrarWindows* registrar_;
};

}  // namespace capture_guard

#endif  // FLUTTER_PLUGIN_CAPTURE_GUARD_PLUGIN_H_
