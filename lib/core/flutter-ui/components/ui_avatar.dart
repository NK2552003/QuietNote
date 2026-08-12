import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

/// Avatar with initials fallback, presence dot and stacked group variant.
class UiAvatar extends StatelessWidget {
  const UiAvatar({
    super.key,
    this.imageUrl,
    this.name = '',
    this.size = UiSize.md,
    this.online = false,
    this.verified = false,
    this.onTap,
  });

  final String? imageUrl;
  final String name;
  final UiSize size;
  final bool online;
  final bool verified;
  final VoidCallback? onTap;

  double _dim(BuildContext context) => size.avatar(context);

  String get _initials {
    final List<String> parts =
        name.trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final double dim = _dim(context);
    Widget avatar = Container(
      width: dim,
      height: dim,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colors.surfaceMuted,
        border: Border.all(
          color: theme.colors.border,
          width: theme.borders.hairline,
        ),
        image: (imageUrl == null || imageUrl!.isEmpty)
            ? null
            : DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
                onError: (Object error, StackTrace? stackTrace) {},
              ),
      ),
      alignment: Alignment.center,
      child: imageUrl == null
          ? Text(
              _initials,
              style: context.uiText.label
                  .copyWith(color: theme.colors.foregroundMuted),
            )
          : null,
    );

    if (online || verified) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          avatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dim * 0.3,
              height: dim * 0.3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online ? theme.colors.bullish : theme.colors.primary,
                border: Border.all(
                  color: theme.colors.surface,
                  width: theme.borders.thick,
                ),
              ),
              child: verified && !online
                  ? Icon(
                      Icons.check,
                      size: dim * 0.16,
                      color: theme.colors.onPrimary,
                    )
                  : null,
            ),
          ),
        ],
      );
    }

    if (onTap == null) return avatar;
    return UiInteractive(onTap: onTap, builder: (_, _) => avatar);
  }
}

/// Overlapping avatar stack ("+12 traders following").
class UiAvatarGroup extends StatelessWidget {
  const UiAvatarGroup({
    super.key,
    required this.avatars,
    this.max = 4,
    this.size = UiSize.sm,
  });

  final List<UiAvatar> avatars;
  final int max;
  final UiSize size;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final List<UiAvatar> shown = avatars.take(max).toList();
    final int overflow = avatars.length - shown.length;
    final double dim = size == UiSize.sm
        ? context.sz(theme.sizes.avatarSm)
        : context.sz(theme.sizes.avatarMd);
    final double overlap = dim * 0.35;

    return SizedBox(
      height: dim,
      child: Stack(
        children: <Widget>[
          for (int i = 0; i < shown.length; i++)
            Positioned(
              left: i * (dim - overlap),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colors.surface,
                    width: theme.borders.thick,
                  ),
                ),
                child: shown[i],
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: shown.length * (dim - overlap),
              child: Container(
                width: dim,
                height: dim,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colors.surfaceMuted,
                  border: Border.all(
                    color: theme.colors.surface,
                    width: theme.borders.thick,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$overflow',
                  style: context.uiText.caption
                      .copyWith(color: theme.colors.foregroundMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
