import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api/api_error.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_icons.dart';
import '../core/theme/tokens.dart';
import '../l10n/l10n.dart';
import 'buttons.dart';
import 'primitives.dart';

/// A calm, centred message for "nothing here" and "something went wrong".
///
/// A small icon tile rather than a large illustration: the message is what matters, and a giant
/// grey icon is the most dated thing an empty screen can show.
class StateMessage extends StatelessWidget {
  const StateMessage({
    required this.icon,
    required this.title,
    this.message,
    this.footer,
    this.action,
    this.iconColor,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? footer;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.x6, vertical: AppSpace.x10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTile(icon: icon, size: 44, iconColor: iconColor),
              const SizedBox(height: AppSpace.x4),
              Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: AppSpace.x1 + 2),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
              if (footer != null) ...[const SizedBox(height: AppSpace.x3), footer!],
              if (action != null) ...[const SizedBox(height: AppSpace.x5), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty state.
class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.title, this.hint, this.action, super.key});

  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) =>
      StateMessage(icon: icon, title: title, message: hint, action: action);
}

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
    final l10n = context.l10n;
    final colors = context.colors;

    final apiError = error is ApiError ? error as ApiError : null;
    final message = apiError?.messageFa ?? l10n.errorUnknown;
    final canRetry = onRetry != null && (apiError?.isRetryable ?? true);

    final icon = apiError?.needsSupport == true
        ? AppIcons.locked
        : apiError?.code == 'NETWORK'
        ? AppIcons.offline
        : AppIcons.error;

    return StateMessage(
      icon: icon,
      title: message,
      footer: apiError?.requestId == null
          ? null
          : _RequestId(label: l10n.supportHint(apiError!.requestId!), id: apiError.requestId!),
      action: canRetry
          ? AppButton(label: l10n.retry, icon: AppIcons.retry, onPressed: onRetry)
          : null,
      iconColor: apiError?.needsSupport == true ? colors.warning : null,
    );
  }
}

/// The support reference, selectable so a student can copy it into a support message.
class _RequestId extends StatelessWidget {
  const _RequestId({required this.label, required this.id});

  final String label;
  final String id;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onLongPress: () => Clipboard.setData(ClipboardData(text: id)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2 + 2, vertical: AppSpace.x1),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: AppRadius.smAll,
          border: Border.all(color: colors.border),
        ),
        child: SelectableText(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}

enum AlertTone { danger, warning, info }

/// An inline message inside a form or a page section.
class InlineAlert extends StatelessWidget {
  const InlineAlert({required this.message, this.tone = AlertTone.danger, super.key});

  final String message;
  final AlertTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (fg, bg, icon) = switch (tone) {
      AlertTone.danger => (colors.danger, colors.dangerSubtle, AppIcons.error),
      AlertTone.warning => (colors.warning, colors.warningSubtle, AppIcons.error),
      AlertTone.info => (colors.textSecondary, colors.surfaceRaised, AppIcons.info),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3, vertical: AppSpace.x2 + 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: fg.withValues(alpha: 0.22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: fg),
            ),
            const SizedBox(width: AppSpace.x2 + 2),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tone == AlertTone.info ? colors.textSecondary : colors.text,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
