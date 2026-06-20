import 'package:flutter/foundation.dart';

/// On web, routes image URLs through the Netlify proxy to bypass CORS.
/// On mobile/desktop, returns the original URL unchanged.
String proxyImageUrl(String url) {
  if (!kIsWeb || url.isEmpty) return url;
  if (url.startsWith('/')) return url;
  final encoded = Uri.encodeComponent(url);
  return '/api/proxy?url=$encoded';
}

/// On web, routes video streams and other resources through the Netlify proxy to bypass CORS.
/// On mobile/desktop, returns the original URL unchanged.
String proxyUrl(String url) {
  if (!kIsWeb || url.isEmpty) return url;
  if (url.startsWith('/')) return url;
  final encoded = Uri.encodeComponent(url);
  return '/api/proxy?url=$encoded';
}
