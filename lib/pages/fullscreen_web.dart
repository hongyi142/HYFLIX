import 'dart:html' as html;

void toggleFullScreen() {
  final doc = html.document;
  if (doc.fullscreenElement != null) {
    doc.exitFullscreen();
  } else {
    doc.documentElement?.requestFullscreen();
  }
}
