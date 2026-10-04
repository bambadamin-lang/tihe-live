import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/models.dart' as api;
import '../../core/providers.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';
import 'device_icon.dart';

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
    final back = context.windowSize.isExpanded
        ? null
        : BackTarget(label: l10n.accountTitle, fallbackLocation: '/account');

    return AppPage(
      back: back,
      maxWidth: 720,
      onRefresh: () async => ref.invalidate(devicesProvider),
      header: PageHeader(title: l10n.devicesTitle, subtitle: l10n.devicesSubtitle),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: AppSpace.x6)),
        ...devices.when(
          skipLoadingOnRefresh: true,
          loading: () => [
            SliverToBoxAdapter(
              child: AppListGroup(
                children: [for (var i = 0; i < 3; i++) const SkeletonRow(titleWidth: 140)],
              ),
            ),
          ],
          error: (error, _) => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorView(error: error, onRetry: () => ref.invalidate(devicesProvider)),
            ),
          ],
          data: (items) => [
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(icon: AppIcons.devices, title: l10n.devicesEmpty),
              )
            else
              SliverToBoxAdapter(
                child: AppListGroup(
                  children: [for (final device in items) _DeviceRow(device: device)],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DeviceRow extends StatefulWidget {
  const _DeviceRow({required this.device});

  final api.Device device;

  @override
  State<_DeviceRow> createState() => _DeviceRowState();
}

class _DeviceRowState extends State<_DeviceRow> {
  bool _releasing = false;

  Future<void> _release() async {
    final l10n = context.l10n;
    final device = widget.device;

    final confirmed = await showConfirmDialog(
      context,
      title: l10n.releaseDevice,
      message: l10n.releaseDeviceConfirm,
      confirmLabel: l10n.remove,
      destructive: true,
    );

    if (!confirmed || !mounted) return;
    setState(() => _releasing = true);

    // The row can be rebuilt away while the request is in flight; the container outlives it.
    final container = ProviderScope.containerOf(context, listen: false);

    try {
      await container.read(devicesRepositoryProvider).signOut(device.id);
      container.invalidate(devicesProvider);
      if (mounted) showToast(context, l10n.deviceReleased, tone: ToastTone.success);

      // Releasing the device you are using ends your own session, which is a legitimate thing to
      // want — the router sends you back to sign-in.
      if (device.isCurrent) {
        await container.read(authControllerProvider.notifier).signOut();
      }
    } on ApiError catch (e) {
      if (mounted) showToast(context, e.messageFa, tone: ToastTone.danger);
    } finally {
      if (mounted) setState(() => _releasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final device = widget.device;

    final meta = [
      if (device.offlineVideoCount > 0)
        l10n.offlineVideos(JalaliFormat.toPersianDigits('${device.offlineVideoCount}')),
      if (device.lastSeenAt != null) l10n.lastSeen(JalaliFormat.relative(device.lastSeenAt!)),
    ];

    return AppListRow(
      title: device.name,
      leading: IconTile(icon: deviceIcon(device.platform)),
      // Wraps rather than truncating: on a phone the badge and "last used" do not fit one line.
      subtitle: Wrap(
        spacing: AppSpace.x2,
        runSpacing: AppSpace.x1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (device.isCurrent) AppBadge(label: l10n.thisDevice, tone: BadgeTone.accent),
          if (meta.isNotEmpty) MetaLine(items: meta, maxLines: 2),
        ],
      ),
      trailing: AppIconButton(
        icon: AppIcons.remove,
        tooltip: l10n.releaseDevice,
        loading: _releasing,
        hoverColor: Theme.of(context).colorScheme.errorContainer,
        onPressed: _release,
      ),
    );
  }
}
