import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

class UiTrackerBlock {
  const UiTrackerBlock({required this.intent, this.tooltip});

  final UiIntent intent;
  final String? tooltip;
}

/// Uptime/streak tracker (e.g. daily trading streak, signal accuracy history).
class UiTracker extends StatelessWidget {
  const UiTracker({super.key, required this.blocks, this.height});

  final List<UiTrackerBlock> blocks;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return SizedBox(
      height: context.sz(height ?? 28),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < blocks.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: context.sz(1)),
                child: Tooltip(
                  message: blocks[i].tooltip ?? '',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: blocks[i].intent.color(context),
                      borderRadius: context.radius(theme.radii.sm),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
