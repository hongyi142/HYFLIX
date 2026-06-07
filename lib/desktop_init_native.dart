import 'dart:io';
import 'package:window_manager/window_manager.dart';

Future<void> initDesktopWindow() async {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await WindowManager.instance.ensureInitialized();
    await WindowManager.instance.waitUntilReadyToShow();
  }
}
