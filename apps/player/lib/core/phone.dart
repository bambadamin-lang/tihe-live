/// Iranian mobile numbers as students type them: Persian or Arabic-Indic digits, with spaces or
/// dashes, starting 09, 9, +98 or 0098. Mirrors `phoneSchema` in packages/contracts, so the app can
/// say "not a valid number" before a round trip; the server still decides.
abstract final class Phone {
  /// E.164 (`+989…`), or null if the input cannot be an Iranian mobile number.
  static String? normalize(String input) {
    final digits = foldDigits(input).replaceAll(RegExp(r'[^\d+]'), '');
    final String e164;
    if (digits.startsWith('+98')) {
      e164 = digits;
    } else if (digits.startsWith('0098')) {
      e164 = '+${digits.substring(2)}';
    } else if (digits.startsWith('98') && digits.length == 12) {
      e164 = '+$digits';
    } else if (digits.startsWith('09')) {
      e164 = '+98${digits.substring(1)}';
    } else if (digits.startsWith('9') && digits.length == 10) {
      e164 = '+98$digits';
    } else {
      return null;
    }
    return RegExp(r'^\+989\d{9}$').hasMatch(e164) ? e164 : null;
  }

  /// Persian and Arabic-Indic digits to ASCII; everything else unchanged.
  static String foldDigits(String input) => input
      .replaceAllMapped(RegExp('[۰-۹]'), (m) => '${m[0]!.codeUnitAt(0) - 0x06f0}')
      .replaceAllMapped(RegExp('[٠-٩]'), (m) => '${m[0]!.codeUnitAt(0) - 0x0660}');

  /// `0912•••6789`, for anywhere a number is shown or logged.
  static String mask(String e164) {
    final local = e164.replaceFirst(RegExp(r'^\+98'), '0');
    if (local.length < 11) return '•' * local.length;
    return '${local.substring(0, 4)}•••${local.substring(local.length - 4)}';
  }
}
