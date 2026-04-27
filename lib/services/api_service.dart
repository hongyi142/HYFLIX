import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/content_model.dart';
import '../models/episode.dart';

const String _baseUrl = 'https://www.hongniuzy2.com/api.php/provide/vod/from/hnm3u8/';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// Parse ALL episodes from vod_play_url. Format: "EpName$url#EpName$url#..."
  static List<Episode> _parseEpisodes(String playUrl) {
    final episodes = <Episode>[];
    try {
      for (final part in playUrl.split('#')) {
        final trimmed = part.trim();
        final idx = trimmed.indexOf('\$');
        if (idx != -1) {
          final name = trimmed.substring(0, idx).trim();
          final url = trimmed.substring(idx + 1).trim();
          if (url.startsWith('http')) {
            episodes.add(Episode(name: name, url: url));
          }
        }
      }
    } catch (_) {}
    return episodes;
  }

  static ContentModel _fromJson(Map<String, dynamic> json) {
    final playUrl = (json['vod_play_url'] as String? ?? '');
    final episodes = _parseEpisodes(playUrl);
    final m3u8 = episodes.isNotEmpty ? episodes.first.url : '';
    final pic = (json['vod_pic'] as String? ?? '').replaceAll(r'\/', '/');
    final score = json['vod_douban_score'];
    double rating = 0;
    if (score is String) rating = double.tryParse(score) ?? 0;
    if (score is num) rating = score.toDouble();
    final subtitle = (json['vod_remarks'] as String? ?? '');
    final blurb = (json['vod_blurb'] as String? ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final titleSeed = Uri.encodeComponent(
      (json['vod_name'] as String? ?? 'movie').replaceAll(' ', '_'),
    );
    final landscapeBanner = 'https://picsum.photos/seed/$titleSeed/1920/1080';

    final year = (json['vod_year'] as String? ?? '');

    return ContentModel(
      title: json['vod_name'] as String? ?? '',
      description: blurb,
      subtitle: subtitle,
      thumbnailUrl: pic,
      bannerUrl: landscapeBanner,
      m3u8Url: m3u8,
      episodes: episodes,
      rating: rating,
      progress: 0.0,
      year: year,
    );
  }

  Future<List<ContentModel>> _fetch(Uri uri) async {
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = body['list'] as List<dynamic>? ?? [];
      return list
          .map((e) => _fromJson(e as Map<String, dynamic>))
          .where((c) => c.m3u8Url.isNotEmpty && c.thumbnailUrl.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ContentModel>> fetchLatest({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&pg=$page'));
  Future<List<ContentModel>> fetchMovies({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=1&pg=$page'));
  Future<List<ContentModel>> fetchTVSeries({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=2&pg=$page'));
  Future<List<ContentModel>> fetchAnimation({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=4&pg=$page'));
  Future<List<ContentModel>> fetchKoreanDramas({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=18&pg=$page'));
  Future<List<ContentModel>> fetchWesternSeries({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=15&pg=$page'));
}
