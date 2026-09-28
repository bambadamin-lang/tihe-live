import Flutter
import UIKit

/// iOS half of capture_guard. iOS cannot block recording, so this:
///  - renders the app inside a secure text-field layer, which screenshots and recordings show
///    blank (the "secure layer" trick; behind a server flag because it relies on UIKit
///    internals — ADR-0011), and
///  - reports capture state, mirroring and screenshots, so the Dart policy censors the class
///    and tells the host.
public class CaptureGuardPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var observers: [NSObjectProtocol] = []
  private var secured = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = CaptureGuardPlugin()
    let channel = FlutterMethodChannel(
      name: "tihe/capture_guard", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    FlutterEventChannel(name: "tihe/capture_guard/events", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "enableBlocking":
      let args = call.arguments as? [String: Any]
      let wantSecureLayer = (args?["iosSecureLayer"] as? Bool) ?? false
      if wantSecureLayer && !secured, let window = keyWindow() {
        window.tiheMakeSecure()
        secured = true
      }
      result([
        "active": secured,
        "mechanism": secured ? "secure_layer" : "none",
        "failed": wantSecureLayer && !secured,
      ])
    case "disableBlocking":
      // The secure layer cannot be taken apart safely while the app runs; it stays until the
      // next launch, which only means screenshots elsewhere in the app are blank too.
      result(nil)
    case "readFacts":
      result(facts())
    case "runningProcesses":
      result([String]())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }

  private func isCaptured() -> Bool {
    guard let window = keyWindow() else { return false }
    if #available(iOS 17.0, *) {
      return window.traitCollection.sceneCaptureState == .active
    }
    return window.windowScene?.screen.isCaptured ?? false
  }

  private func facts() -> [String: Any] {
    [
      // Screen recording, AirPlay mirroring and our own broadcast extension all show as
      // captured; Dart tells them apart using the screen count and its own share state.
      "osRecording": isCaptured(),
      // AirPlay mirroring and cabled displays both add a screen, scene or not.
      "externalDisplay": UIScreen.screens.count > 1,
      "remoteSession": false,
    ]
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    let center = NotificationCenter.default
    let push: (Notification) -> Void = { [weak self] _ in
      guard let self = self else { return }
      self.sink?(self.facts())
    }
    for name in [
      UIScreen.capturedDidChangeNotification,
      UIScreen.didConnectNotification,
      UIScreen.didDisconnectNotification,
    ] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main, using: push))
    }
    observers.append(
      center.addObserver(
        forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main
      ) { [weak self] _ in self?.sink?(["event": "screenshot"]) })
    push(Notification(name: UIScreen.capturedDidChangeNotification))
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
    sink = nil
    return nil
  }
}

extension UIWindow {
  /// Re-parents the window's layer into the canvas of a secure text field. UIKit blanks that
  /// canvas in screenshots, recordings and mirroring, so everything drawn in the window is
  /// hidden from capture while still shown on the device itself.
  fileprivate func tiheMakeSecure() {
    let field = UITextField()
    field.isSecureTextEntry = true
    field.isUserInteractionEnabled = false
    addSubview(field)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    field.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
    layer.superlayer?.addSublayer(field.layer)
    // The secure canvas is the first sublayer before iOS 17 and the last one since.
    if #available(iOS 17.0, *) {
      field.layer.sublayers?.last?.addSublayer(layer)
    } else {
      field.layer.sublayers?.first?.addSublayer(layer)
    }
  }
}
