import 'package:flutter/material.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

import 'update.dart';

/// Offers a new version on the start screen. Only shown outside class, so an update never
/// interrupts a lesson; the student chooses when to install.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.updater});

  final Updater updater;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: updater,
    builder: (context, state, _) => switch (state) {
      UpdateIdle() => const SizedBox.shrink(),
      UpdateAvailable(:final release) => _Banner(
        title: 'نسخهٔ تازهٔ ${toPersianDigits(release.version)} آماده است',
        hint: 'برنامه بسته می‌شود، به‌روز می‌شود و دوباره باز می‌شود.',
        actions: [
          TextButton(onPressed: updater.dismiss, child: const Text('بعداً')),
          FilledButton(
            onPressed: updater.install,
            child: const Text('به‌روزرسانی'),
          ),
        ],
      ),
      UpdateDownloading(:final release, :final progress) => _Banner(
        title:
            'در حال دریافت نسخهٔ ${toPersianDigits(release.version)}… '
            '${toPersianDigits((progress * 100).floor())}٪',
        progress: progress,
      ),
      UpdateInstalling() => const _Banner(
        title: 'در حال نصب…',
        hint: 'برنامه چند لحظهٔ دیگر دوباره باز می‌شود.',
        progress: 1,
      ),
      UpdateFailed(:final messageFa) => _Banner(
        title: 'به‌روزرسانی انجام نشد',
        hint: messageFa,
        danger: true,
        actions: [
          TextButton(onPressed: updater.dismiss, child: const Text('بعداً')),
          FilledButton(
            onPressed: updater.install,
            child: const Text('تلاش دوباره'),
          ),
        ],
      ),
    },
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.title,
    this.hint,
    this.progress,
    this.danger = false,
    this.actions = const [],
  });

  final String title;
  final String? hint;
  final double? progress;
  final bool danger;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Glass(
        radius: 20,
        fill: danger ? t.dangerSubtle : t.accentSubtle,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: danger ? t.danger : t.text,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(
                hint!,
                style: TextStyle(fontSize: 12.5, color: t.textSecondary),
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                borderRadius: BorderRadius.circular(999),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final a in actions) ...[const SizedBox(width: 8), a],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
