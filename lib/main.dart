import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'home_page.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
