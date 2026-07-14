import 'package:flutter/material.dart';

// both library actions use this neutral style so they stand out in either theme
abstract final class LibraryActionStyle {
  static const background = Color(0xff424242);
  static const foreground = Colors.white;
  static const double compactSize = 40;
  static const double compactTapTarget = 48;
}

class CompactLibraryAddSurface extends StatelessWidget {
  const CompactLibraryAddSurface({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: LibraryActionStyle.compactTapTarget,
    child: Center(
      child: Material(
        color: LibraryActionStyle.background,
        elevation: 2,
        shape: CircleBorder(),
        child: SizedBox.square(
          dimension: LibraryActionStyle.compactSize,
          child: Icon(
            Icons.add,
            color: LibraryActionStyle.foreground,
            size: 24,
          ),
        ),
      ),
    ),
  );
}
