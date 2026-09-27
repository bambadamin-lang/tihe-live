#include "include/capture_guard/capture_guard_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "capture_guard_plugin.h"

void CaptureGuardPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  capture_guard::CaptureGuardPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
