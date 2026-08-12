import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_button.dart';
import 'ui_common.dart';

class UiDialog extends StatelessWidget {
  const UiDialog({
    super.key,
    required this.title,
    this.description,
    this.content,
    this.actions = const <Widget>[],
    this.icon,
    this.intent = UiIntent.primary,
  });

  final String title;
  final String? description;
  final Widget? content;
  final List<Widget> actions;
  final IconData? icon;
  final UiIntent intent;

  /// Shows the dialog; a bottom sheet on phones, centered modal otherwise.
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    bool dismissible = true,
  }) {
    final theme = context.ui;
    if (context.uiRes.isMobile) {
      return showModalBottomSheet<T>(
        context: context,
        isDismissible: dismissible,
        isScrollControlled: true,
        backgroundColor: theme.colors.surface,
        barrierColor: theme.colors.overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.sz(theme.radii.xxl)),
          ),
        ),
        builder: (BuildContext ctx) => SafeArea(
          child: Padding(
            padding: EdgeInsets.all(ctx.sp(theme.spacing.lg)),
            child: child,
          ),
        ),
      );
    }
    return showDialog<T>(
      context: context,
      barrierDismissible: dismissible,
      barrierColor: theme.colors.overlay,
      builder: (BuildContext ctx) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ctx.sz(480)),
          child: Material(
            color: theme.colors.surface,
            borderRadius: ctx.radius(theme.radii.xl),
            child: Padding(
              padding: EdgeInsets.all(ctx.sp(theme.spacing.xl)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// Convenience confirm dialog (e.g. "Close position?").
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? description,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    UiVariant confirmVariant = UiVariant.primary,
  }) async {
    final bool? result = await show<bool>(
      context,
      child: Builder(
        builder: (BuildContext ctx) => UiDialog(
          title: title,
          description: description,
          actions: <Widget>[
            UiButton(
              label: cancelLabel,
              variant: UiVariant.secondary,
              expandOnMobile: false,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            UiButton(
              label: confirmLabel,
              variant: confirmVariant,
              expandOnMobile: false,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Container(
                padding: EdgeInsets.all(context.sp(theme.spacing.sm)),
                decoration: BoxDecoration(
                  color: intent.surface(context),
                  borderRadius: context.radius(theme.radii.md),
                ),
                child: Icon(
                  icon,
                  color: intent.color(context),
                  size: context.sz(theme.sizes.iconMd),
                ),
              ),
              SizedBox(width: context.sp(theme.spacing.md)),
            ],
            Expanded(
              child: Text(
                title,
                style: context.uiText.heading
                    .copyWith(color: theme.colors.foreground),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Icon(
                Icons.close,
                size: context.sz(theme.sizes.iconMd),
                color: theme.colors.foregroundSubtle,
              ),
            ),
          ],
        ),
        if (description != null) ...<Widget>[
          SizedBox(height: context.sp(theme.spacing.sm)),
          Text(
            description!,
            style: context.uiText.body
                .copyWith(color: theme.colors.foregroundMuted),
          ),
        ],
        if (content != null) ...<Widget>[
          SizedBox(height: context.sp(theme.spacing.lg)),
          content!,
        ],
        if (actions.isNotEmpty) ...<Widget>[
          SizedBox(height: context.sp(theme.spacing.xl)),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: context.sp(theme.spacing.sm),
            runSpacing: context.sp(theme.spacing.sm),
            children: actions,
          ),
        ],
      ],
    );
  }
}
