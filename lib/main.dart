import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'features/shopping/presentation/screens/home_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: OptiyoApp(),
    ),
  );
}

class OptiyoApp extends StatelessWidget {
  const OptiyoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Optiyo v12.8',
      theme: AppTheme.lightTheme,
      home: const HomeScreen(),
    );
  }
}
