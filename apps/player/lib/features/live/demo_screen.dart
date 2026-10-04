import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tihe_classroom/demo.dart' show DemoClassroom;
import 'package:tihe_classroom/tihe_classroom.dart' show Glass;

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';
import 'classroom_launcher.dart';

/// The demo class, reachable before signing in: one tap per role, no server, no account.
///
/// It is how someone tries the classroom before the institute's server exists, and how a teacher
/// rehearses the controls before their first real class.
class DemoScreen extends StatelessWidget {
  const DemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.colors;

    final roles = [
      (DemoClassroom.host, AppIcons.liveClass, l10n.demoAsHost, l10n.demoAsHostHint),
      (DemoClassroom.cohost, AppIcons.users, l10n.demoAsCohost, l10n.demoAsCohostHint),
      (DemoClassroom.ali, AppIcons.account, l10n.demoAsStudent, l10n.demoAsStudentHint),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.x5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppButton.ghost(
                      label: l10n.back,
                      icon: AppIcons.back,
                      size: AppButtonSize.small,
                      onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                    ),
                  ),
                  const SizedBox(height: AppSpace.x4),
                  Glass(
                    radius: 24,
                    strong: true,
                    padding: const EdgeInsets.all(AppSpace.x6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: BrandMark(size: 40)),
                        const SizedBox(height: AppSpace.x5),
                        Text(
                          l10n.demoTitle,
                          style: theme.textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpace.x2),
                        Text(
                          l10n.demoSubtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpace.x6),
                        AppListGroup(
                          children: [
                            for (final (id, icon, title, hint) in roles)
                              AppListRow(
                                title: title,
                                subtitle: hint,
                                leading: IconTile(icon: icon),
                                showChevron: true,
                                onTap: () => openDemoClass(context, as: id),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.x4),
                        Text(
                          l10n.demoNote,
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
