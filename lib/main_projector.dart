import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/memory_profile.dart';
import 'desktop_init.dart';
import 'services/media_init.dart';
import 'services/auth_service.dart';
import 'services/download_service.dart';
import 'services/api_service.dart';
import 'services/watchlist_service.dart';
import 'main.dart' show HyflixApp, HyflixHttpOverrides;

/// Projector Edition Entry Point (Low Memory Profile)
/// Built specifically for 1GB RAM Projectors / Legacy Android TVs (e.g. Lumos Projector).
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Projector Low-Memory Profile
  MemoryProfile.init(isProjector: true);

  // Apply strict low-memory constraints to Flutter's ImageCache
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      MemoryProfile.current.flutterImageCacheLimitBytes;
  PaintingBinding.instance.imageCache.maximumSize =
      MemoryProfile.current.flutterImageCacheMaxCount;

  if (!kIsWeb) {
    HttpOverrides.global = HyflixHttpOverrides();
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
