import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/models.dart' as api;
import '../../core/providers.dart';
import '../../core/theme/jalali.dart';
import '../../l10n/l10n.dart';
import '../shared/error_view.dart';

/// Device management.
///
/// This screen is the answer to `DEVICE_LIMIT_REACHED`. A student who has used their allowance needs
/// somewhere to act, not just a refusal — so the error opens this, and the confirmation says plainly
/// that releasing a device makes its downloads unplayable, because that is what happens
/// server-side.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final devices = ref.watch(devicesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.devicesTitle)),
      body: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(devicesProvider),
        ),
        data: (items) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, index) => _DeviceCard(device: items[index]),
        ),
      ),
    );
  }
}

class _DeviceCard extends ConsumerWidget {
  const _DeviceCard({required this.device});

  final api.Device device;

  static const _icons = {
    'windows': Icons.laptop_windows,
    'android': Icons.phone_android,
    'ios': Icons.phone_iphone,
    'macos': Icons.laptop_mac,
    'linux': Icons.computer,
  };

  Future<void> _release(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.releaseDevice),
        content: Text(l10n.releaseDeviceConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(devicesRepositoryProvider).release(device.id);
      ref.invalidate(devicesProvider);

      // Releasing the device you are using ends your own session, which is a legitimate thing to
      // want — the router sends you back to sign-in.
      if (device.isCurrent) {
        await ref.read(authControllerProvider.notifier).signOut();
      }
    } on ApiError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.messageFa)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _icons[device.platform] ?? Icons.devices_other,
              size: 32,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          device.name,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (device.isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            l10n.thisDevice,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (device.offlineVideoCount > 0)
                        l10n.offlineVideos(
                          JalaliFormat.toPersianDigits('${device.offlineVideoCount}'),
                        ),
                      if (device.lastSeenAt != null)
                        l10n.lastSeen(JalaliFormat.relative(device.lastSeenAt!)),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.releaseDevice,
              onPressed: () => _release(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
