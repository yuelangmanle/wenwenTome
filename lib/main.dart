import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '文文Tome',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('文文Tome - 跨端电子书阅读器\n版本: 0.1.0-MVP',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24)),
        ),
      ),
    );
  }
}
