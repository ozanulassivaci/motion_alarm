import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import 'theme/night_theme.dart';

class MotionAlarmApp extends StatelessWidget {
  const MotionAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Motion Alarm',
      theme: nightTheme,
      home: const HomeScreen(),
    );
  }
}
