import 'dart:html' as html;
import 'package:flutter/foundation.dart';

/// Triggers a browser native download on Web platform.
void triggerBrowserDownload(String url, String filename) {
  try {
    debugPrint('[WebDownload] Triggering browser download for: $url');
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..setAttribute('target', '_blank');
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
  } catch (e) {
    debugPrint('[WebDownload] Error triggering browser download: $e');
    try {
      html.window.open(url, '_blank');
    } catch (_) {}
  }
}
