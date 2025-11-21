import 'package:flutter/material.dart';
import 'app_colors.dart';

/// App theme configurations for light and dark modes
class AppTheme {
  // Primary color for the app
  static const Color primaryColor = Color(0xFF2196F3); // Blue
  static const Color primaryColorDark = Color(0xFF1976D2);

  // Secondary/accent color
  static const Color secondaryColor = Color(0xFF4CAF50); // Green
  static const Color secondaryColorDark = Color(0xFF388E3C);

  /// Light theme configuration
  static ThemeData lightTheme() {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      primary: primaryColor,
      secondary: secondaryColor,
      error: AppColors.errorLight,
      background: const Color(0xFFFAFAFA),
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,

      // AppBar theme
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.inversePrimary,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),

      // Card theme
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: Colors.white,
      ),

      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),

      // Icon button theme
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
        ),
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      // Divider theme
      dividerTheme: DividerThemeData(
        color: AppColors.dividerLight,
        thickness: 1,
        space: 1,
      ),

      // Snackbar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // Text theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimaryLight),
        displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimaryLight),
        displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimaryLight),
        headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimaryLight),
        headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimaryLight),
        headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimaryLight),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.textPrimaryLight),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textPrimaryLight),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimaryLight),
        bodyLarge: TextStyle(fontSize: 16, color: AppColors.textPrimaryLight),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.textPrimaryLight),
        bodySmall: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimaryLight),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimaryLight),
        labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textSecondaryLight),
      ),
    );
  }

  /// Dark theme configuration
  static ThemeData darkTheme() {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColorDark,
      brightness: Brightness.dark,
      primary: primaryColorDark,
      secondary: secondaryColorDark,
      error: AppColors.errorDark,
      background: const Color(0xFF121212),
      surface: const Color(0xFF1E1E1E),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,

      // AppBar theme
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),

      // Card theme
      cardTheme: CardThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: const Color(0xFF2C2C2C),
      ),

      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColorDark,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),

      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColorDark,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),

      // Icon button theme
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
        ),
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2C2C2C),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: primaryColorDark, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      // Divider theme
      dividerTheme: DividerThemeData(
        color: AppColors.dividerDark,
        thickness: 1,
        space: 1,
      ),

      // Snackbar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // Text theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimaryDark),
        displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimaryDark),
        displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimaryDark),
        headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark),
        headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark),
        headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.textPrimaryDark),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textPrimaryDark),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimaryDark),
        bodyLarge: TextStyle(fontSize: 16, color: AppColors.textPrimaryDark),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.textPrimaryDark),
        bodySmall: TextStyle(fontSize: 12, color: AppColors.textSecondaryDark),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimaryDark),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimaryDark),
        labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textSecondaryDark),
      ),
    );
  }
}
