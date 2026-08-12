import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';
import 'ui_input.dart';

/// Dropdown select. Uses a bottom sheet on phones and an anchored menu on
/// larger screens — one API, responsive presentation.
class UiSelect<T> extends StatelessWidget {
  const UiSelect({
    super.key,
    required this.options,
    this.value,
    this.onChanged,
    this.hintText = 'Select',
    this.label,
    this.helperText,
    this.errorText,
    this.size = UiSize.md,
    this.density = UiDensity.comfortable,
    this.variant = UiInputVariant.outline,
    this.enabled = true,
    this.error = false,
    this.loading = false,
    this.multiple = false,
    this.values,
    this.maxVisibleChips,
    this.onValuesChanged,
    this.leadingIcon,
    this.searchable = false,
  });

  final List<UiOption<T>> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final String hintText;
  final String? label;
  final String? helperText;
  final String? errorText;
  final UiSize size;
  final UiDensity density;
  final UiInputVariant variant;
  final bool enabled;
  final bool error;
  final bool loading;
  final bool multiple;
  final List<T>? values;
  final int? maxVisibleChips;
  final ValueChanged<List<T>>? onValuesChanged;
  final IconData? leadingIcon;
  final bool searchable;

  UiOption<T>? get _selected {
    for (final UiOption<T> o in options) {
      if (o.value == value) return o;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    final T? picked = context.uiRes.isMobile
        ? await _showSheet(context)
        : await _showMenu(context);
    if (picked != null) onChanged?.call(picked);
  }

  Future<T?> _showSheet(BuildContext context) {
    final theme = context.ui;
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: theme.colors.surface,
      barrierColor: theme.colors.overlay,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.sz(theme.radii.xxl)),
        ),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.all(ctx.sp(theme.spacing.lg)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (label != null) ...<Widget>[
                Text(
                  label!,
                  style: ctx.uiText.heading
                      .copyWith(color: theme.colors.foreground),
                ),
                SizedBox(height: ctx.sp(theme.spacing.md)),
              ],
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (BuildContext c2, int i) => _UiSelectRow<T>(
                    option: options[i],
                    selected: options[i].value == value,
                    onTap: () => Navigator.of(c2).pop(options[i].value),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<T?> _showMenu(BuildContext context) {
    final theme = context.ui;
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset offset = box.localToGlobal(Offset.zero);
    return showMenu<T>(
      context: context,
      color: theme.colors.surface,
      elevation: 0,
      constraints: BoxConstraints(minWidth: box.size.width),
      shape: RoundedRectangleBorder(
        borderRadius: context.radius(theme.radii.lg),
        side: BorderSide(
          color: theme.colors.border,
          width: theme.borders.hairline,
        ),
      ),
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + box.size.height,
        offset.dx + box.size.width,
        offset.dy,
      ),
      items: <PopupMenuEntry<T>>[
        for (final UiOption<T> o in options)
          PopupMenuItem<T>(
            value: o.value,
            enabled: o.enabled,
            padding: EdgeInsets.zero,
            child: _UiSelectRow<T>(option: o, selected: o.value == value),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final c = theme.colors;
    final UiOption<T>? sel = _selected;

    return UiInteractive(
      enabled: enabled && onChanged != null,
      onTap: () => _open(context),
      semanticLabel: label ?? hintText,
      builder: (BuildContext ctx, UiInteractiveState s) => AnimatedContainer(
        duration: theme.motion.fast,
        height: size.height(ctx),
        padding: EdgeInsets.symmetric(horizontal: ctx.sp(theme.spacing.md)),
        decoration: BoxDecoration(
          color: enabled ? c.surface : c.disabledBackground,
          borderRadius: ctx.radius(theme.radii.lg),
          border: Border.all(
            color: error
                ? c.destructive
                : s.hovered
                    ? c.borderStrong
                    : c.border,
            width: theme.borders.hairline,
          ),
        ),
        child: Row(
          children: <Widget>[
            if (leadingIcon != null || sel?.icon != null) ...<Widget>[
              Icon(
                sel?.icon ?? leadingIcon,
                size: size.icon(ctx),
                color: c.foregroundMuted,
              ),
              SizedBox(width: ctx.sp(theme.spacing.sm)),
            ],
            Expanded(
              child: Text(
                sel?.label ?? hintText,
                overflow: TextOverflow.ellipsis,
                style: ctx.uiText.body.copyWith(
                  color: sel == null
                      ? c.foregroundSubtle
                      : enabled
                          ? c.foreground
                          : c.disabledForeground,
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: size.icon(ctx),
              color: c.foregroundSubtle,
            ),
          ],
        ),
      ),
    );
  }
}

class _UiSelectRow<T> extends StatelessWidget {
  const _UiSelectRow({required this.option, required this.selected, this.onTap});

  final UiOption<T> option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final c = theme.colors;
    return UiInteractive(
      enabled: option.enabled,
      onTap: onTap,
      builder: (BuildContext ctx, UiInteractiveState s) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: ctx.sp(theme.spacing.md),
          vertical: ctx.sp(theme.spacing.md),
        ),
        color: s.hovered ? c.surfaceHover : Colors.transparent,
        child: Row(
          children: <Widget>[
            if (option.icon != null) ...<Widget>[
              Icon(
                option.icon,
                size: ctx.sz(theme.sizes.iconMd),
                color: c.foregroundMuted,
              ),
              SizedBox(width: ctx.sp(theme.spacing.sm)),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    option.label,
                    style: ctx.uiText.body.copyWith(
                      color: option.enabled
                          ? c.foreground
                          : c.disabledForeground,
                    ),
                  ),
                  if (option.description != null)
                    Text(
                      option.description!,
                      style: ctx.uiText.caption
                          .copyWith(color: c.foregroundMuted),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check,
                size: ctx.sz(theme.sizes.iconSm),
                color: c.primary,
              ),
          ],
        ),
      ),
    );
  }
}
