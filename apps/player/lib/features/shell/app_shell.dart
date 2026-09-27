import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';

/// Top-level destinations.
enum Destination {
  library('/library'),
  search('/search'),
  devices('/devices'),
  account('/account');

  const Destination(this.location);

  final String location;

  /// Which destination a location belongs to. A course page belongs to the library.
  static Destination of(String location) {
    if (location.startsWith('/search')) return Destination.search;
    if (location.startsWith('/devices')) return Destination.devices;
    if (location.startsWith('/account')) return Destination.account;
    return Destination.library;
  }

  IconData get icon => switch (this) {
        Destination.library => AppIcons.library,
        Destination.search => AppIcons.search,
        Destination.devices => AppIcons.devices,
        Destination.account => AppIcons.account,
      };

  String label(AppLocalizations l10n) => switch (this) {
        Destination.library => l10n.navLibrary,
        Destination.search => l10n.navSearch,
        Destination.devices => l10n.devicesTitle,
        Destination.account => l10n.accountTitle,
      };
}

/// The frame around every signed-in page except the player.
///
/// The navigation pattern changes with the window rather than shrinking: a sidebar with labels on
/// desktop, an icon rail on tablets and narrow windows, a bottom bar on phones, where the thumb is.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Ctrl+K (⌘K on macOS) opens search from anywhere in the shell.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyK) return false;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) return false;
    // The player and dialogs sit above the shell; the shortcut belongs to the shell's own pages.
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return false;
    context.go(Destination.search.location);
    return true;
  }

  void _go(Destination destination) => context.go(destination.location);

  @override
  Widget build(BuildContext context) {
    final size = context.windowSize;
    final current = Destination.of(widget.location);
    final colors = context.colors;

    if (size.isCompact) {
      return Scaffold(
        body: widget.child,
        bottomNavigationBar: _BottomBar(
          // Devices is reached through Account on a phone.
          current: current == Destination.devices ? Destination.account : current,
          onSelect: _go,
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          if (size.isExpanded)
            _Sidebar(current: current, onSelect: _go)
          else
            _Rail(current: current, onSelect: _go),
          Container(width: 1, color: colors.border),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.current, required this.onSelect});

  final Destination current;
  final ValueChanged<Destination> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthSignedIn ? auth.session.user : null;

    return Container(
      width: 248,
      color: colors.sidebar,
      child: SafeArea(
        right: false,
        left: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.x2, AppSpace.x2, AppSpace.x2, AppSpace.x5),
                child: Row(
                  children: [
                    const BrandMark(size: 24),
                    const SizedBox(width: AppSpace.x2 + 2),
                    Text(l10n.appTitle, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              _SearchTrigger(onTap: () => onSelect(Destination.search), active: current == Destination.search),
              const SizedBox(height: AppSpace.x4),
              for (final destination in [Destination.library, Destination.devices, Destination.account])
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _SidebarItem(
                    icon: destination.icon,
                    label: destination.label(l10n),
                    selected: destination == current,
                    onTap: () => onSelect(destination),
                  ),
                ),
              const Spacer(),
              if (user != null) _UserFooter(user: user, onTap: () => onSelect(Destination.account)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchTrigger extends StatelessWidget {
  const _SearchTrigger({required this.onTap, required this.active});

  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;

    return Pressable(
      onTap: onTap,
      semanticLabel: context.l10n.searchTitle,
      color: colors.surface,
      border: Border.all(color: active ? colors.borderStrong : colors.border),
      builder: (context, state) => SizedBox(
        height: 34,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpace.x2 + 2, end: AppSpace.x1 + 2),
          child: Row(
            children: [
              Icon(AppIcons.search, size: 15, color: colors.textTertiary),
              const SizedBox(width: AppSpace.x2),
              Expanded(
                child: Text(
                  '${context.l10n.navSearch}…',
                  style: TextStyle(fontSize: 13, height: 1.2, color: colors.textTertiary),
                ),
              ),
              KeyCap(isMac ? '⌘K' : 'Ctrl K'),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        borderRadius: AppRadius.smAll,
        color: selected ? colors.surfaceHover : Colors.transparent,
        builder: (context, state) {
          final fg = selected || state.hovered ? colors.text : colors.textSecondary;
          return SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2 + 2),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: selected ? colors.accentText : fg),
                  const SizedBox(width: AppSpace.x2 + 2),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.2, color: fg),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _UserFooter extends StatelessWidget {
  const _UserFooter({required this.user, required this.onTap});

  final AppUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = displayNameOf(user, context.l10n);

    return Pressable(
      onTap: onTap,
      semanticLabel: context.l10n.accountTitle,
      padding: const EdgeInsets.all(AppSpace.x2),
      child: Row(
        children: [
          Monogram(text: name, size: 30, circle: true),
          const SizedBox(width: AppSpace.x2 + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.3, color: colors.text),
                ),
                Text(
                  user.phoneMasked,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 11.5, height: 1.3, color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends ConsumerWidget {
  const _Rail({required this.current, required this.onSelect});

  final Destination current;
  final ValueChanged<Destination> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthSignedIn ? auth.session.user : null;

    return Container(
      width: 64,
      color: colors.sidebar,
      child: SafeArea(
        right: false,
        left: false,
        child: Column(
          children: [
            const SizedBox(height: AppSpace.x4),
            const BrandMark(size: 26),
            const SizedBox(height: AppSpace.x6),
            for (final destination in Destination.values)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.x1),
                child: AppIconButton(
                  icon: destination.icon,
                  tooltip: destination.label(l10n),
                  size: AppButtonSize.large,
                  selected: destination == current,
                  onPressed: () => onSelect(destination),
                ),
              ),
            const Spacer(),
            if (user != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.x4),
                child: Tooltip(
                  message: displayNameOf(user, l10n),
                  child: Pressable(
                    onTap: () => onSelect(Destination.account),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: Monogram(text: displayNameOf(user, l10n), size: 32, circle: true),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.current, required this.onSelect});

  final Destination current;
  final ValueChanged<Destination> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (final destination in [Destination.library, Destination.search, Destination.account])
                Expanded(
                  child: Semantics(
                    selected: destination == current,
                    child: Pressable(
                      onTap: () => onSelect(destination),
                      semanticLabel: destination.label(l10n),
                      hoverColor: Colors.transparent,
                      pressedColor: Colors.transparent,
                      borderRadius: BorderRadius.zero,
                      builder: (context, state) {
                        final selected = destination == current;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: AppMotion.base,
                              curve: AppMotion.curve,
                              width: 48,
                              height: 28,
                              decoration: BoxDecoration(
                                color: selected ? colors.accentSubtle : Colors.transparent,
                                borderRadius: BorderRadius.circular(AppRadius.full),
                              ),
                              child: Icon(
                                destination.icon,
                                size: 19,
                                color: selected ? colors.accentText : colors.textTertiary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              destination == Destination.account ? l10n.navAccount : destination.label(l10n),
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                fontWeight: FontWeight.w500,
                                color: selected ? colors.text : colors.textTertiary,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The name to show for a student: their display name, else their role.
String displayNameOf(AppUser user, AppLocalizations l10n) {
  final name = user.displayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return roleLabelOf(user.role, l10n);
}

String roleLabelOf(String role, AppLocalizations l10n) => switch (role) {
      'teacher' => l10n.roleTeacher,
      'admin' => l10n.roleAdmin,
      _ => l10n.roleStudent,
    };

/// Shown while the session is being restored on launch.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: 40),
            SizedBox(height: AppSpace.x6),
            AppSpinner(size: 16),
          ],
        ),
      ),
    );
  }
}
