import 'package:flutter/foundation.dart';

bool get isDesktopPlatform =>
    !kIsWeb &&
    const {
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }.contains(defaultTargetPlatform);

bool get usesMacPrimaryModifier =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
