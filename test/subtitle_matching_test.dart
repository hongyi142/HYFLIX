import 'package:flutter_test/flutter_test.dart';
import 'package:hyflix_tv/services/subtitle_service.dart';

void main() {
  group('Subtitle Matching Tests', () {
    test('Matches S##E## pattern', () {
      expect(
        SubtitleService.classifyMatch('Show.Name.S01E03.720p.srt', 1, 3),
        equals(SubtitleMatchType.exactEpisode),
      );
      expect(
        SubtitleService.classifyMatch('Show.Name.S01E03.720p.srt', 1, 4),
        isNull,
      );
    });

    test('Matches 1x03 pattern', () {
      expect(
        SubtitleService.classifyMatch('Show.Name.1x03.srt', 1, 3),
        equals(SubtitleMatchType.exactEpisode),
      );
      expect(
        SubtitleService.classifyMatch('Show.Name.1x03.srt', 1, 4),
        isNull,
      );
    });

    test('Matches Ep/EP pattern', () {
      expect(
        SubtitleService.classifyMatch('Show.Name.Ep03.srt', 1, 3),
        equals(SubtitleMatchType.exactEpisode),
      );
      expect(
        SubtitleService.classifyMatch('Show.Name.Ep03.srt', 1, 4),
        isNull,
      );
    });

    test('Matches Standalone numbers', () {
      expect(
        SubtitleService.classifyMatch('Show.Name.03.srt', 1, 3),
        equals(SubtitleMatchType.exactEpisode),
      );
      expect(
        SubtitleService.classifyMatch('Show.Name.03.srt', 1, 4),
        isNull,
      );
      expect(
        SubtitleService.classifyMatch('03.srt', 1, 3),
        equals(SubtitleMatchType.exactEpisode),
      );
    });

    test('Ignores resolutions, years, and codecs as standalone numbers', () {
      expect(
        SubtitleService.classifyMatch('Show.Name.2024.1080p.x265.srt', 1, 24),
        equals(SubtitleMatchType.seasonFallback),
      );
      expect(
        SubtitleService.classifyMatch('Show.Name.S01.720p.h264.srt', 1, 20),
        equals(SubtitleMatchType.seasonFallback),
      );
    });

    test('Normalizes mathematical stylized unicode symbols', () {
      expect(
        SubtitleService.normalizeUnicodeAlphanumeric(
          '[𝗖𝗼𝗳𝗳𝗲𝗲𝗣𝗿𝗶𝘀𝗼𝗻] 𝗔𝗚𝗘𝗡𝗧 𝗞𝗜𝗠 𝗥𝗘𝗔𝗖𝗧𝗜𝗩𝗔𝗧𝗘𝗗 𝗦𝟬𝟭𝗘𝟬𝟰 𝗡𝗙𝗫 𝗪𝗘𝗕',
        ),
        equals('[CoffeePrison] AGENT KIM REACTIVATED S01E04 NFX WEB'),
      );
    });
  });
}
