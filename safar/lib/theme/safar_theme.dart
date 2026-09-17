import 'package:flutter/material.dart';
import 'safar_tokens.dart';

class SafarTheme {
  SafarTheme._();

  // Field / HUD Dark Theme (Default)
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SafarTokens.asphalt900,
      colorScheme: const ColorScheme.dark(
        primary: SafarTokens.hivis,
        onPrimary: SafarTokens.asphalt950,
        surface: SafarTokens.asphalt800,
        onSurface: SafarTokens.concrete50,
        surfaceContainerHighest: SafarTokens.asphalt700,
        outline: SafarTokens.asphalt600,
        error: SafarTokens.confLow,
        onError: SafarTokens.concrete50,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: SafarTokens.asphalt950,
        foregroundColor: SafarTokens.concrete50,
        elevation: 0,
        titleTextStyle: SafarTokens.fontUi(
          fontSize: 16.0,
          fontWeight: FontWeight.w700,
          color: SafarTokens.concrete50,
          letterSpacing: 0.05,
        ),
        iconTheme: const IconThemeData(color: SafarTokens.concrete50),
      ),
      cardTheme: CardThemeData(
        color: SafarTokens.asphalt800,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SafarTokens.rMd),
          side: const BorderSide(color: SafarTokens.asphalt600, width: 1.0),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: SafarTokens.asphalt600,
        thickness: 1.0,
        space: 1.0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SafarTokens.asphalt950,
        indicatorColor: SafarTokens.hivis.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return SafarTokens.fontUi(
              fontSize: 11.0,
              fontWeight: FontWeight.w700,
              color: SafarTokens.hivis,
            );
          }
          return SafarTokens.fontUi(
            fontSize: 11.0,
            fontWeight: FontWeight.w500,
            color: SafarTokens.asphalt400,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: SafarTokens.hivis, size: 22);
          }
          return const IconThemeData(color: SafarTokens.asphalt400, size: 22);
        }),
      ),
    );
  }

  // Desk / Dashboard Light Theme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: SafarTokens.concrete50,
      colorScheme: const ColorScheme.light(
        primary: SafarTokens.hivisDeep,
        onPrimary: SafarTokens.concrete50,
        surface: Colors.white,
        onSurface: SafarTokens.ink,
        surfaceContainerHighest: SafarTokens.concrete100,
        outline: SafarTokens.concrete200,
        error: SafarTokens.confLow,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: SafarTokens.concrete100,
        foregroundColor: SafarTokens.ink,
        elevation: 0,
        titleTextStyle: SafarTokens.fontUi(
          fontSize: 16.0,
          fontWeight: FontWeight.w700,
          color: SafarTokens.ink,
          letterSpacing: 0.05,
        ),
        iconTheme: const IconThemeData(color: SafarTokens.ink),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SafarTokens.rMd),
          side: const BorderSide(color: SafarTokens.concrete200, width: 1.0),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: SafarTokens.concrete200,
        thickness: 1.0,
        space: 1.0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SafarTokens.concrete100,
        indicatorColor: SafarTokens.hivisDeep.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return SafarTokens.fontUi(
              fontSize: 11.0,
              fontWeight: FontWeight.w700,
              color: SafarTokens.hivisDeep,
            );
          }
          return SafarTokens.fontUi(
            fontSize: 11.0,
            fontWeight: FontWeight.w500,
            color: SafarTokens.fgMute,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: SafarTokens.hivisDeep, size: 22);
          }
          return const IconThemeData(color: SafarTokens.fgMute, size: 22);
        }),
      ),
    );
  }
}
