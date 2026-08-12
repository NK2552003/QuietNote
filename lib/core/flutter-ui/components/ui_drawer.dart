import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_icon_button.dart';

/// Side drawer (filters, account panel). Full-height sheet on phones.
class UiDrawer extends StatelessWidget {
  const UiDrawer({
    super.key,
    required this.title,
    required this.child,
    this.footer,
  });

  final String title;
  final Widget child;
  final Widget? footer;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget child,
    Widget? footer,
    bool fromRight = true,
  }) {
    final theme = context.ui;
    final bool mobile = context.uiRes.isMobile;
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: theme.colors.overlay,
      transitionDuration: theme.motion.normal,
      pageBuilder: (BuildContext ctx, _, _) => Align(
        alignment: mobile
            ? Alignment.bottomCenter
            : (fromRight ? Alignment.centerRight : Alignment.centerLeft),
        child: SizedBox(
          width: mobile ? double.infinity : ctx.sz(420),
          height: mobile ? ctx.uiRes.height * 0.9 : double.infinity,
          child: Material(
            color: theme.colors.surface,
            child: SafeArea(
              child: UiDrawer(title: title, footer: footer, child: child),
            ),
          ),
        ),
      ),
      transitionBuilder: (BuildContext ctx, Animation<double> anim, _,
              Widget child) =>
          SlideTransition(
        position: Tween<Offset>(
          begin: mobile
              ? const Offset(0, 1)
              : Offset(fromRight ? 1 : -1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: theme.motion.curve)),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: context.uiText.heading
                      .copyWith(color: theme.colors.foreground),
                ),
              ),
              UiIconButton(
                icon: Icons.close,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Container(height: theme.borders.hairline, color: theme.colors.border),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
            child: child,
          ),
        ),
        if (footer != null) ...<Widget>[
          Container(height: theme.borders.hairline, color: theme.colors.border),
          Padding(
            padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
            child: footer!,
          ),
        ],
      ],
    );
  }
}
