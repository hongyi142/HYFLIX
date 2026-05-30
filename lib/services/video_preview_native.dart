import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PreviewPlayer {
  Player? _player;
  VideoController? _controller;

  Player? get player => _player;
  VideoController? get controller => _controller;

  Future<void> init(String url) async {
    final player = Player();
    final controller = VideoController(player);
    await player.open(Media(url));
    await player.setVolume(0);
    _player = player;
    _controller = controller;
  }

  void dispose() {
    _player?.dispose();
    _player = null;
    _controller = null;
  }
}
