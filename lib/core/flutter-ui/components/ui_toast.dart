import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';
import 'ui_toaster.dart';

/// Professional frosted-glass toast visual styled in the exact same design
/// language as the QuietNote pill dock (frosted translucent surface, hairline
/// border, soft ambient drop shadow, and modern status accents).
class UiToast extends StatelessWidget {
  const UiToast({
    super.key,
    required this.data,
    this.onDismiss,
    this.isExpanded = false,
  });

  final UiToastData data;
  final VoidCallback? onDismiss;
  final bool isExpanded;

  static void show(
    BuildContext context, {
    required String title,
    String? message,
    UiIntent intent = UiIntent.neutral,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) =>
      UiToastScope.of(context).show(
        UiToastData(
          title: title,
          message: message,
          intent: intent,
          icon: icon,
          actionLabel: actionLabel,
          onAction: onAction,
          duration: duration,
        ),
      );

  Color _intentColor(BuildContext context) {
    switch (data.intent) {
      case UiIntent.success:
      case UiIntent.bullish:
        return const Color(0xFF10B981);
      case UiIntent.warning:
        return const Color(0xFFF59E0B);
      case UiIntent.danger:
      case UiIntent.bearish:
        return const Color(0xFFEF4444);
      case UiIntent.primary:
      case UiIntent.info:
        return const Color(0xFF6366F1);
      case UiIntent.neutral:
        return Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF9CA3AF)
            : const Color(0xFF6B7280);
    }
  }

  IconData _defaultIcon() {
    if (data.icon != null) return data.icon!;
    switch (data.intent) {
      case UiIntent.success:
      case UiIntent.bullish:
        return Icons.check_circle_rounded;
      case UiIntent.warning:
        return Icons.warning_amber_rounded;
      case UiIntent.danger:
      case UiIntent.bearish:
        return Icons.error_rounded;
      case UiIntent.primary:
        return Icons.auto_awesome;
      case UiIntent.info:
      case UiIntent.neutral:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accentColor = _intentColor(context);
    final IconData icon = _defaultIcon();

    final Color bgColor = isDark
        ? const Color(0xDC1A1817)
        : theme.colors.surface.withValues(alpha: 0.88);

    final Color borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.08);

    final Color fgColor = isDark ? Colors.white : theme.colors.foreground;
    final Color fgMuted = isDark
        ? Colors.white.withValues(alpha: 0.70)
        : theme.colors.foregroundMuted;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 420,
          minWidth: 260,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 20,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
              if (data.intent != UiIntent.neutral)
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.12),
                  blurRadius: 16,
                  spreadRadius: -2,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: borderColor,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    // Status Icon Capsule with Glowing Ambient Tint
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor.withValues(alpha: 0.16),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: accentColor,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title and Message Column
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            data.title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: fgColor,
                              letterSpacing: -0.2,
                              decoration: TextDecoration.none,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (data.message != null && data.message!.trim().isNotEmpty) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              data.message!,
                              style: TextStyle(
                                fontSize: 12,
                                color: fgMuted,
                                height: 1.25,
                                decoration: TextDecoration.none,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (data.actionLabel != null) ...<Widget>[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          data.onAction?.call();
                          onDismiss?.call();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.40),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            data.actionLabel!,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: accentColor,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: onDismiss,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: fgMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
