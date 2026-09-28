import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_icons.dart';
import '../core/theme/tokens.dart';
import '../l10n/l10n.dart';
import 'buttons.dart';

/// Asks the student to confirm. Resolves to true only on an explicit confirm.
///
/// [destructive] colours the confirm button as danger. The cancel button takes initial focus, so a
/// stray Enter never confirms something irreversible.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) => AppDialog(
      title: title,
      body: Text(message),
      actions: [
        AppButton(
          label: context.l10n.cancel,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: confirmLabel,
          variant: destructive ? AppButtonVariant.danger : AppButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// A dialog frame: title, body, actions. Narrow and flat — a hairline border, one soft shadow.
class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    required this.body,
    this.actions = const [],
    this.maxWidth = 420,
    super.key,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final compact = context.windowSize.isCompact;

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpace.x4),
      shadowColor: colors.shadow,
      elevation: 24,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                  if (actions.isEmpty)
                    AppIconButton(
                      icon: AppIcons.close,
                      tooltip: context.l10n.close,
                      size: AppButtonSize.small,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.x2),
              DefaultTextStyle.merge(
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                child: body,
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpace.x6),
                if (compact)
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpace.x2),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpace.x2),
                        actions[i],
                      ],
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum ToastTone { neutral, success, danger }

/// A brief confirmation or failure at the bottom of the window.
void showToast(BuildContext context, String message, {ToastTone tone = ToastTone.neutral}) {
  final colors = context.colors;
  final compact = context.windowSize.isCompact;
  final icon = switch (tone) {
    ToastTone.neutral => null,
    ToastTone.success => AppIcons.downloaded,
    ToastTone.danger => AppIcons.error,
  };
  final iconColor = switch (tone) {
    ToastTone.danger => colors.danger,
    ToastTone.success => colors.success,
    ToastTone.neutral => colors.onInverse,
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        width: compact ? null : 420,
        margin: compact ? const EdgeInsets.all(AppSpace.x3) : null,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.x4, vertical: AppSpace.x3),
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: AppSpace.x2 + 2),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}
