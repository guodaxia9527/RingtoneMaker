import 'package:flutter/material.dart';

const editorBlue = Color(0xFF087EFF);
const editorRed = Color(0xFFE44842);
const editorGreen = Color(0xFF87A437);
const editorBackground = Color(0xFFF3F4F6);

ThemeData buildAppTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: editorBackground,
  colorScheme: ColorScheme.fromSeed(
    seedColor: editorGreen,
    primary: editorGreen,
    surface: editorBackground,
    onSurface: const Color(0xFF161918),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: editorBackground,
    surfaceTintColor: Colors.transparent,
    centerTitle: true,
    elevation: 0,
    foregroundColor: Colors.black,
    titleTextStyle: TextStyle(
      color: Colors.black,
      fontSize: 21,
      fontWeight: FontWeight.w700,
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: Colors.black,
      disabledForegroundColor: const Color(0xFFA3A6A9),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: editorGreen,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: editorBackground,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: editorBackground,
    modalBackgroundColor: editorBackground,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
  ),
  dividerTheme: const DividerThemeData(color: Color(0xFFE0E2E4), thickness: .7),
  progressIndicatorTheme: const ProgressIndicatorThemeData(color: editorGreen),
  sliderTheme: const SliderThemeData(
    activeTrackColor: editorGreen,
    inactiveTrackColor: Color(0xFFDCDFD8),
    thumbColor: editorGreen,
  ),
);
