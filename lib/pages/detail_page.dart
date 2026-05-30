import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:lucide_icons/lucide_icons.dart';
import '../core/responsive.dart';
import '../core/proxy_url.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../models/episode.dart';
import '../pages/video_player_screen.dart';
import '../services/api_service.dart';
import '../services/download_service.dart';
import '../services/torrent_service.dart';
import '../services/watchlist_service.dart';
import '../services/tmdb_service.dart';
import '../widgets/buttons.dart';

class DetailPage extends StatefulWidget {
  final ContentModel content;
  final TmdbResult? initialTmdb;

  const DetailPage({super.key, required this.content, this.initialTmdb});

  static Future<void> show(
    BuildContext context,
    ContentModel content, {
    TmdbResult? initialTmdb,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Detail',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) =>
          DetailPage(content: content, initialTmdb: initialTmdb),
      transitionBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 0.95,
            end: 1.0,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
      ),
    );
  }

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  TmdbResult? _tmdb;
  int _selectedSeason = 1;
  final _watchlistService = WatchlistService();
  final _downloadService = DownloadService();
  bool _isListed = false;

  VideoSource _selectedSource = ApiService.sources.first;
  List<Episode>? _sourceEpisodes;
  bool _isLoadingEpisodes = false;
  List<String> _cast = [];
  bool _reverseEpisodes = false;
  int _sourceGeneration = 0;

  // Torrent streaming state
  Map<int, List<TorrentStream>> _torrentStreamsByEpisode = {};
  int _torrentEpisodeCount = 0;
  int _torrentSeasonCount = 1;
  bool _isLoadingTorrents = false;
  bool _torrentFailed = false;
  String _selectedQuality = '1080p';
  List<String> _availableQualities = [];
  String _selectedEncoder = '';
  List<String> _availableEncoders = [];
  Map<int, TmdbEpisodeInfo> _tmdbEpisodeDetails = {};
  String? _cachedImdbId;

  /// Whether this content should use Chinese VOD providers as primary source.
  static bool _isChineseContent(TmdbResult? tmdb) {
    if (tmdb == null) return false;
    if (tmdb.originalLanguage == 'zh') return true;
    if (tmdb.originCountries.any({'HK', 'TW'}.contains)) return true;
    return false;
  }

  @override
  void initState() {
    super.initState();
    _tmdb = widget.initialTmdb;
    if (_tmdb == null) {
      TmdbService.search(widget.content.title, year: widget.content.year).then((
        r,
      ) {
        if (mounted) {
          setState(() => _tmdb = r);
          _fetchCast();
          _routeContentSource();
        }
      });
    } else {
      _fetchCast();
      _routeContentSource();
    }
    _checkListed();
    _watchlistService.addListener(_checkListed);
    _downloadService.addListener(_onDownloadChanged);
  }

  /// Route to the appropriate content source based on content type.
  /// Chinese content → VOD providers directly.
  /// Western/Korean content → Torrentio first, VOD fallback.
  void _routeContentSource() {
    if (kIsWeb || _isChineseContent(_tmdb)) {
      _refreshSourceEpisodes();
    } else {
      // Initialize season from content subtitle if available
      _selectedSeason = _extractSeasonNumber() ?? 1;
      _fetchTorrentStreams();
    }
  }

  @override
  void dispose() {
    _watchlistService.removeListener(_checkListed);
    _downloadService.removeListener(_onDownloadChanged);
    super.dispose();
  }

  void _onDownloadChanged() {
    if (mounted) setState(() {});
  }

  void _fetchCast() {
    final id = _tmdb?.id;
    final mediaType = _tmdb?.mediaType;
    if (id == null) return;
    TmdbService.fetchCast(id, mediaType ?? 'movie').then((cast) {
      if (mounted && cast.isNotEmpty) setState(() => _cast = cast);
    });
  }

  void _refreshSourceEpisodes() {
    // Re-fetch episodes for the current source (used on initial load)
    _switchSource(_selectedSource, force: true);
  }

  /// Fetch torrent metadata for Western/Korean content.
  /// Fetches IMDB ID + TMDB episode details in parallel (no Torrentio call yet).
  /// Torrentio streams are fetched lazily when user taps an episode.
  /// Falls back to VOD if no IMDB ID found.
  Future<void> _fetchTorrentStreams() async {
    final tmdb = _tmdb;
    if (tmdb == null || tmdb.id == null) {
      _fallbackToVod();
      return;
    }

    setState(() => _isLoadingTorrents = true);

    final isTv = tmdb.mediaType == 'tv';

    // Fetch IMDB ID + TMDB metadata in parallel
    final futures = <Future>[
      TmdbService.fetchImdbId(tmdb.id!, tmdb.mediaType),
      if (isTv) TmdbService.fetchSeasonCount(tmdb.id!),
      if (isTv) TmdbService.fetchSeasonEpisodes(tmdb.id!, _selectedSeason),
    ];

    final results = await Future.wait(futures);
    if (!mounted) return;

    final imdbId = results[0] as String?;
    if (imdbId == null) {
      _fallbackToVod();
      return;
    }
    _cachedImdbId = imdbId;

    int tmdbEpisodeCount = 0;
    final episodeDetailsMap = <int, TmdbEpisodeInfo>{};

    if (isTv) {
      _torrentSeasonCount = results[1] as int;
      final episodes = results[2] as List<TmdbEpisodeInfo>;
      tmdbEpisodeCount = episodes.length;
      for (final ep in episodes) {
        episodeDetailsMap[ep.episodeNumber] = ep;
      }
    }

    // For movies, fetch streams now. For series, defer until episode tap.
    if (!isTv) {
      final streams = await TorrentService().fetchStreams(
        imdbId, tmdb.mediaType,
      );
      if (!mounted) return;
      if (streams.isEmpty) {
        _fallbackToVod();
        return;
      }
      setState(() {
        _torrentStreamsByEpisode = {0: streams};
        _torrentEpisodeCount = 1;
        _tmdbEpisodeDetails = episodeDetailsMap;
        _availableQualities = streams.map((s) => s.quality).toSet().toList()
          ..sort((a, b) => _qualityRank(a).compareTo(_qualityRank(b)));
        _selectedQuality = _availableQualities.contains('1080p') ? '1080p' : _availableQualities.first;
        _availableEncoders = _extractEncoders(streams);
        _selectedEncoder = _availableEncoders.isNotEmpty ? _availableEncoders.first : '';
        _isLoadingTorrents = false;
      });
    } else {
      // Series: show episode list immediately, fetch first episode streams for quality dropdown
      setState(() {
        _torrentStreamsByEpisode = {};
        _torrentEpisodeCount = tmdbEpisodeCount > 0 ? tmdbEpisodeCount : 1;
        _tmdbEpisodeDetails = episodeDetailsMap;
        _availableQualities = [];
        _selectedQuality = '1080p';
        _availableEncoders = [];
        _selectedEncoder = '';
        _isLoadingTorrents = false;
      });

      // Pre-fetch first episode so quality/encoder dropdown shows all options
      _fetchEpisodeStreams(1);

      // Auto-resume: if coming from Continue Watching, play the saved episode
      final resumeIndex = widget.content.resumeEpisodeIndex;
      if (resumeIndex != null && resumeIndex < _torrentEpisodeCount) {
        final resumePos = widget.content.resumePositionSeconds ?? 0;
        _playWithTorrent(resumeIndex, seekToSeconds: resumePos);
      }
    }
  }

  /// Extract unique encoder/release group names from stream titles.
  static List<String> _extractEncoders(List<TorrentStream> streams) {
    final encoders = <String>{};
    for (final s in streams) {
      final text = '${s.filename} ${s.title}';
      // Look for common encoder patterns: x265, x264, HEVC, H264, AV1
      if (text.contains(RegExp(r'x265|HEVC|H\.?265', caseSensitive: false))) {
        encoders.add('x265/HEVC');
      }
      if (text.contains(RegExp(r'x264|H\.?264|AVC', caseSensitive: false))) {
        encoders.add('x264');
      }
      if (text.contains(RegExp(r'AV1', caseSensitive: false))) {
        encoders.add('AV1');
      }
      // Look for release group (usually after last "-" in filename)
      final groupMatch = RegExp(r'-([A-Za-z0-9]+)\.[a-z]{2,4}$').firstMatch(text);
      if (groupMatch != null) {
        encoders.add(groupMatch.group(1)!);
      }
    }
    return encoders.toList()..sort();
  }

  /// Change the selected season for torrent content and re-fetch streams.
  void _changeTorrentSeason(int season) {
    if (season == _selectedSeason) return;
    setState(() {
      _selectedSeason = season;
      _torrentStreamsByEpisode = {};
      _torrentEpisodeCount = 0;
      _tmdbEpisodeDetails = {};
      _availableQualities = [];
      _selectedQuality = '1080p';
      _availableEncoders = [];
      _selectedEncoder = '';
    });
    _fetchTorrentStreams();
  }

  /// Fall back to VOD provider when torrents aren't available.
  void _fallbackToVod() {
    setState(() {
      _torrentFailed = true;
      _isLoadingTorrents = false;
    });
    _refreshSourceEpisodes();
  }

  static int _qualityRank(String quality) {
    switch (quality) {
      case '4K': return 0;
      case '1080p': return 1;
      case '720p': return 2;
      case '480p': return 3;
      default: return 4;
    }
  }

  /// Get the best torrent stream for the selected quality and encoder.
  TorrentStream? _getStreamForSelection(int episodeNum) {
    var streams = _torrentStreamsByEpisode[episodeNum] ?? [];

    // Filter by encoder (skip if no encoder selected)
    if (_selectedEncoder.isNotEmpty) {
      final encoderLower = _selectedEncoder.toLowerCase();
      final filtered = streams.where((s) {
        final text = '${s.filename} ${s.title}'.toLowerCase();
        return text.contains(encoderLower) ||
            (_selectedEncoder == 'x265/HEVC' &&
                (text.contains('x265') || text.contains('hevc') || text.contains('h.265'))) ||
            (_selectedEncoder == 'x264' &&
                (text.contains('x264') || text.contains('h.264') || text.contains('avc')));
      }).toList();
      if (filtered.isNotEmpty) streams = filtered;
    }

    // Filter by quality
    final qualityFiltered = streams.where((s) => s.quality == _selectedQuality).toList();
    if (qualityFiltered.isNotEmpty) {
      qualityFiltered.sort((a, b) => b.seeders.compareTo(a.seeders));
      return qualityFiltered.first;
    }

    // Fallback: best available
    if (streams.isNotEmpty) {
      streams.sort((a, b) => b.seeders.compareTo(a.seeders));
      return streams.first;
    }
    return null;
  }

  /// Fetch streams for a specific episode (lazy loading for series).
  Future<void> _fetchEpisodeStreams(int episodeNum) async {
    final tmdb = _tmdb;
    if (tmdb?.id == null || _torrentStreamsByEpisode.containsKey(episodeNum)) return;

    final imdbId = _cachedImdbId ?? await TmdbService.fetchImdbId(tmdb!.id!, tmdb.mediaType);
    if (imdbId == null || !mounted) return;
    _cachedImdbId ??= imdbId;

    final streams = await TorrentService().fetchStreams(
      imdbId, 'tv',
      season: _selectedSeason,
      episode: episodeNum,
    );

    if (!mounted || streams.isEmpty) return;

    // Merge quality/encoder options from every fetched episode
    final newQualities = streams.map((s) => s.quality).toSet();
    final mergedQualities = {..._availableQualities, ...newQualities}.toList()
      ..sort((a, b) => _qualityRank(a).compareTo(_qualityRank(b)));
    final newEncoders = _extractEncoders(streams);
    final mergedEncoders = {..._availableEncoders, ...newEncoders}.toList()..sort();
    setState(() {
      _torrentStreamsByEpisode[episodeNum] = streams;
      _availableQualities = mergedQualities;
      if (!_availableQualities.contains(_selectedQuality)) {
        _selectedQuality = _availableQualities.contains('1080p') ? '1080p' : _availableQualities.first;
      }
      _availableEncoders = mergedEncoders;
      if (_selectedEncoder.isNotEmpty && !_availableEncoders.contains(_selectedEncoder)) {
        _selectedEncoder = _availableEncoders.isNotEmpty ? _availableEncoders.first : '';
      }
    });
  }

  /// Play a torrent stream — navigates to player immediately, player handles buffering.
  Future<void> _playWithTorrent(int episodeIndex, {int seekToSeconds = 0}) async {
    final tmdb = _tmdb;
    final episodeNum = episodeIndex + 1;

    // Fetch streams for this episode if not already loaded
    if (!_torrentStreamsByEpisode.containsKey(episodeNum)) {
      setState(() => _isLoadingTorrents = true);
      await _fetchEpisodeStreams(episodeNum);
      if (!mounted) return;
      setState(() => _isLoadingTorrents = false);
    }

    // Pick the best stream for selected quality/encoder
    final picked = _getStreamForSelection(episodeNum);
    if (picked == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No streams available for this episode.')),
      );
      return;
    }

    // Navigate to player immediately — player handles torrent buffering
    final poster = tmdb?.posterUrl.isNotEmpty == true
        ? tmdb!.posterUrl
        : widget.content.thumbnailUrl;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: '',
          title: tmdb?.englishTitle ?? widget.content.title,
          originalTitle: widget.content.title,
          episodes: const [],
          initialEpisodeIndex: 0,
          tmdbId: tmdb?.id?.toString(),
          isTvShow: _torrentEpisodeCount > 1,
          seasonNumber: _selectedSeason,
          posterUrl: poster,
          torrentStream: picked,
          seekToSeconds: seekToSeconds,
        ),
      ),
    );
  }

  void _switchSource(VideoSource source, {bool force = false}) {
    if (!force && source == _selectedSource) return;
    final gen = ++_sourceGeneration;
    setState(() {
      _selectedSource = source;
      _isLoadingEpisodes = true;
    });
    final api = ApiService();
    final tmdb = _tmdb;

    Future<void> applyEpisodes(List<Episode>? eps) async {
      if (!mounted || _sourceGeneration != gen) return;
      setState(() {
        _sourceEpisodes = eps;
        _isLoadingEpisodes = false;
      });
    }

    if (tmdb != null) {
      api.matchTmdbToProviderFromSource(tmdb, source).then((result) async {
        final matchedEps = result?.episodes ?? [];
        // If TMDB match returned results, use them
        if (matchedEps.isNotEmpty) {
          await applyEpisodes(matchedEps);
          return;
        }
        // Fallback: direct search by original title + cleaned title
        var fallbackResults = await api.searchByTitleFromSource(
          widget.content.title, source);
        var allEps = <Episode>[];
        for (final r in fallbackResults) {
          allEps.addAll(r.episodes);
        }
        // If still no results and we have a TMDB ID, try Chinese title
        if (allEps.isEmpty && tmdb.id != null) {
          final chineseTitle = await TmdbService.fetchChineseTitle(
            tmdb.id!, tmdb.mediaType);
          if (chineseTitle != null && chineseTitle != widget.content.title) {
            fallbackResults = await api.searchByTitleFromSource(
              chineseTitle, source);
            for (final r in fallbackResults) {
              allEps.addAll(r.episodes);
            }
          }
        }
        await applyEpisodes(allEps.isNotEmpty ? allEps : null);
      });
    } else {
      api
          .searchByTitleFromSource(widget.content.title, source)
          .then((results) async {
        final allEps = <Episode>[];
        for (final r in results) {
          allEps.addAll(r.episodes);
        }
        await applyEpisodes(allEps.isNotEmpty ? allEps : null);
      });
    }
  }

  void _handleDownload(int episodeIndex) {
    final ep = widget.content.episodes[episodeIndex];
    final contentId = _tmdb?.id?.toString() ?? widget.content.title;
    final existing = _downloadService.getDownload(contentId, episodeIndex);

    if (existing?.status == DownloadStatus.downloading) {
      _downloadService.cancelDownload(contentId, episodeIndex);
      return;
    }

    if (existing?.status == DownloadStatus.completed) {
      _downloadService.deleteDownload(contentId, episodeIndex);
      return;
    }

    _downloadService.startDownload(
      contentId: contentId,
      contentTitle: _tmdb?.englishTitle ?? widget.content.title,
      episodeIndex: episodeIndex,
      episodeName: ep.name.isNotEmpty ? ep.name : 'Episode ${episodeIndex + 1}',
      m3u8Url: ep.url,
      thumbnailUrl: _tmdb?.posterUrl ?? widget.content.thumbnailUrl,
    );
  }

  void _checkListed() {
    if (mounted) {
      bool found = false;
      for (final listName in _watchlistService.listNames) {
        if (_watchlistService.isListed(listName, widget.content.title)) {
          found = true;
          break;
        }
      }
      setState(() => _isListed = found);
    }
  }

  void _showAddToListModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final lists = _watchlistService.listNames;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Save to...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...lists.map((listName) {
                    final isListed = _watchlistService.isListed(
                      listName,
                      widget.content.title,
                    );
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                      ),
                      title: Text(
                        listName,
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: isListed
                          ? const Icon(
                              LucideIcons.checkCircle2,
                              color: AppTheme.accent,
                            )
                          : const Icon(
                              LucideIcons.circle,
                              color: Colors.white54,
                            ),
                      onTap: () {
                        if (isListed) {
                          _watchlistService.removeFromList(
                            listName,
                            widget.content.title,
                          );
                        } else {
                          _watchlistService.addToList(listName, widget.content);
                        }
                        setModalState(() {});
                      },
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  int? _extractSeasonNumber() {
    final subtitle = widget.content.subtitle;
    final match = RegExp(r'第([一二三四五六七八九十\d]+)季').firstMatch(subtitle);
    if (match != null) {
      final seasonStr = match.group(1)!;
      if (RegExp(r'^\d+$').hasMatch(seasonStr)) return int.tryParse(seasonStr);
      const cnNums = {
        '一': 1,
        '二': 2,
        '三': 3,
        '四': 4,
        '五': 5,
        '六': 6,
        '七': 7,
        '八': 8,
        '九': 9,
        '十': 10,
      };
      return cnNums[seasonStr];
    }
    return null;
  }

  void _play(int episodeIndex) {
    // Route to torrent for non-Chinese content (unless torrent already failed or on web)
    if (!kIsWeb && !_isChineseContent(_tmdb) && !_torrentFailed) {
      _playWithTorrent(episodeIndex);
      return;
    }

    // VOD playback path
    final episodes = _sourceEpisodes ?? widget.content.episodes;
    if (episodes.isEmpty) {
      if (_isLoadingEpisodes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Loading episodes, please wait...'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No streams available for this title.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    final isTvShow = episodes.length > 1;
    final poster = _tmdb?.posterUrl.isNotEmpty == true
        ? _tmdb!.posterUrl
        : widget.content.thumbnailUrl;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: episodes.isNotEmpty
              ? episodes[episodeIndex].url
              : widget.content.m3u8Url,
          title: _tmdb?.englishTitle ?? widget.content.title,
          originalTitle: widget.content.title,
          episodes: episodes,
          initialEpisodeIndex: episodeIndex,
          tmdbId: _tmdb?.id?.toString(),
          isTvShow: isTvShow,
          seasonNumber: _extractSeasonNumber() ?? 1,
          posterUrl: poster,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);
    final title = _tmdb?.englishTitle.isNotEmpty == true
        ? _tmdb!.englishTitle
        : widget.content.title;
    final overview = _tmdb?.overview.isNotEmpty == true
        ? _tmdb!.overview
        : widget.content.description;
    final backdrop = _tmdb?.backdropUrl.isNotEmpty == true
        ? _tmdb!.backdropUrl
        : widget.content.bannerUrl;
    final genres = _tmdb?.genres ?? [];
    final year = _tmdb?.year ?? widget.content.year;
    final rating = _tmdb?.voteAverage ?? widget.content.rating;
    final episodes =
        _sourceEpisodes ?? widget.content.episodes;
    final isMultiEpisode = episodes.length > 1;

    final screenHeight = MediaQuery.of(context).size.height;
    final modalHeight = layout.isPhone
        ? screenHeight - 24
        : screenHeight * 0.85;
    final contentPadding = layout.isPhone ? 20.0 : 32.0;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: layout.modalHorizontalPadding,
          vertical: layout.modalVerticalPadding,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: AppTheme.background,
            child: Container(
            height: modalHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroSection(context, backdrop, title),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      contentPadding,
                      0,
                      contentPadding,
                      0,
                    ),
                    child: layout.useWideDetailLayout
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildMetadataRow(
                                      year,
                                      rating,
                                      isMultiEpisode,
                                      episodes,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildOverviewText(overview, layout),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 32),
                              Expanded(
                                flex: 2,
                                child: _buildSidebarInfo(genres),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildMetadataRow(
                                year,
                                rating,
                                isMultiEpisode,
                                episodes,
                              ),
                              const SizedBox(height: 16),
                              _buildOverviewText(overview, layout),
                              const SizedBox(height: 24),
                              _buildSidebarInfo(genres),
                            ],
                          ),
                  ),
                  // Episodes/streams section
                  if (!kIsWeb && !_isChineseContent(_tmdb) && !_torrentFailed) ...[
                    // Torrent content: show quality filter + play/episode cards
                    SizedBox(height: layout.isPhone ? 28 : 36),
                    _buildTorrentEpisodesSection(layout),
                  ] else if (isMultiEpisode) ...[
                    // VOD content: show episode list
                    SizedBox(height: layout.isPhone ? 28 : 36),
                    _buildEpisodesSection(episodes, layout),
                  ],
                  SizedBox(height: layout.isPhone ? 28 : 60),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildTorrentEpisodesSection(ResponsiveLayout layout) {
    final contentPadding = layout.isPhone ? 20.0 : 32.0;
    final isMovie = _tmdb?.mediaType != 'tv';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with quality dropdown + fallback button
        Padding(
          padding: EdgeInsets.fromLTRB(contentPadding, 0, contentPadding, 16),
          child: Row(
            children: [
              if (isMovie)
                const Text(
                  'Stream',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                )
              else
                const Text(
                  'Episodes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
              // Season dropdown for multi-season TV shows
              if (!isMovie && _torrentSeasonCount > 1) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.cardDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: DropdownButton<int>(
                    value: _selectedSeason,
                    dropdownColor: AppTheme.cardDark,
                    underline: const SizedBox(),
                    isDense: true,
                    items: List.generate(_torrentSeasonCount, (i) => i + 1)
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                'Season $s',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) _changeTorrentSeason(v);
                    },
                  ),
                ),
              ],
              const SizedBox(width: 12),
              // Quality selector (dropdown if multiple, label if single)
              if (_availableQualities.isNotEmpty)
                _availableQualities.length > 1
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.cardDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedQuality,
                          dropdownColor: AppTheme.cardDark,
                          underline: const SizedBox(),
                          isDense: true,
                          items: _availableQualities
                              .map((q) => DropdownMenuItem(
                                    value: q,
                                    child: Text(
                                      q,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedQuality = v);
                          },
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.cardDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          _selectedQuality,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
              const SizedBox(width: 8),
              // Encoder/source selector (dropdown if multiple, label if single)
              if (_availableEncoders.isNotEmpty && _selectedEncoder.isNotEmpty)
                _availableEncoders.length > 1
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.cardDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedEncoder,
                          dropdownColor: AppTheme.cardDark,
                          underline: const SizedBox(),
                          isDense: true,
                          items: _availableEncoders
                              .map((e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(
                                      e,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedEncoder = v);
                          },
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.cardDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          _selectedEncoder,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
              if (_isLoadingTorrents) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent,
                  ),
                ),
              ],
              const Spacer(),
              // Fallback button
              HoverButton(
                onTap: _fallbackToVod,
                backgroundColor: const Color(0x662F3640),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    'Try other sources',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Content: movie play card or episode list
        if (_isLoadingTorrents)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            ),
          )
        else if (isMovie)
          _buildTorrentMovieCard(layout)
        else
          _buildTorrentEpisodeList(layout),
      ],
    );
  }

  Widget _buildTorrentMovieCard(ResponsiveLayout layout) {
    final stream = _getStreamForSelection(0);
    final contentPadding = layout.isPhone ? 20.0 : 32.0;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: contentPadding, vertical: 6),
      child: Material(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _playWithTorrent(0),
          focusColor: Colors.white24,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Quality badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
                  ),
                  child: Text(
                    _selectedQuality,
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                if (stream?.isHDR == true) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'HDR',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                // Stream info
                if (stream != null) ...[
                  Icon(Icons.people, color: AppTheme.textSecondary, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${stream.seeders}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (stream.size.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      stream.size,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ],
                const Spacer(),
                const Icon(LucideIcons.playCircle, color: AppTheme.textSecondary, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTorrentEpisodeList(ResponsiveLayout layout) {
    return Column(
      children: List.generate(_torrentEpisodeCount, (i) {
        return _buildTorrentEpisodeTile(i, layout);
      }),
    );
  }

  Widget _buildTorrentEpisodeTile(int index, ResponsiveLayout layout) {
    final epNum = index + 1;
    final stream = _getStreamForSelection(epNum);
    final epDetail = _tmdbEpisodeDetails[epNum];
    final epName = epDetail?.name.isNotEmpty == true ? epDetail!.name : 'Episode $epNum';
    final epOverview = epDetail?.overview ?? '';
    final stillUrl = epDetail?.stillUrl ?? '';

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: layout.isPhone ? 20 : 32,
        vertical: 6,
      ),
      child: Material(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _playWithTorrent(index),
          focusColor: Colors.white24,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: layout.isPhone
                ? _buildEpisodeTilePhone(epNum, epName, epOverview, stillUrl, stream)
                : _buildEpisodeTileDesktop(epNum, epName, epOverview, stillUrl, stream),
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeTilePhone(
    int epNum, String epName, String epOverview, String stillUrl, TorrentStream? stream,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$epNum',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
            const Spacer(),
            const Icon(LucideIcons.playCircle, color: AppTheme.textSecondary, size: 22),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: stillUrl.isNotEmpty
              ? Image.network(
                  proxyImageUrl(stillUrl),
                  width: double.infinity,
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _episodePlaceholder(width: double.infinity, height: 160),
                )
              : _episodePlaceholder(width: double.infinity, height: 160),
        ),
        const SizedBox(height: 12),
        Text(
          epName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (epOverview.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            epOverview,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.4,
              decoration: TextDecoration.none,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        _buildStreamBadges(stream),
      ],
    );
  }

  Widget _buildEpisodeTileDesktop(
    int epNum, String epName, String epOverview, String stillUrl, TorrentStream? stream,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            '$epNum',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(width: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: stillUrl.isNotEmpty
              ? Image.network(
                  proxyImageUrl(stillUrl),
                  width: 160,
                  height: 90,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _episodePlaceholder(width: 160, height: 90),
                )
              : _episodePlaceholder(width: 160, height: 90),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                epName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (epOverview.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  epOverview,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                    decoration: TextDecoration.none,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              _buildStreamBadges(stream),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Icon(LucideIcons.playCircle, color: AppTheme.textSecondary, size: 22),
      ],
    );
  }

  Widget _buildStreamBadges(TorrentStream? stream) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _selectedQuality,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        if (stream != null) ...[
          const SizedBox(width: 6),
          Icon(Icons.people, color: AppTheme.textSecondary, size: 12),
          const SizedBox(width: 2),
          Text(
            '${stream.seeders}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              decoration: TextDecoration.none,
            ),
          ),
          if (stream.size.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              stream.size,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildOverviewText(String overview, ResponsiveLayout layout) {
    return Text(
      overview.isNotEmpty ? overview : 'No description available.',
      style: TextStyle(
        color: AppTheme.textSecondary,
        fontSize: layout.isPhone ? 13 : 14,
        height: 1.6,
        fontWeight: FontWeight.normal,
        decoration: TextDecoration.none,
      ),
    );
  }

  Widget _buildHeroSection(
    BuildContext context,
    String backdrop,
    String title,
  ) {
    final layout = ResponsiveLayout.of(context);
    final heroHeight = layout.isPhone ? 420.0 : 580.0;
    final titleSize = layout.isPhone ? 28.0 : 42.0;
    final horizontalPadding = layout.isPhone ? 20.0 : 32.0;
    final buttonWrapSpacing = layout.isPhone ? 10.0 : 12.0;

    return Stack(
      children: [
        SizedBox(
          height: heroHeight,
          width: double.infinity,
          child: Image.network(
            proxyImageUrl(backdrop),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: AppTheme.cardDark),
          ),
        ),
        Container(
          height: heroHeight,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.transparent,
                Color(0xCC0B0F14),
                AppTheme.background,
              ],
              stops: [0.0, 0.4, 0.75, 1.0],
            ),
          ),
        ),
        Container(
          height: heroHeight,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xAA0B0F14), Colors.transparent],
              stops: [0.0, 0.5],
            ),
          ),
        ),
        Positioned(
          top: layout.isPhone ? 16 : 40,
          left: layout.isPhone ? 12 : 20,
          child: HoverButton(
            onTap: () => Navigator.of(context).pop(),
            backgroundColor: Colors.black54,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: const Icon(
                LucideIcons.arrowLeft,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ),
        Positioned(
          top: layout.isPhone ? 16 : 40,
          right: layout.isPhone ? 12 : 20,
          child: HoverButton(
            onTap: () => Navigator.of(context).pop(),
            backgroundColor: Colors.black54,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: const Icon(LucideIcons.x, color: Colors.white, size: 22),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                horizontalPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'HY',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'SERIES',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          letterSpacing: 4,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: layout.isPhone ? 1 : 2,
                      height: 1.1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: buttonWrapSpacing,
                    runSpacing: 12,
                    children: [
                      HoverButton(
                        onTap: () => _play(0),
                        backgroundColor: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 12,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.play,
                                color: Colors.black,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Play',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      HoverButton(
                        onTap: _showAddToListModal,
                        backgroundColor: _isListed
                            ? AppTheme.accent.withOpacity(0.2)
                            : const Color(0x662F3640),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isListed
                                    ? LucideIcons.check
                                    : LucideIcons.plus,
                                color: _isListed
                                    ? AppTheme.accent
                                    : Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isListed ? 'Added' : 'My List',
                                style: TextStyle(
                                  color: _isListed
                                      ? AppTheme.accent
                                      : Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _actionButton(LucideIcons.thumbsUp, ''),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionButton(IconData icon, String label) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0x662F3640),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataRow(
    String year,
    double rating,
    bool isMultiEpisode,
    List<Episode> episodes,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Match percentage (simulated)
        if (rating > 0) ...[
          Text(
            '${(rating * 10).round()}% Match',
            style: const TextStyle(
              color: Color(0xFF46D369),
              fontWeight: FontWeight.w700,
              fontSize: 14,
              decoration: TextDecoration.none,
            ),
          ),
        ],
        // Year
        if (year.isNotEmpty) _metadataChip(year),
        // Rating badge
        if (widget.content.subtitle.isNotEmpty) _metadataChip('TV-MA'),
        // Episode count
        if (isMultiEpisode) _metadataChip('${episodes.length} Episodes'),
        // HD badge
        _metadataChip('HD'),
      ],
    );
  }

  Widget _metadataChip(String text) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.cardLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarInfo(List<String> genres) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Genres
        if (genres.isNotEmpty) ...[
          _sidebarRow('Genres:', genres.join(', ')),
          const SizedBox(height: 12),
        ],
        // Cast
        if (_cast.isNotEmpty) ...[
          _sidebarRow('Cast:', _cast.join(', ')),
          const SizedBox(height: 12),
        ],
        // Rating
        if (widget.content.rating > 0) ...[
          _sidebarRow('Rating:', widget.content.rating.toStringAsFixed(1)),
        ],
      ],
    );
  }

  Widget _sidebarRow(String label, String value) {
    return Material(
      type: MaterialType.transparency,
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                decoration: TextDecoration.none,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodesSection(
    List<Episode> episodes,
    ResponsiveLayout layout,
  ) {
    // Extract season numbers from episode names
    final seasonMap = <int, List<Episode>>{};
    for (final ep in episodes) {
      final seasonMatch = RegExp(r'第(\d+)季').firstMatch(ep.name);
      final season = seasonMatch != null
          ? int.tryParse(seasonMatch.group(1)!) ?? 1
          : 1;
      seasonMap.putIfAbsent(season, () => []).add(ep);
    }
    final seasons = seasonMap.keys.toList()..sort();
    final hasSeasons = seasons.length > 1;
    var filteredEpisodes = hasSeasons
        ? (seasonMap[_selectedSeason] ?? [])
        : episodes;
    if (_reverseEpisodes) filteredEpisodes = filteredEpisodes.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with season dropdown
        Padding(
          padding: EdgeInsets.fromLTRB(
            layout.isPhone ? 20 : 32,
            0,
            layout.isPhone ? 20 : 32,
            16,
          ),
          child: Row(
            children: [
              const Text(
                'Episodes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 8),
              if (hasSeasons)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.cardDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: DropdownButton<int>(
                    value: _selectedSeason,
                    dropdownColor: AppTheme.cardDark,
                    underline: const SizedBox(),
                    isDense: true,
                    items: seasons
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              'Season $s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedSeason = v ?? 1),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.cardLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${episodes.length}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              // Source picker
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: DropdownButton<VideoSource>(
                  value: _selectedSource,
                  dropdownColor: AppTheme.cardDark,
                  underline: const SizedBox(),
                  isDense: true,
                  items: ApiService.sources
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            s.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _switchSource(v);
                  },
                ),
              ),
              if (_isLoadingEpisodes) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent,
                  ),
                ),
              ],
              const Spacer(),
              // Reverse order button
              GestureDetector(
                onTap: () => setState(() => _reverseEpisodes = !_reverseEpisodes),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _reverseEpisodes ? AppTheme.accent.withOpacity(0.2) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    LucideIcons.arrowDownUp,
                    color: _reverseEpisodes ? AppTheme.accent : AppTheme.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Episode list
        if (_isLoadingEpisodes)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            ),
          )
        else
          ...List.generate(filteredEpisodes.length, (i) {
            final globalIndex = episodes.indexOf(filteredEpisodes[i]);
            return _buildEpisodeTile(filteredEpisodes[i], globalIndex, layout);
          }),
      ],
    );
  }

  Widget _buildDownloadButton(int index) {
    final contentId = _tmdb?.id?.toString() ?? widget.content.title;
    final download = _downloadService.getDownload(contentId, index);
    final isDownloaded = _downloadService.isDownloaded(contentId, index);

    IconData icon;
    Color color;
    VoidCallback? onTap;

    if (isDownloaded) {
      icon = LucideIcons.checkCircle;
      color = AppTheme.accent;
      onTap = () => _handleDownload(index);
    } else if (download?.status == DownloadStatus.downloading) {
      icon = LucideIcons.loader;
      color = AppTheme.accent;
      onTap = () => _handleDownload(index);
    } else if (download?.status == DownloadStatus.failed) {
      icon = LucideIcons.refreshCw;
      color = Colors.orange;
      onTap = () => _handleDownload(index);
    } else {
      icon = LucideIcons.download;
      color = AppTheme.textSecondary;
      onTap = () => _handleDownload(index);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildEpisodeTile(
    Episode episode,
    int index,
    ResponsiveLayout layout,
  ) {
    final epName = episode.name.isNotEmpty
        ? episode.name
        : 'Episode ${index + 1}';
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: layout.isPhone ? 20 : 32,
        vertical: 6,
      ),
      child: Material(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _play(index),
          focusColor: Colors.white24,
          child: Padding(
            padding: const EdgeInsets.all(12),
        child: layout.isPhone
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const Spacer(),
                      _buildDownloadButton(index),
                      const SizedBox(width: 4),
                      const Icon(
                        LucideIcons.playCircle,
                        color: AppTheme.textSecondary,
                        size: 22,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: episode.imageUrl.isNotEmpty
                        ? Image.network(
                            proxyImageUrl(episode.imageUrl),
                            width: double.infinity,
                            height: 160,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _episodePlaceholder(
                              width: double.infinity,
                              height: 160,
                            ),
                          )
                        : _episodePlaceholder(
                            width: double.infinity,
                            height: 160,
                          ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    epName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Episode ${index + 1}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: episode.imageUrl.isNotEmpty
                        ? Image.network(
                            proxyImageUrl(episode.imageUrl),
                            width: 120,
                            height: 68,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _episodePlaceholder(),
                          )
                        : _episodePlaceholder(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          epName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Episode ${index + 1}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildDownloadButton(index),
                  const SizedBox(width: 4),
                  const Icon(
                    LucideIcons.playCircle,
                    color: AppTheme.textSecondary,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  Widget _episodePlaceholder({double width = 120, double height = 68}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.cardLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        LucideIcons.play,
        color: AppTheme.textSecondary,
        size: 24,
      ),
    );
  }
}
