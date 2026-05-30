import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

Widget buildPreviewWidget(VideoController controller) {
  return Video(controller: controller, controls: NoVideoControls);
}
