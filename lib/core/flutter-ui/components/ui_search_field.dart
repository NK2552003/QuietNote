import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';
import 'ui_input.dart';

/// One suggestion row in a [UiSearchField] dropdown.
@immutable
class UiSearchSuggestion {
  const UiSearchSuggestion({
    required this.id,
    required this.label,
    this.subtitle,
    this.icon,
    this.trailing,
    this.group,
  });

  final String id;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final String? trailing;
  final String? group;
}

/// Search field with clear button, recent/suggestion dropdown and keyboard
/// submit. Used for global search, ticker search and in-list filtering.
class UiSearchField extends StatefulWidget {
  const UiSearchField({
    super.key,
    this.hintText = 'Search',
    this.value,
    this.onChanged,
    this.onSubmitted,
    this.suggestions = const <UiSearchSuggestion>[],
    this.onSuggestionTap,
    this.autofocus = false,
    this.size = UiSize.md,
    this.loading = false,
  });

  final String hintText;
  final String? value;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<UiSearchSuggestion> suggestions;
  final ValueChanged<UiSearchSuggestion>? onSuggestionTap;
  final bool autofocus;
  final UiSize size;
  final bool loading;

  @override
  State<UiSearchField> createState() => _UiSearchFieldState();
}

class _UiSearchFieldState extends State<UiSearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value ?? '');
  bool _focused = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final UiTheme theme = context.ui;
    final bool showSuggestions =
        _focused && widget.suggestions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Focus(
          onFocusChange: (bool v) => setState(() => _focused = v),
          child: UiInput(
            controller: _controller,
            leadingIcon: Icons.search,
            textInputAction: TextInputAction.search,
            hintText: widget.hintText,
            autofocus: widget.autofocus,
            size: widget.size,
            onChanged: (String v) {
              setState(() {});
              widget.onChanged?.call(v);
            },
            onSubmitted: widget.onSubmitted,
            trailingIcon:
                _controller.text.isEmpty ? null : Icons.close_rounded,
            onTrailingTap: () {
              _controller.clear();
              widget.onChanged?.call('');
              setState(() {});
            },
          ),
        ),
        if (widget.loading) ...<Widget>[
          SizedBox(height: context.sp(theme.spacing.xs)),
          LinearProgressIndicator(
            minHeight: context.sz(2),
            backgroundColor: theme.colors.surfaceMuted,
            color: theme.colors.primary,
          ),
        ],
        if (showSuggestions) ...<Widget>[
          SizedBox(height: context.sp(theme.spacing.sm)),
          Container(
            decoration: BoxDecoration(
              color: theme.colors.surface,
              borderRadius: context.radius(theme.radii.lg),
              border: Border.all(
                color: theme.colors.border,
                width: theme.borders.hairline,
              ),
              boxShadow: theme.shadows.sm,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final UiSearchSuggestion s in widget.suggestions)
                  UiInteractive(
                    onTap: () => widget.onSuggestionTap?.call(s),
                    builder: (BuildContext ctx, UiInteractiveState st) =>
                        Container(
                      color: st.hovered
                          ? theme.colors.surfaceHover
                          : Colors.transparent,
                      padding: EdgeInsets.symmetric(
                        horizontal: ctx.sp(theme.spacing.md),
                        vertical: ctx.sp(theme.spacing.sm),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            s.icon ?? Icons.search,
                            size: ctx.sz(theme.sizes.iconMd),
                            color: theme.colors.foregroundMuted,
                          ),
                          SizedBox(width: ctx.sp(theme.spacing.sm)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(s.label, style: ctx.uiText.bodyStrong),
                                if (s.subtitle != null)
                                  Text(
                                    s.subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ctx.uiText.caption.copyWith(
                                      color: theme.colors.foregroundMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (s.trailing != null)
                            Text(
                              s.trailing!,
                              style: ctx.uiText.numeric.copyWith(
                                fontSize: ctx.uiText.caption.fontSize,
                                color: theme.colors.foregroundMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
