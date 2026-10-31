import 'package:flutter_test/flutter_test.dart';
import 'package:hyflix_tv/services/api_service.dart';

void main() {
  group('VOD source list', () {
    test('rebuilding the list from the full list never duplicates built-ins', () {
      final builtInCount = ApiService.sources.where(ApiService.isBuiltIn).length;
      expect(builtInCount, greaterThan(0));

      // Simulate adding and deleting custom sources repeatedly, rebuilding
      // the list from the full set each time, as the settings page does.
      for (var i = 0; i < 5; i++) {
        ApiService.setCustomSources([
          ...ApiService.customSources,
          VideoSource(name: 'Custom $i', baseUrl: 'https://example.com/$i/'),
        ]);
      }
      expect(ApiService.sources.length, builtInCount + 5);

      // Delete them one by one, the way the settings page does.
      for (var i = 0; i < 5; i++) {
        ApiService.setCustomSources(
          ApiService.customSources.where((s) => s.name != 'Custom $i').toList(),
        );
      }
      expect(ApiService.customSources, isEmpty);
      expect(ApiService.sources.length, builtInCount);
    });

    test('built-in sources passed in as custom are ignored', () {
      final builtIn = ApiService.sources.where(ApiService.isBuiltIn).first;
      ApiService.setCustomSources([builtIn]);
      expect(ApiService.customSources, isEmpty);
    });
  });
}
