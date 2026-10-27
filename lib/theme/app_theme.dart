import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:med_ad_app/provider/local_provider.dart';

/// Colours of the Dawai patient app (calm purple theme).
class AppColors {
  static const primary = Color(0xFF5B47A6);
  static const primaryDark = Color(0xFF463687);
  static const primaryTint = Color(0xFFEFECF8);
  static const background = Color(0xFFF3F6F8);
  static const surface = Colors.white;
  static const border = Color(0xFFE8EEF1);
  static const text = Color(0xFF14212B);
  static const textMuted = Color(0xFF4F5F6B);
  static const grey = Color(0xFFEEF2F5);

  static const success = Color(0xFF15803D);
  static const successTint = Color(0xFFE5F5EA);
  static const warning = Color(0xFFB45309);
  static const warningText = Color(0xFF9A4A00);
  static const warningTint = Color(0xFFFFF4E5);
  static const danger = Color(0xFFB42318);
  static const dangerTint = Color(0xFFFBEAEA);
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
    );
    final radius = BorderRadius.circular(14);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

/// White rounded card used across the app.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: 2),
      ),
      child: child,
    );
  }
}

/// Section title such as "جدول اليوم".
class SectionTitle extends StatelessWidget {
  final String text;
  final String? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text)),
          ),
          if (trailing != null)
            Text(trailing!,
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

/// Chooses the Arabic or English text for the current app language.
String tr(BuildContext context, String ar, String en, {bool listen = true}) {
  final lang = Provider.of<LocaleProvider>(context, listen: listen).currentLanguage;
  return lang == 'en' ? en : ar;
}

bool isArabic(BuildContext context) =>
    Provider.of<LocaleProvider>(context).currentLanguage != 'en';
