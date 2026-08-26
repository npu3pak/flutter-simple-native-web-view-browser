import 'package:flutter/material.dart';

import 'browser_demo_screen.dart';

void main() {
  runApp(const BrowserDemoApp());
}

class BrowserDemoApp extends StatelessWidget {
  const BrowserDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebView Browser Demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const BrowserDemoScreen(),
    );
  }
}
