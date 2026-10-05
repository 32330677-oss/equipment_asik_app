import 'package:flutter/material.dart';

/// Design tokens of Equipment Flow (company identity: navy + gold).
class AppColors {
  static const navy = Color(0xFF1A2A6C);
  static const navyDark = Color(0xFF111C4A);
  static const gold = Color(0xFFB8963E);
  static const ink = Color(0xFF1F2430);
  static const muted = Color(0xFF6B7280);
  static const line = Color(0xFFE5E7EB);
  static const surface = Color(0xFFF5F6FA);
  static const card = Colors.white;

  // states (always shown with a text label too)
  static const working = Color(0xFF2E8B57);
  static const onBreak = Color(0xFF5B6B8C);
  static const breakdown = Color(0xFFC0392B);
  static const standby = Color(0xFFD48A00);
  static const neutral = Color(0xFF9AA0AB);
  static const info = Color(0xFF2563EB);
  /// Rows changed by an Admin after approval.
  static const edited = Color(0xFF7C3AED);
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      primary: AppColors.navy,
      secondary: AppColors.gold,
      surface: Colors.white,
      brightness: Brightness.light,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Cairo');
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.line)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.navy, width: 1.6)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          side: const BorderSide(color: AppColors.line),
          textStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: const BorderSide(color: AppColors.line),
        labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.navyDark,
        selectedIconTheme: IconThemeData(color: Colors.white),
        unselectedIconTheme: IconThemeData(color: Color(0xFFB9C1DC)),
        selectedLabelTextStyle: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelTextStyle: TextStyle(fontFamily: 'Cairo', color: Color(0xFFB9C1DC), fontSize: 13),
        indicatorColor: Color(0x33FFFFFF),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F3F9)),
        headingTextStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 13),
        dataTextStyle: const TextStyle(fontFamily: 'Cairo', color: AppColors.ink, fontSize: 13),
      ),
    );
  }
}

/// Colour + label for a machine live state.
class StateStyle {
  const StateStyle(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;

  static StateStyle of(String state) {
    switch (state) {
      case 'Working':
        return const StateStyle('Working', AppColors.working, Icons.play_circle_fill_rounded);
      case 'OnBreak':
        return const StateStyle('On break', AppColors.onBreak, Icons.coffee_rounded);
      case 'Breakdown':
        return const StateStyle('Breakdown', AppColors.breakdown, Icons.build_circle_rounded);
      case 'Standby':
        return const StateStyle('Standby', AppColors.standby, Icons.pause_circle_filled_rounded);
      case 'Finished':
        return const StateStyle('Finished', AppColors.neutral, Icons.check_circle_rounded);
      case 'Absent':
        return const StateStyle('Absent', AppColors.neutral, Icons.remove_circle_rounded);
      case 'Holiday':
        return const StateStyle('Holiday', AppColors.neutral, Icons.beach_access_rounded);
      default:
        return const StateStyle('Not arrived', AppColors.breakdown, Icons.schedule_rounded);
    }
  }
}
