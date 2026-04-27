import '../models/episode.dart';

class ContentModel {
  final String title;
  final String description;
  final String subtitle;
  final String thumbnailUrl;
  final String bannerUrl;
  final String m3u8Url;
  final List<Episode> episodes;
  final double rating;
  final double progress;

  const ContentModel({
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.bannerUrl,
    required this.m3u8Url,
    this.subtitle = '',
    this.episodes = const [],
    this.rating = 0.0,
    this.progress = 0.0,
  });

  ContentModel copyWith({
    String? title,
    String? description,
    String? subtitle,
    String? thumbnailUrl,
    String? bannerUrl,
    String? m3u8Url,
    List<Episode>? episodes,
    double? rating,
    double? progress,
  }) {
    return ContentModel(
      title: title ?? this.title,
      description: description ?? this.description,
      subtitle: subtitle ?? this.subtitle,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      m3u8Url: m3u8Url ?? this.m3u8Url,
      episodes: episodes ?? this.episodes,
      rating: rating ?? this.rating,
      progress: progress ?? this.progress,
    );
  }
}
