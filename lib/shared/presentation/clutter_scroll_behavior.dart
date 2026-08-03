import 'package:flutter/material.dart';

/// Applies clutter's compact scrollbar treatment to vertical scrollables.
class ClutterScrollBehavior extends MaterialScrollBehavior {
  const ClutterScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) == Axis.horizontal) {
      return child;
    }

    return RawScrollbar(
      controller: details.controller,
      thumbVisibility: false,
      trackVisibility: false,
      interactive: true,
      scrollbarOrientation: ScrollbarOrientation.left,
      thickness: 3,
      radius: const Radius.circular(2),
      minThumbLength: 28,
      mainAxisMargin: 6,
      crossAxisMargin: 3,
      thumbColor: Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: 0.24),
      child: child,
    );
  }
}
