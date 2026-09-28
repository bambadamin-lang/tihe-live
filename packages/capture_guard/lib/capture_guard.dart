/// Blocks and detects screen capture on Windows, macOS, Android and iOS, for the TIHE Live
/// classroom and player. See docs/adr/0011-live-capture-guard-censor-and-attribute.md.
///
/// Native code only reports facts; [CapturePolicyEngine] decides, so the rules are testable
/// anywhere. [CaptureMonitor] ties the two together.
library;

export 'src/facts.dart';
export 'src/monitor.dart';
export 'src/platform.dart';
export 'src/policy.dart';
