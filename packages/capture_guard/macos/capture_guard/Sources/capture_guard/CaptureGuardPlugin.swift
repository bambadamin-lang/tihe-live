import Cocoa
import CoreGraphics
import FlutterMacOS

/// macOS half of capture_guard. Blocks with `NSWindow.sharingType = .none` — honoured by the
/// capture APIs up to macOS 14; **ScreenCaptureKit on macOS 15+ ignores it** (ADR-0011), so
/// there the running-app scan and the Dart policy are what censor the class.
public class CaptureGuardPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var blocking = false
  private var observers: [NSObjectProtocol] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = CaptureGuardPlugin()
    let channel = FlutterMethodChannel(
      name: "tihe/capture_guard", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: channel)
    FlutterEventChannel(name: "tihe/capture_guard/events", binaryMessenger: registrar.messenger)
      .setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "enableBlocking":
      blocking = true
      applySharing()
      // Windows opened later (a dialog, a second window) get the same treatment.
      if observers.isEmpty {
        observers.append(
          NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
          ) { [weak self] _ in self?.applySharing() })
      }
      result(["active": true, "mechanism": "sharing_none", "failed": false])
    case "disableBlocking":
      blocking = false
      applySharing()
      result(nil)
    case "readFacts":
      result(facts())
    case "runningProcesses":
      result(runningProcesses())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func applySharing() {
    for window in NSApplication.shared.windows {
      window.sharingType = blocking ? .none : .readOnly
    }
  }

  /// A display in a mirror set (AirPlay mirroring, a projector cloning the screen) sends the
  /// class somewhere a camera or capture box can record it.
  private func mirrored() -> Bool {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
    return displays.contains { CGDisplayIsInMirrorSet($0) != 0 }
  }

  private func facts() -> [String: Any] {
    // macOS offers no public "you are being recorded" signal; the process scan stands in.
    return ["osRecording": false, "externalDisplay": mirrored(), "remoteSession": false]
  }

  /// Names of running apps, as both their display name and executable, lower-cased — the
  /// recorder list in the capture policy may name either.
  private func runningProcesses() -> [String] {
    var names = Set<String>()
    for app in NSWorkspace.shared.runningApplications {
      if let name = app.localizedName { names.insert(name.lowercased()) }
      if let exe = app.executableURL?.lastPathComponent { names.insert(exe.lowercased()) }
    }
    return Array(names)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self = self else { return }
        self.sink?(self.facts())
      })
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  deinit {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
  }
}
