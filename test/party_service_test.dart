import 'package:flutter_test/flutter_test.dart';
import 'package:hyflix_tv/services/party_service.dart';

void main() {
  group('PartyService pins', () {
    test('generated pins are 8 characters without look-alike letters', () {
      for (var i = 0; i < 200; i++) {
        final pin = PartyService.generatePin();
        expect(pin.length, 8);
        expect(RegExp(r'^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$').hasMatch(pin), isTrue,
            reason: 'pin $pin');
      }
    });

    test('pins entered by hand are normalised', () {
      expect(PartyService.normalisePin(' abcd-2345 '), 'ABCD2345');
      expect(PartyService.normalisePin('ab cd\t23'), 'ABCD23');
    });
  });

  group('PartyMeta', () {
    test('round-trips through JSON, keeping torrent identity', () {
      const meta = PartyMeta(
        title: 'Some Show',
        posterUrl: 'https://example.com/p.jpg',
        tmdbId: 1234,
        mediaType: 'tv',
        sourceName: 'Torrent',
        infoHash: 'abc123',
        fileIdx: 2,
        year: '2024',
      );
      final back = PartyMeta.fromJson(meta.toJson());
      expect(back.title, 'Some Show');
      expect(back.tmdbId, 1234);
      expect(back.mediaType, 'tv');
      expect(back.sourceName, 'Torrent');
      expect(back.infoHash, 'abc123');
      expect(back.fileIdx, 2);
      expect(back.year, '2024');
    });

    test('omits stream identity for VOD rooms and never stores URLs', () {
      const meta = PartyMeta(title: 'VOD Movie', sourceName: 'ZUIDA (最大)');
      final json = meta.toJson();
      expect(json.containsKey('infoHash'), isFalse);
      expect(json.containsKey('fileIdx'), isFalse);
      expect(json.containsKey('url'), isFalse);
      expect(PartyMeta.fromJson(json).sourceName, 'ZUIDA (最大)');
    });
  });

  group('PartyMeta stream mode', () {
    test('keeps the host stream mode through JSON', () {
      const meta = PartyMeta(
        title: 'Torrent Show',
        sourceName: 'Torrent',
        streamMode: 'torbox',
      );
      expect(PartyMeta.fromJson(meta.toJson()).streamMode, 'torbox');
    });

    test('VOD rooms carry no stream mode', () {
      const meta = PartyMeta(title: 'VOD', sourceName: 'ZUIDA (最大)');
      expect(meta.toJson().containsKey('streamMode'), isFalse);
      expect(PartyMeta.fromJson(meta.toJson()).streamMode, isNull);
    });
  });
}
