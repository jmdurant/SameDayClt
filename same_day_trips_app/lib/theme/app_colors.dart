import 'package:flutter/material.dart';

/// Semantic color definitions for the app
/// These provide meaning-based colors rather than literal color names
class AppColors {
  // Semantic colors for success states (flights, locations, confirmations)
  static const Color successLight = Color(0xFF4CAF50);
  static const Color successDark = Color(0xFF66BB6A);

  // Semantic colors for warning/caution
  static const Color warningLight = Color(0xFFFFA726);
  static const Color warningDark = Color(0xFFFFB74D);

  // Semantic colors for errors/delete actions
  static const Color errorLight = Color(0xFFEF5350);
  static const Color errorDark = Color(0xFFE57373);

  // Semantic colors for information/primary actions
  static const Color infoLight = Color(0xFF2196F3);
  static const Color infoDark = Color(0xFF42A5F5);

  // Surface tints for backgrounds
  static const Color blueTintLight = Color(0xFFE3F2FD);
  static const Color blueTintDark = Color(0xFF1A237E);

  static const Color greenTintLight = Color(0xFFE8F5E9);
  static const Color greenTintDark = Color(0xFF1B5E20);

  static const Color purpleTintLight = Color(0xFFF3E5F5);
  static const Color purpleTintDark = Color(0xFF4A148C);

  static const Color orangeTintLight = Color(0xFFFFF3E0);
  static const Color orangeTintDark = Color(0xFFE65100);

  static const Color redTintLight = Color(0xFFFFEBEE);
  static const Color redTintDark = Color(0xFFB71C1C);

  // Text colors
  static const Color textPrimaryLight = Color(0xFF212121);
  static const Color textSecondaryLight = Color(0xFF757575);
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFFB0B0B0);

  // Border colors
  static const Color borderLight = Color(0xFFE0E0E0);
  static const Color borderDark = Color(0xFF424242);

  // Divider colors
  static const Color dividerLight = Color(0xFFBDBDBD);
  static const Color dividerDark = Color(0xFF616161);
}

/// Extension to get brightness-aware colors from BuildContext
extension ThemeColors on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  Color get successColor => isDarkMode ? AppColors.successDark : AppColors.successLight;
  Color get warningColor => isDarkMode ? AppColors.warningDark : AppColors.warningLight;
  Color get errorColor => isDarkMode ? AppColors.errorDark : AppColors.errorLight;
  Color get infoColor => isDarkMode ? AppColors.infoDark : AppColors.infoLight;

  Color get blueTint => isDarkMode ? AppColors.blueTintDark : AppColors.blueTintLight;
  Color get greenTint => isDarkMode ? AppColors.greenTintDark : AppColors.greenTintLight;
  Color get purpleTint => isDarkMode ? AppColors.purpleTintDark : AppColors.purpleTintLight;
  Color get orangeTint => isDarkMode ? AppColors.orangeTintDark : AppColors.orangeTintLight;
  Color get redTint => isDarkMode ? AppColors.redTintDark : AppColors.redTintLight;

  Color get textPrimary => isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
  Color get textSecondary => isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

  Color get borderColor => isDarkMode ? AppColors.borderDark : AppColors.borderLight;
  Color get dividerColor => isDarkMode ? AppColors.dividerDark : AppColors.dividerLight;

  // Lighter versions with opacity for container backgrounds
  Color get successTint => successColor.withOpacity(isDarkMode ? 0.2 : 0.1);
  Color get warningTint => warningColor.withOpacity(isDarkMode ? 0.2 : 0.1);
  Color get errorTint => errorColor.withOpacity(isDarkMode ? 0.2 : 0.1);
  Color get infoTint => infoColor.withOpacity(isDarkMode ? 0.2 : 0.1);

  // Helper for getting surface colors
  Color get surfaceColor => Theme.of(this).colorScheme.surface;
  Color get backgroundColor => Theme.of(this).colorScheme.background;
  Color get primaryColor => Theme.of(this).colorScheme.primary;
  Color get secondaryColor => Theme.of(this).colorScheme.secondary;
}
