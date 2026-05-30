import 'package:flutter/material.dart';
import 'services/media_init.dart';
import 'core/theme.dart';
import 'pages/splash_page.dart';
import 'pages/auth_page.dart';
import 'services/auth_service.dart';
import 'services/download_service.dart';

import 'services/api_service.dart';
import 'services/watchlist_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ensureMediaKitInitialized();
  await ApiService.init();
  await WatchlistService().init();
  await DownloadService().init();
  await AuthService.init();
  runApp(const HyflixApp());
}

class HyflixApp extends StatefulWidget {
  const HyflixApp({super.key});

  @override
  State<HyflixApp> createState() => _HyflixAppState();
}

class _HyflixAppState extends State<HyflixApp> {
  bool _isLoggedIn = AuthService.isLoggedIn;

  @override
  void initState() {
    super.initState();
    AuthService.addAuthListener((loggedIn) {
      if (mounted) setState(() => _isLoggedIn = loggedIn);
    });
  }

  @override
  void dispose() {
    AuthService.removeAuthListener((loggedIn) {
      if (mounted) setState(() => _isLoggedIn = loggedIn);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HYFLIX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: _isLoggedIn ? const SplashPage() : const AuthPage(),
    );
  }
}
