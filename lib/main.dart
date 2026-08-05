import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
