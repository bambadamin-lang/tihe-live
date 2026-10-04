import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/jalali.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';

/// The fewest and most devices an account may be signed in on at once — `deviceLimitSchema` in
/// packages/contracts.
const minDeviceLimit = 1;
const maxDeviceLimit = 20;

/// A small number changed one step at a time. The device limit is small and rarely changed, so
/// two large buttons beat a text field someone can mistype.
class LimitStepper extends StatelessWidget {
  const LimitStepper({
    required this.value,
    required this.onChanged,
    this.min = minDeviceLimit,
    this.max = maxDeviceLimit,
    super.key,
  });

  final int value;

  /// Null disables both buttons.
  final ValueChanged<int>? onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final change = onChanged;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          icon: AppIcons.decrease,
          tooltip: l10n.decrease,
          variant: AppIconButtonVariant.secondary,
          onPressed: change != null && value > min ? () => change(value - 1) : null,
        ),
        SizedBox(
          width: 52,
          child: Text(
            JalaliFormat.toPersianDigits('$value'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        AppIconButton(
          icon: AppIcons.increase,
          tooltip: l10n.increase,
          variant: AppIconButtonVariant.secondary,
          onPressed: change != null && value < max ? () => change(value + 1) : null,
        ),
      ],
    );
  }
}
