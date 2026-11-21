import 'package:flutter/material.dart';
import 'home_page.dart';
import 'app_theme.dart';

void main() {
  runApp(const RingtoneApp());
}

class RingtoneApp extends StatelessWidget {
  const RingtoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '铃声制作',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomePage(),
    );
  }
}
