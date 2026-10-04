import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/tokens.dart';

enum AppTextFieldSize { medium, large }

/// A text input with its label above it.
///
/// A label above the field rather than floating inside it: it never animates away, never overlaps
/// the value, and reads the same in RTL. Focus shows an accent border plus a soft ring, so the
/// focused field is obvious without a heavy outline.
class AppTextField extends StatefulWidget {
  const AppTextField({
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.errorText,
    this.helper,
    this.size = AppTextFieldSize.medium,
    this.autofocus = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.textDirection,
    this.textAlign = TextAlign.start,
    this.style,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
    this.obscureText = false,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final String? errorText;
  final String? helper;
  final AppTextFieldSize size;
  final bool autofocus;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextDirection? textDirection;
  final TextAlign textAlign;
  final TextStyle? style;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  /// For passwords: hides the value and turns off suggestions and autocorrect.
  final bool obscureText;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode => widget.focusNode ?? (_ownFocusNode ??= FocusNode());
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocusNode)?.removeListener(_onFocusChange);
      _focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _ownFocusNode?.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final hasError = widget.errorText != null;
    final large = widget.size == AppTextFieldSize.large;

    final ringColor = hasError ? colors.danger : colors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: theme.textTheme.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpace.x2 - 2),
        ],
        AnimatedContainer(
          duration: AppMotion.fast,
          decoration: BoxDecoration(
            borderRadius: AppRadius.mdAll,
            boxShadow: [
              if (_focused) BoxShadow(color: ringColor.withValues(alpha: 0.22), spreadRadius: 3),
            ],
          ),
          // An LTR value (a phone number, a code) lays its decoration out LTR too, so the icon sits
          // beside the digits rather than across the field from them.
          child: Directionality(
            textDirection: widget.textDirection ?? Directionality.of(context),
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              enabled: widget.enabled,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              textDirection: widget.textDirection,
              textAlign: widget.textAlign,
              inputFormatters: widget.inputFormatters,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              autofillHints: widget.autofillHints,
              obscureText: widget.obscureText,
              enableSuggestions: !widget.obscureText,
              autocorrect: !widget.obscureText,
              cursorWidth: 1.5,
              style: (large ? theme.textTheme.bodyLarge : theme.textTheme.bodyMedium)
                  ?.copyWith(height: 1.4)
                  .merge(widget.style),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintTextDirection: widget.textDirection,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpace.x3,
                  vertical: large ? 14 : 10,
                ),
                prefixIcon: widget.prefixIcon == null
                    ? null
                    : Icon(
                        widget.prefixIcon,
                        size: 16,
                        color: _focused ? colors.textSecondary : null,
                      ),
                prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
                suffixIcon: widget.suffix,
                suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
                enabledBorder: hasError
                    ? OutlineInputBorder(
                        borderRadius: AppRadius.mdAll,
                        borderSide: BorderSide(color: colors.danger),
                      )
                    : null,
              ),
            ),
          ),
        ),
        if (widget.errorText != null || widget.helper != null) ...[
          const SizedBox(height: AppSpace.x2 - 2),
          Text(
            widget.errorText ?? widget.helper!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: hasError ? colors.danger : colors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}
