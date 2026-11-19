import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData finsightTheme() {
  const colors = ColorScheme.dark(
    primary: FinsightColors.primary,
    onPrimary: FinsightColors.black,
    surface: FinsightColors.gray1000,
    onSurface: FinsightColors.white,
    error: FinsightColors.error,
  );

  return ThemeData(
    colorScheme: colors,
    fontFamily: FinsightTypography.family,
    scaffoldBackgroundColor: colors.surface,
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: FinsightColors.noticeSurface,
      contentTextStyle: TextStyle(color: FinsightColors.noticeText),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    textTheme: const TextTheme(
      displayLarge: FinsightTypography.displaySb38,
      displayMedium: FinsightTypography.displaySb28,
      displaySmall: FinsightTypography.displaySb22,
      titleLarge: FinsightTypography.titleSb18,
      titleMedium: FinsightTypography.titleM18,
      titleSmall: FinsightTypography.titleR18,
      bodyLarge: FinsightTypography.bodyR16,
      bodyMedium: FinsightTypography.bodyR14,
      labelLarge: FinsightTypography.bodySb16,
      labelMedium: FinsightTypography.labelM12,
      labelSmall: FinsightTypography.captionR10,
    ).apply(bodyColor: colors.onSurface, displayColor: colors.onSurface),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
