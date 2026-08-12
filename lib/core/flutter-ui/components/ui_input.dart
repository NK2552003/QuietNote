import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ui_theme.dart';
import '../theme/ui_tokens.dart';
import 'ui_common.dart';

/// Chrome treatments for text fields.
enum UiInputVariant { outline, filled, underline, ghost }

/// Text input covering Input / Textarea / SearchInput / numeric order entry.
///
/// States: default, hover, focus, filled, read-only, disabled, invalid,
/// valid, warning, loading, with counter, with clear affordance.
class UiInput extends StatefulWidget {
  const UiInput({
    super.key,
    this.controller,
    this.hintText,
    this.value,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.leadingIcon,
    this.trailingIcon,
    this.onTrailingTap,
    this.leading,
    this.trailing,
    this.obscure = false,
    this.enabled = true,
    this.readOnly = false,
    this.error = false,
    this.validation = UiValidationState.none,
    this.variant = UiInputVariant.outline,
    this.density = UiDensity.comfortable,
    this.size = UiSize.md,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.focusNode,
    this.maxLength,
    this.showCounter = false,
    this.clearable = false,
    this.loading = false,
    this.prefixText,
    this.suffixText,
    this.suffix,
    this.intent,
    this.semanticLabel,
    this.expand = true,
  });

  /// Multiline variant (Textarea).
  const UiInput.multiline({
    super.key,
    this.controller,
    this.hintText,
    this.value,
    this.onChanged,
    this.enabled = true,
    this.readOnly = false,
    this.error = false,
    this.validation = UiValidationState.none,
    this.variant = UiInputVariant.outline,
    this.density = UiDensity.comfortable,
    this.size = UiSize.md,
    this.maxLines = 6,
    this.minLines = 3,
    this.maxLength,
    this.showCounter = false,
    this.autofocus = false,
    this.focusNode,
    this.intent,
    this.semanticLabel,
    this.expand = true,
  })  : leadingIcon = null,
        trailingIcon = null,
        onTrailingTap = null,
        onSubmitted = null,
        onClear = null,
        leading = null,
        trailing = null,
        obscure = false,
        keyboardType = TextInputType.multiline,
        inputFormatters = null,
        textInputAction = TextInputAction.newline,
        textAlign = TextAlign.start,
        clearable = false,
        loading = false,
        prefixText = null,
        suffixText = null,
        suffix = null;

  /// Search variant used on discovery / symbol lookup screens.
  const UiInput.search({
    super.key,
    this.controller,
    this.hintText = 'Search',
    this.value,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.enabled = true,
    this.loading = false,
    this.clearable = true,
    this.variant = UiInputVariant.filled,
    this.density = UiDensity.comfortable,
    this.size = UiSize.md,
    this.autofocus = false,
    this.focusNode,
    this.semanticLabel,
    this.expand = true,
  })  : leadingIcon = Icons.search,
        trailingIcon = null,
        onTrailingTap = null,
        leading = null,
        trailing = null,
        obscure = false,
        readOnly = false,
        error = false,
        validation = UiValidationState.none,
        maxLines = 1,
        minLines = null,
        keyboardType = TextInputType.text,
        inputFormatters = null,
        textInputAction = TextInputAction.search,
        textAlign = TextAlign.start,
        maxLength = null,
        showCounter = false,
        prefixText = null,
        suffixText = null,
        suffix = null,
        intent = null;

  /// Numeric order-entry variant (quantity, price, leverage).
  UiInput.number({
    Key? key,
    TextEditingController? controller,
    String? hintText,
    String? value,
    ValueChanged<String>? onChanged,
    bool enabled = true,
    bool readOnly = false,
    UiValidationState validation = UiValidationState.none,
    UiInputVariant variant = UiInputVariant.outline,
    UiSize size = UiSize.md,
    UiDensity density = UiDensity.comfortable,
    String? prefixText,
    String? suffixText,
    Widget? trailing,
    bool decimals = true,
  }) : this(
          key: key,
          controller: controller,
          hintText: hintText,
          value: value,
          onChanged: onChanged,
          enabled: enabled,
          readOnly: readOnly,
          validation: validation,
          variant: variant,
          size: size,
          density: density,
          prefixText: prefixText,
          suffixText: suffixText,
          trailing: trailing,
          textAlign: TextAlign.end,
          keyboardType:
              TextInputType.numberWithOptions(decimal: decimals, signed: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(
              decimals ? RegExp(r'[0-9.\-]') : RegExp(r'[0-9\-]'),
            ),
          ],
        );

  final TextEditingController? controller;
  final String? hintText;
  final String? value;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Called after the clear affordance empties the field.
  final VoidCallback? onClear;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingTap;

  /// Arbitrary widget slots, e.g. a currency selector or unit toggle.
  final Widget? leading;
  final Widget? trailing;
  final bool obscure;
  final bool enabled;
  final bool readOnly;

  /// Legacy flag — equivalent to [UiValidationState.invalid].
  final bool error;
  final UiValidationState validation;
  final UiInputVariant variant;
  final UiDensity density;
  final UiSize size;
  final int maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final TextAlign textAlign;
  final bool autofocus;
  final FocusNode? focusNode;
  final int? maxLength;
  final bool showCounter;
  final bool clearable;

  /// Shows an inline spinner (async validation, symbol lookup).
  final bool loading;
  final String? prefixText;
  final String? suffixText;
  final Widget? suffix;

  /// Tints the focus ring and accents; defaults to the theme focus colour.
  final UiIntent? intent;
  final String? semanticLabel;

  /// When false the field hugs its content instead of filling the row.
  final bool expand;

  @override
  State<UiInput> createState() => _UiInputState();
}

class _UiInputState extends State<UiInput> {
  late TextEditingController _controller;
  late FocusNode _focus;
  bool _ownsFocus = false;
  bool _focused = false;
  bool _hovered = false;
  bool _obscured = true;

  UiValidationState get _validation => widget.error
      ? UiValidationState.invalid
      : widget.validation;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? TextEditingController(text: widget.value ?? '');
    _ownsFocus = widget.focusNode == null;
    _focus = widget.focusNode ?? FocusNode();
    _focus.addListener(_onFocus);
    _controller.addListener(_onText);
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = _focus.hasFocus);
  }

  void _onText() {
    if (mounted && (widget.clearable || widget.showCounter)) setState(() {});
  }

  @override
  void didUpdateWidget(UiInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null &&
        widget.value != null &&
        widget.value != _controller.text) {
      _controller.text = widget.value!;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onText);
    if (widget.controller == null) _controller.dispose();
    _focus.removeListener(_onFocus);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  Color _accent(BuildContext context) {
    final c = context.uiColors;
    switch (_validation) {
      case UiValidationState.invalid:
        return c.destructive;
      case UiValidationState.valid:
        return UiIntent.success.color(context);
      case UiValidationState.warning:
        return c.warning;
      case UiValidationState.none:
        return widget.intent?.color(context) ?? c.focusRing;
    }
  }

  IconData? get _validationIcon {
    switch (_validation) {
      case UiValidationState.invalid:
        return Icons.error_outline;
      case UiValidationState.valid:
        return Icons.check_circle_outline;
      case UiValidationState.warning:
        return Icons.warning_amber_rounded;
      case UiValidationState.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final c = theme.colors;
    final bool multiline = widget.maxLines > 1;
    final double f = widget.density.factor;
    final Color accent = _accent(context);
    final bool underline = widget.variant == UiInputVariant.underline;
    final BorderRadius radius = context.radius(
      underline ? theme.radii.none : theme.radii.lg,
    );

    Color background;
    Color borderColor;
    switch (widget.variant) {
      case UiInputVariant.filled:
        background = widget.enabled ? c.surfaceMuted : c.disabledBackground;
        borderColor = Colors.transparent;
        break;
      case UiInputVariant.ghost:
      case UiInputVariant.underline:
        background = Colors.transparent;
        borderColor = Colors.transparent;
        break;
      case UiInputVariant.outline:
        background = widget.enabled ? c.surface : c.disabledBackground;
        borderColor = _hovered ? c.borderStrong : c.border;
        break;
    }
    if (_validation != UiValidationState.none) borderColor = accent;
    if (_focused) borderColor = accent;

    final Widget field = AnimatedContainer(
      duration: theme.motion.fast,
      curve: theme.motion.curve,
      constraints: BoxConstraints(
        minHeight: multiline ? 0 : widget.size.height(context) * f,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: underline
            ? 0
            : context.sp(theme.spacing.md) * f,
        vertical: multiline ? context.sp(theme.spacing.md) * f : 0,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: underline
            ? Border(
                bottom: BorderSide(
                  color: borderColor == Colors.transparent
                      ? c.border
                      : borderColor,
                  width: _focused ? theme.borders.thick : theme.borders.hairline,
                ),
              )
            : Border.all(
                color: borderColor,
                width: _focused ? theme.borders.thick : theme.borders.hairline,
              ),
        boxShadow: _focused && !underline
            ? uiGlow(context, accent, alpha: 0.18)
            : null,
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: <Widget>[
          if (widget.leading != null) ...<Widget>[
            widget.leading!,
            SizedBox(width: context.sp(theme.spacing.sm)),
          ],
          if (widget.leadingIcon != null) ...<Widget>[
            Icon(
              widget.leadingIcon,
              size: widget.size.icon(context),
              color: _focused ? accent : c.foregroundSubtle,
            ),
            SizedBox(width: context.sp(theme.spacing.sm)),
          ],
          if (widget.prefixText != null) ...<Widget>[
            Text(
              widget.prefixText!,
              style: context.uiText.body.copyWith(color: c.foregroundMuted),
            ),
            SizedBox(width: context.sp(theme.spacing.xs)),
          ],
          if (widget.expand)
            Expanded(child: _textField(context, c))
          else
            Flexible(child: _textField(context, c)),
          if (widget.suffixText != null) ...<Widget>[
            SizedBox(width: context.sp(theme.spacing.xs)),
            Text(
              widget.suffixText!,
              style: context.uiText.body.copyWith(color: c.foregroundMuted),
            ),
          ],
          if (widget.showCounter && widget.maxLength != null) ...<Widget>[
            SizedBox(width: context.sp(theme.spacing.xs)),
            Text(
              '${_controller.text.characters.length}/${widget.maxLength}',
              style: context.uiText.caption.copyWith(
                color: _controller.text.characters.length >= widget.maxLength!
                    ? c.destructive
                    : c.foregroundSubtle,
              ),
            ),
          ],
          if (widget.suffix != null) ...<Widget>[
            SizedBox(width: context.sp(theme.spacing.xs)),
            widget.suffix!,
          ],
          if (widget.loading) ...<Widget>[
            SizedBox(width: context.sp(theme.spacing.xs)),
            SizedBox(
              width: widget.size.icon(context),
              height: widget.size.icon(context),
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
          ],
          if (widget.clearable &&
              _controller.text.isNotEmpty &&
              widget.enabled) ...<Widget>[
            SizedBox(width: context.sp(theme.spacing.xs)),
            UiInteractive(
              semanticLabel: 'Clear',
              onTap: () {
                _controller.clear();
                widget.onChanged?.call('');
                widget.onClear?.call();
                setState(() {});
              },
              builder: (_, _) => Icon(
                Icons.close,
                size: widget.size.icon(context),
                color: c.foregroundSubtle,
              ),
            ),
          ],
          if (widget.obscure)
            UiInteractive(
              semanticLabel: _obscured ? 'Show' : 'Hide',
              onTap: () => setState(() => _obscured = !_obscured),
              builder: (_, _) => Icon(
                _obscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: widget.size.icon(context),
                color: c.foregroundSubtle,
              ),
            )
          else if (widget.trailingIcon != null)
            UiInteractive(
              enabled: widget.onTrailingTap != null,
              onTap: widget.onTrailingTap,
              builder: (_, _) => Icon(
                widget.trailingIcon,
                size: widget.size.icon(context),
                color: c.foregroundSubtle,
              ),
            )
          else if (_validationIcon != null) ...<Widget>[
            SizedBox(width: context.sp(theme.spacing.xs)),
            Icon(_validationIcon, size: widget.size.icon(context), color: accent),
          ],
          if (widget.trailing != null) ...<Widget>[
            SizedBox(width: context.sp(theme.spacing.sm)),
            widget.trailing!,
          ],
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.enabled ? SystemMouseCursors.text : SystemMouseCursors.basic,
      child: Semantics(
        textField: true,
        label: widget.semanticLabel ?? widget.hintText,
        child: field,
      ),
    );
  }

  Widget _textField(BuildContext context, UiColors c) => TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        autofocus: widget.autofocus,
        obscureText: widget.obscure && _obscured,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        maxLength: widget.maxLength,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        textInputAction: widget.textInputAction,
        textAlign: widget.textAlign,
        scrollPadding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom + 112,
        ),
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        cursorColor: _accent(context),
        style: context.uiText.body.copyWith(
          color: widget.enabled ? c.foreground : c.disabledForeground,
        ),
        decoration: InputDecoration(
          isDense: true,
          counterText: '',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: widget.hintText,
          hintStyle:
              context.uiText.body.copyWith(color: c.foregroundSubtle),
        ),
      );
}
