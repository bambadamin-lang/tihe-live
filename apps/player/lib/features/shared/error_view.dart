import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../l10n/l10n.dart';

/// Renders a failure the way the student needs to see it.
///
/// Always prefers the server's `messageFa` over anything composed here: the server knows why it
/// refused, and it already phrased it. The request id is shown when present, because "give support
/// this code" is far more useful than "it did not work".
class ErrorView extends StatelessWidget {
  const ErrorView({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final apiError = error is ApiError ? error as ApiError : null;
    final message = apiError?.messageFa ?? l10n.errorUnknown;
    final canRetry = onRetry != null && (apiError?.isRetryable ?? true);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              apiError?.needsSupport == true ? Icons.lock_outline : Icons.cloud_off,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(message, style: theme.textTheme.titleSmall, textAlign: TextAlign.center),
            if (apiError?.requestId != null) ...[
              const SizedBox(height: 8),
              // Selectable so a student can copy it into a support message.
              SelectableText(
                l10n.supportHint(apiError!.requestId!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (canRetry) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
