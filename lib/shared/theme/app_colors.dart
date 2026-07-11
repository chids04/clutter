import 'package:flutter/material.dart';

class AppColors {
  // chatgpt-style dark theme (but a shade darker)
  static const darkBackground = Color(0xFF0D0D0D); // almost black app canvas
  static const darkSurface = Color(
    0xFF171717,
  ); // a little lighter so cards separate from the canvas
  static const darkSurfaceSecondary = Color(0xFF212121);
  static const darkBorder = Color(0xFF262626); // quiet border between surfaces
  static const darkDivider = Color(0xFF262626);

  static const textPrimary = Color(0xFFECECEC); // softer than pure white
  static const textSecondary = Color(
    0xFFB4B4B4,
  ); // use this when the text should not compete for attention

  static const accent = Color(0xFF71717A); // zinc-500
  static const errorRed = Color(0xFFEF4444);
}
