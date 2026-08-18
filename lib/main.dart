import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'desktop_init.dart';
import 'services/media_init.dart';
import 'core/theme.dart';
import 'pages/splash_page.dart';
import 'pages/auth_page.dart';
import 'services/auth_service.dart';
import 'services/download_service.dart';

import 'services/api_service.dart';
import 'services/watchlist_service.dart';

final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

/// Custom HttpOverrides to handle legacy Android (e.g. Android 6.0 Marshmallow / Lumos Projector)
/// where modern Root CA certificates (like Let's Encrypt ISRG Root X1) may be outdated or missing.
class _HyflixHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    HttpOverrides.global = _HyflixHttpOverrides();
  }

  // Force traditional focus highlight mode so focus rings are ALWAYS visible on TV/Projector
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;

  await initDesktopWindow();

  ensureMediaKitInitialized();
  await ApiService.init();
  await AuthService.init();
  await WatchlistService().init();
  await DownloadService().init();
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
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
      },
      navigatorObservers: [routeObserver],
      home: _isLoggedIn ? const SplashPage() : const AuthPage(),
    );
  }
}
