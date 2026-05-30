import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';

bool _isFullScreen = false;

Future<void> toggleFullScreen() async {
  if (Platform.isAndroid || Platform.isIOS) {
    // Mobile: toggle system UI (status bar, navigation bar)
    _isFullScreen = !_isFullScreen;
    if (_isFullScreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    // Desktop: use window_manager — query actual state to stay in sync
    try {
      final isFullscreen = await WindowManager.instance.isFullScreen();
      await WindowManager.instance.setFullScreen(!isFullscreen);
    } catch (e) {
      debugPrint('[Fullscreen] Desktop toggle error: $e');
    }
  }
}
