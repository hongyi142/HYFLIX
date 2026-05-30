import '../models/episode.dart';
import '../services/tmdb_service.dart';

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
  final String year;
  final int? resumeEpisodeIndex;
  final int? resumePositionSeconds;

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
    this.year = '',
    this.resumeEpisodeIndex,
    this.resumePositionSeconds,
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
    String? year,
    int? resumeEpisodeIndex,
    int? resumePositionSeconds,
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
      year: year ?? this.year,
      resumeEpisodeIndex: resumeEpisodeIndex ?? this.resumeEpisodeIndex,
      resumePositionSeconds: resumePositionSeconds ?? this.resumePositionSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'subtitle': subtitle,
        'thumbnailUrl': thumbnailUrl,
        'bannerUrl': bannerUrl,
        'm3u8Url': m3u8Url,
        'episodes': episodes.map((e) => e.toJson()).toList(),
        'rating': rating,
        'progress': progress,
        'year': year,
        'resumeEpisodeIndex': resumeEpisodeIndex,
        'resumePositionSeconds': resumePositionSeconds,
      };

  factory ContentModel.fromJson(Map<String, dynamic> json) => ContentModel(
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
        bannerUrl: json['bannerUrl'] as String? ?? '',
        m3u8Url: json['m3u8Url'] as String? ?? '',
        episodes: (json['episodes'] as List<dynamic>?)
                ?.map((e) => Episode.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        year: json['year'] as String? ?? '',
        resumeEpisodeIndex: json['resumeEpisodeIndex'] as int?,
        resumePositionSeconds: json['resumePositionSeconds'] as int?,
      );

  factory ContentModel.fromTmdb(TmdbResult tmdb) => ContentModel(
        title: tmdb.englishTitle,
        description: tmdb.overview,
        thumbnailUrl: tmdb.posterUrl,
        bannerUrl: tmdb.backdropUrl.isNotEmpty ? tmdb.backdropUrl : tmdb.posterUrl,
        m3u8Url: '',
        year: tmdb.year,
        rating: tmdb.voteAverage,
      );
}
