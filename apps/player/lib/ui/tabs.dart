import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/tokens.dart';
import 'pressable.dart';

/// A tab in [AppTabs].
class AppTab {
  const AppTab({required this.label, this.count});

  final String label;

  /// Shown after the label in a quieter tone: "Chapters 6".
  final String? count;
}

/// Text tabs with an underline indicator.
///
/// Controlled: the parent owns the selected index. A hairline runs under the whole strip so the
/// tabs read as a header for the content below, not as floating buttons.
class AppTabs extends StatelessWidget {
  const AppTabs({
    required this.tabs,
    required this.selected,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final List<AppTab> tabs;
  final int selected;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpace.x1),
                child: _TabButton(tab: tabs[i], selected: i == selected, onTap: () => onChanged(i)),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.tab, required this.selected, required this.onTap});

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      child: Pressable(
        onTap: onTap,
        semanticLabel: tab.label,
        hoverColor: Colors.transparent,
        pressedColor: Colors.transparent,
        borderRadius: AppRadius.smAll,
        builder: (context, state) => Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.x2 + 2,
                AppSpace.x2,
                AppSpace.x2 + 2,
                AppSpace.x3 - 1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: AppMotion.fast,
                    style: TextStyle(
                      fontFamily: Theme.of(context).textTheme.labelMedium?.fontFamily,
                      fontSize: 13.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: selected || state.hovered ? colors.text : colors.textTertiary,
                    ),
                    child: Text(tab.label),
                  ),
                  if (tab.count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      tab.count!,
                      style: TextStyle(fontSize: 12, height: 1.4, color: colors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            PositionedDirectional(
              start: AppSpace.x2 + 2,
              end: AppSpace.x2 + 2,
              bottom: 0,
              child: AnimatedContainer(
                duration: AppMotion.base,
                curve: AppMotion.curve,
                height: 2,
                decoration: BoxDecoration(
                  color: selected ? colors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One option in an [AppSegmented] control.
class AppSegment<T> {
  const AppSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// A segmented control, for choosing one of a few mutually exclusive settings.
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expand = false,
    super.key,
  });

  final List<AppSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final children = [
      for (final segment in segments)
        _wrap(
          Semantics(
            selected: segment.value == value,
            child: Pressable(
              onTap: () => onChanged(segment.value),
              semanticLabel: segment.label,
              borderRadius: AppRadius.smAll,
              color: segment.value == value
                  ? (dark ? colors.surfacePressed : colors.surface)
                  : Colors.transparent,
              hoverColor: segment.value == value ? null : colors.surfaceHover,
              builder: (context, state) {
                final selected = segment.value == value;
                final fg = selected || state.hovered ? colors.text : colors.textSecondary;
                return Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3),
                  decoration: selected && !dark
                      ? BoxDecoration(
                          borderRadius: AppRadius.smAll,
                          boxShadow: [
                            BoxShadow(
                              color: colors.shadow,
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        )
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (segment.icon != null) ...[
                        Icon(segment.icon, size: 14, color: fg),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        segment.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                          color: fg,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: children),
    );
  }

  Widget _wrap(Widget child) => expand ? Expanded(child: child) : child;
}
