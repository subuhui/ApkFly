import 'package:flutter/material.dart';

const appBackground = Color(0xfff6f7f4);
const appSurface = Color(0xffffffff);
const appInk = Color(0xff1f2725);
const appMuted = Color(0xff687370);
const appLine = Color(0xffdfe5df);
const appAccent = Color(0xff147d64);
const appWarning = Color(0xffb56b11);
const appDanger = Color(0xffb83b3b);

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: appAccent,
    brightness: Brightness.light,
    surface: appSurface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: appBackground,
    fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei', 'Arial'],
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: appInk,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: appInk,
      ),
      bodyMedium: TextStyle(fontSize: 14, color: appInk),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: appLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: appLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: appAccent, width: 1.4),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: appLine),
      ),
    ),
  );
}
