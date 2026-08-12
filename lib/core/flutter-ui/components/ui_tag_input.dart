import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_badge.dart';
import 'ui_common.dart';
import 'ui_input.dart';

/// Chip-based tag entry (journal tags, ticker tags, post cashtags).
class UiTagInput extends StatefulWidget {
  const UiTagInput({
    super.key,
    required this.tags,
    required this.onChanged,
    this.hintText = 'Add a tag',
    this.suggestions = const <String>[],
    this.maxTags,
    this.prefix,
    this.intent = UiIntent.primary,
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final String hintText;
  final List<String> suggestions;
  final int? maxTags;

  /// Prepended to every tag when rendered (e.g. `#` or `\$`).
  final String? prefix;
  final UiIntent intent;

  @override
  State<UiTagInput> createState() => _UiTagInputState();
}

class _UiTagInputState extends State<UiTagInput> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final String tag = raw.trim().replaceAll(RegExp(r'^[#\$]'), '');
    if (tag.isEmpty) return;
    if (widget.tags.contains(tag)) return;
    if (widget.maxTags != null && widget.tags.length >= widget.maxTags!) return;
    widget.onChanged(<String>[...widget.tags, tag]);
    _controller.clear();
  }

  void _remove(String tag) =>
      widget.onChanged(widget.tags.where((String t) => t != tag).toList());

  @override
  Widget build(BuildContext context) {
    final UiTheme theme = context.ui;
    final List<String> unused = widget.suggestions
        .where((String s) => !widget.tags.contains(s))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.tags.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: context.sp(theme.spacing.sm)),
            child: Wrap(
              spacing: context.sp(theme.spacing.xs),
              runSpacing: context.sp(theme.spacing.xs),
              children: <Widget>[
                for (final String tag in widget.tags)
                  UiInteractive(
                    onTap: () => _remove(tag),
                    builder: (BuildContext ctx, UiInteractiveState _) =>
                        Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ctx.sp(theme.spacing.sm),
                        vertical: ctx.sp(theme.spacing.xxs),
                      ),
                      decoration: BoxDecoration(
                        color: widget.intent.surface(ctx),
                        borderRadius: ctx.radius(theme.radii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            '${widget.prefix ?? ''}$tag',
                            style: ctx.uiText.label
                                .copyWith(color: widget.intent.color(ctx)),
                          ),
                          SizedBox(width: ctx.sp(theme.spacing.xxs)),
                          Icon(
                            Icons.close_rounded,
                            size: ctx.sz(theme.sizes.iconSm),
                            color: widget.intent.color(ctx),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        UiInput(
          controller: _controller,
          hintText: widget.hintText,
          leadingIcon: Icons.sell_outlined,
          onSubmitted: _add,
          textInputAction: TextInputAction.done,
        ),
        if (unused.isNotEmpty) ...<Widget>[
          SizedBox(height: context.sp(theme.spacing.sm)),
          Wrap(
            spacing: context.sp(theme.spacing.xs),
            runSpacing: context.sp(theme.spacing.xs),
            children: <Widget>[
              for (final String s in unused)
                UiBadge(
                  label: '${widget.prefix ?? ''}$s',
                  icon: Icons.add,
                  intent: UiIntent.neutral,
                  onTap: () => _add(s),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
