/// The server's error envelope, as defined in `packages/contracts`.
///
/// `messageFa` comes from the server rather than being mapped client-side. That is deliberate: if
/// the client mapped codes to Persian strings itself, any code added after a release would render
/// blank or in English on apps already installed on students' devices.
class ApiError implements Exception {
  const ApiError({
    required this.code,
    required this.message,
    required this.messageFa,
    this.details,
    this.requestId,
  });

  final String code;
  final String message;
  final String messageFa;
  final Map<String, dynamic>? details;
  final String? requestId;

  factory ApiError.fromJson(Map<String, dynamic> json) {
    final error = json['error'] as Map<String, dynamic>?;
    if (error == null) {
      return const ApiError(
        code: 'INTERNAL',
        message: 'malformed error response',
        messageFa: 'خطای غیرمنتظره‌ای رخ داد.',
      );
    }
    return ApiError(
      code: error['code'] as String? ?? 'INTERNAL',
      message: error['message'] as String? ?? '',
      messageFa: error['messageFa'] as String? ?? 'خطای غیرمنتظره‌ای رخ داد.',
      details: error['details'] as Map<String, dynamic>?,
      requestId: error['requestId'] as String?,
    );
  }

  /// No network, or the server never answered. Distinguished from a server refusal because the
  /// recovery differs: check your connection, versus contact the institute.
  factory ApiError.network() => const ApiError(
        code: 'NETWORK',
        message: 'network unreachable',
        messageFa: 'اتصال به سرور برقرار نشد. اتصال اینترنت خود را بررسی کنید.',
      );

  /// Whether the client should send the user back to sign-in.
  bool get requiresReauth =>
      code == 'UNAUTHENTICATED' ||
      code == 'TOKEN_EXPIRED' ||
      code == 'DEVICE_REVOKED' ||
      code == 'DEVICE_UNKNOWN';

  /// Whether the device manager should open, so the user can free a slot instead of hitting a
  /// dead end.
  bool get needsDeviceManager => code == 'DEVICE_LIMIT_REACHED';

  /// Whether the institute has to act — nothing the student can do in the app.
  bool get needsSupport =>
      code == 'NOT_ENROLLED' ||
      code == 'LICENSE_MISSING' ||
      code == 'LICENSE_EXPIRED' ||
      code == 'LICENSE_REVOKED';

  bool get isRetryable => code == 'RATE_LIMITED' || code == 'VIDEO_NOT_READY' || code == 'NETWORK';

  @override
  String toString() => 'ApiError($code): $message';
}
