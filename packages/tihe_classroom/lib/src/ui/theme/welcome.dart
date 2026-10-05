import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../contracts/layout.dart';
import 'brand.dart';
import 'classroom_theme.dart';
import 'glass.dart';
import 'menu.dart';
import 'motion.dart';

/// The welcome page (docs/11 §11): the front door of every app built on the classroom — the
/// standalone classroom's launcher and the one TIHE app's sign-in are both this page, so they
/// cannot drift apart.
///
/// A title bar (the brand and a status lamp), the page's name with the light/dark switch, and
/// glass cards in one centred column over the night sky, rising in one after another.
class WelcomePage extends StatelessWidget {
  const WelcomePage({
    super.key,
    required this.title,
    required this.onToggleBrightness,
    required this.cards,
    this.status,
    this.backdrop = true,
  });

  final String title;
  final VoidCallback onToggleBrightness;

  /// Usually [WelcomeCard]s.
  final List<Widget> cards;

  /// Beside the brand in the title bar: the server's lamp ([StatusPill]).
  final Widget? status;

  /// Paints the sky behind the page. False in an app that already paints it behind every route.
  final bool backdrop;

  /// Below this width the page is laid out for a phone.
  static const narrowWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < narrowWidth;
    final body = SafeArea(
      child: Column(
        children: [
          WelcomeTitleBar(status: status),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  narrow ? 16 : 24,
                  8,
                  narrow ? 16 : 24,
                  28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      WelcomeHeader(
                        title: title,
                        onToggleBrightness: onToggleBrightness,
                      ),
                      SizedBox(height: narrow ? 18 : 24),
                      for (final (i, card) in cards.indexed) ...[
                        if (i > 0) const SizedBox(height: 18),
                        Appear(
                          delay: Duration(milliseconds: 80 * i),
                          offset: const Offset(0, 16),
                          child: card,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Scaffold(body: backdrop ? GlassBackdrop(child: body) : body);
  }
}

/// The brand and a status lamp at the physical left; when the app draws its own window frame
/// ([WindowChrome]), the window buttons at the right and the whole bar a handle to drag the
/// window by — where Windows keeps them in every language.
class WelcomeTitleBar extends StatelessWidget {
  const WelcomeTitleBar({super.key, this.status});

  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final chrome = WindowChrome.maybeOf(context);
    final page = Directionality.of(context);
    final bar = Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 6),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            const BrandLockup(),
            if (status case final status?) ...[
              const BarDivider(height: 26),
              Directionality(textDirection: page, child: status),
            ],
            const Spacer(),
            ?chrome?.controls,
          ],
        ),
      ),
    );
    return chrome == null ? bar : chrome.dragArea(bar);
  }
}

/// The page's name beside the brand's tile, centred, with the light/dark switch at the end.
class WelcomeHeader extends StatelessWidget {
  const WelcomeHeader({
    super.key,
    required this.title,
    required this.onToggleBrightness,
    this.icon = ClassroomIcons.play,
  });

  final String title;
  final VoidCallback onToggleBrightness;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final dark = t.isDark;
    final narrow = MediaQuery.sizeOf(context).width < WelcomePage.narrowWidth;
    final toggle = Glass(
      radius: 999,
      shadow: false,
      padding: const EdgeInsets.all(3),
      child: GlassIconButton(
        icon: dark ? ClassroomIcons.light : ClassroomIcons.dark,
        tooltip: dark ? 'پوستهٔ روشن' : 'پوستهٔ تیره',
        size: 42,
        iconSize: 20,
        radius: 999,
        onPressed: onToggleBrightness,
      ),
    );
    return SizedBox(
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: narrow ? 56 : 64),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTile(icon: icon, size: narrow ? 44 : 54, solid: true),
                const SizedBox(width: 16),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: narrow ? 21 : 28,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        color: t.text,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          PositionedDirectional(end: 0, child: toggle),
        ],
      ),
    );
  }
}

/// A glass card: its name and a line on what it is for, its tile at the end, then its fields
/// and its button.
class WelcomeCard extends StatelessWidget {
  const WelcomeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Glass(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.6,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              IconTile(icon: icon, size: 58),
            ],
          ),
          for (final child in children) ...[const SizedBox(height: 16), child],
        ],
      ),
    );
  }
}

/// A text field in the design's shape: icon and label at the start, the value at the end. The
/// value is Latin — an address, a phone number, a password — so it runs left to right.
class WelcomeField extends StatefulWidget {
  const WelcomeField({
    super.key,
    required this.icon,
    required this.label,
    required this.controller,
    this.focusNode,
    this.obscure = false,
    this.autofocus = false,
    this.hint,
    this.error,
    this.trailing,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });

  final IconData icon;
  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool obscure;
  final bool autofocus;

  /// Shown in the value's place while it is empty.
  final String? hint;

  /// What is wrong with the value: the field turns red and says so underneath.
  final String? error;

  /// After the value: a show-password switch, say.
  final Widget? trailing;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<WelcomeField> createState() => _WelcomeFieldState();
}

class _WelcomeFieldState extends State<WelcomeField> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(WelcomeField old) {
    super.didUpdateWidget(old);
    final was = old.focusNode ?? _own;
    if (was != _focus) {
      was?.removeListener(_changed);
      _focus.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final focused = _focus.hasFocus;
    final error = widget.error;
    final edge = error != null
        ? t.danger
        : focused
        ? t.accent
        : t.fieldBorder;
    final field = GestureDetector(
      onTap: _focus.requestFocus,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        height: 56,
        padding: const EdgeInsetsDirectional.only(start: 18, end: 18),
        decoration: BoxDecoration(
          color: t.field,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: edge,
            width: focused || error != null ? 1.5 : 1,
          ),
          boxShadow: focused && error == null
              ? t.accentGlow(strength: 0.35)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 20,
              color: error != null
                  ? t.danger
                  : focused
                  ? t.accentText
                  : t.textSecondary,
            ),
            const SizedBox(width: 12),
            Text(
              widget.label,
              style: TextStyle(fontSize: 14.5, color: t.textSecondary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Semantics(
                label: widget.label,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  obscureText: widget.obscure,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  autofillHints: widget.autofillHints,
                  inputFormatters: widget.inputFormatters,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 15.5, color: t.text),
                  decoration: InputDecoration(
                    filled: false,
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: widget.hint,
                    hintTextDirection: TextDirection.ltr,
                    hintStyle: TextStyle(fontSize: 15.5, color: t.textTertiary),
                  ),
                ),
              ),
            ),
            if (widget.trailing case final trailing?) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    );
    if (error == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 18, top: 6),
          child: Text(
            error,
            style: TextStyle(fontSize: 13, height: 1.5, color: t.danger),
          ),
        ),
      ],
    );
  }
}

/// A demo class's starting layout, as a field that opens a glass menu of the six presets.
class WelcomeLayoutField extends StatelessWidget {
  const WelcomeLayoutField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final LayoutPreset value;
  final ValueChanged<LayoutPreset> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return GlassPressable(
      semanticLabel: 'چیدمان آغازین: ${layoutPresets[value]!.name}',
      radius: 15,
      onTap: () async {
        final chosen = await showGlassMenu<LayoutPreset>(
          context: context,
          width: null,
          entries: [
            for (final p in LayoutPreset.values)
              GlassMenuItem(
                value: p,
                label: layoutPresets[p]!.name,
                checked: p == value,
              ),
          ],
        );
        if (chosen != null) onChanged(chosen);
      },
      builder: (context, s) => AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        height: 60,
        padding: const EdgeInsetsDirectional.only(start: 18, end: 16),
        decoration: BoxDecoration(
          color: s.hovered ? Color.alphaBlend(t.glassHover, t.field) : t.field,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: t.fieldBorder),
        ),
        child: Row(
          children: [
            Icon(ClassroomIcons.screen, size: 20, color: t.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'چیدمان آغازین',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: t.textTertiary,
                    ),
                  ),
                  Text(
                    layoutPresets[value]!.name,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ],
              ),
            ),
            Icon(ClassroomIcons.chevronDown, size: 20, color: t.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Something went wrong, in the card it went wrong in.
class WelcomeNote extends StatelessWidget {
  const WelcomeNote(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: t.dangerSubtle,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: t.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ClassroomIcons.alert, size: 18, color: t.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: t.danger,
                height: 1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
