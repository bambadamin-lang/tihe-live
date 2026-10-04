import 'dart:developer' as developer;

/// Logging that cannot leak identity.
///
/// `print()` is banned by the analyzer (see analysis_options.yaml) and everything goes through here,
/// because the single most likely way a phone number or token ends up somewhere it should not is a
/// debug line that outlived its debugging session.
///
/// [maskPhone] mirrors the server's masking exactly, so a log line here and one in the API describe
/// the same student the same way.
class AppLog {
  const AppLog._();

  static void info(String message, {String? name}) => developer.log(message, name: name ?? 'tihe');

  static void warn(String message, {String? name}) =>
      developer.log('WARN $message', name: name ?? 'tihe');

  static void error(String message, {Object? error, StackTrace? stackTrace, String? name}) =>
      developer.log('ERROR $message', name: name ?? 'tihe', error: error, stackTrace: stackTrace);

  /// `+989123456789` and `09123456789` both become `0912•••6789`.
  static String maskPhone(String phone) {
    final local = phone.startsWith('+98') ? '0${phone.substring(3)}' : phone;
    if (local.length < 11) return '•' * local.length;
    return '${local.substring(0, 4)}•••${local.substring(local.length - 4)}';
  }

  /// Truncates anything token-shaped. Use when a correlation id is wanted in a log line but the
  /// value itself is a secret.
  static String maskToken(String token) =>
      token.length <= 8 ? '•' * token.length : '${token.substring(0, 4)}…${'•' * 6}';
}
