import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'core/theme.dart';
import 'pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const HyflixApp());
}

class HyflixApp extends StatelessWidget {
  const HyflixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HYFLIX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomePage(),
    );
  }
}
