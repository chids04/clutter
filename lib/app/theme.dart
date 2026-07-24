import 'package:flutter/material.dart';

import 'package:clutter/shared/theme/app_colors.dart';

final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.darkBackground,
  canvasColor: AppColors.darkBackground,
  cardColor: AppColors.darkSurface,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.darkBackground,
    foregroundColor: AppColors.textPrimary,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    iconTheme: IconThemeData(color: AppColors.textPrimary),
    actionsIconTheme: IconThemeData(color: AppColors.textPrimary),
    titleTextStyle: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
  ),
  iconTheme: const IconThemeData(color: AppColors.textPrimary),
  primaryIconTheme: const IconThemeData(color: AppColors.textPrimary),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: AppColors.darkBackground,
    selectedItemColor: AppColors.textPrimary,
    unselectedItemColor: Color(0xFF8A8A8A),
    elevation: 0,
    type: BottomNavigationBarType.fixed,
  ),
  dividerTheme: const DividerThemeData(
    color: AppColors.darkDivider,
    thickness: 1,
    space: 1,
  ),
  colorScheme: const ColorScheme.dark(
    surface: AppColors.darkSurface,
    onSurface: AppColors.textPrimary,
    primary: AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.darkSurfaceSecondary,
    onSecondary: AppColors.textPrimary,
    error: AppColors.errorRed,
  ),
  listTileTheme: const ListTileThemeData(
    textColor: AppColors.textPrimary,
    iconColor: AppColors.textPrimary,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.darkSurfaceSecondary,
      foregroundColor: AppColors.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 0,
    ),
  ),
  splashFactory: NoSplash.splashFactory,
  highlightColor: Colors.transparent,
  splashColor: Colors.transparent,
);
