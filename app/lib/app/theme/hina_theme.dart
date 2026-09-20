import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'hina_colors.dart';

abstract final class HinaSpace {
  static const xs = 4.0, s = 8.0, m = 16.0, l = 24.0, xl = 32.0;
}

abstract final class HinaRadius {
  static const card = 20.0, button = 28.0, chip = 12.0, sheet = 28.0;
}

abstract final class HinaShadow {
  static const card = [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4))];
}

/// Typography scale (Noto Sans JP): display 28/B, title 20/B, body 16, caption 13, label 14/M.
class HinaText {
  static TextTheme textTheme(TextTheme base) {
    final t = GoogleFonts.notoSansJpTextTheme(base);
    return t.copyWith(
      displaySmall: t.displaySmall?.copyWith(fontSize: 28, fontWeight: FontWeight.w700, color: HinaColors.ink, height: 1.3),
      titleLarge: t.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: HinaColors.ink, height: 1.3),
      titleMedium: t.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: HinaColors.ink),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 16, color: HinaColors.ink, height: 1.6),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, color: HinaColors.ink, height: 1.6),
      bodySmall: t.bodySmall?.copyWith(fontSize: 13, color: HinaColors.inkSub, height: 1.5),
      labelLarge: t.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: HinaColors.ink),
    );
  }
}

ThemeData hinaTheme() {
  final base = ThemeData.light(useMaterial3: true);
  final scheme = ColorScheme.fromSeed(
    seedColor: HinaColors.sky,
    primary: HinaColors.sky,
    secondary: HinaColors.sun,
    surface: HinaColors.surface,
    error: HinaColors.alert,
    brightness: Brightness.light,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: HinaColors.bg,
    textTheme: HinaText.textTheme(base.textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: HinaColors.bg,
      foregroundColor: HinaColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.notoSansJp(fontSize: 20, fontWeight: FontWeight.w700, color: HinaColors.ink),
    ),
    dividerColor: HinaColors.line,
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: HinaColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(HinaRadius.sheet))),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? HinaColors.sky : HinaColors.line),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: HinaColors.surface,
      indicatorColor: HinaColors.mist,
      labelTextStyle: WidgetStateProperty.all(GoogleFonts.notoSansJp(fontSize: 11, color: HinaColors.inkSub)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? HinaColors.sky : HinaColors.inkSub)),
    ),
  );
}
