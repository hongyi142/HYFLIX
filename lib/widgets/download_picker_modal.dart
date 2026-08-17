import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../core/responsive.dart';
import '../core/proxy_url.dart';
import '../models/content_model.dart';
import '../models/episode.dart';
import '../services/api_service.dart';
import '../services/tmdb_service.dart';
import '../services/torrent_service.dart';
import '../services/torbox_service.dart';
import '../services/download_service.dart';
import 'buttons.dart';

const VideoSource _torrentSource = VideoSource(
  name: 'Torrent (TorBox)',
  baseUrl: 'torrent',
);

/// Shows the Netflix-inspired universal Download Picker modal for movies and TV series,
/// supporting both Torrent and Chinese VOD sources with full D-pad & remote control.
Future<void> showDownloadPickerModal({
  required BuildContext context,
  required ContentModel content,
  TmdbResult? tmdb,
  bool isNonChineseContent = false,
  VideoSource? initialSource,
  List<Episode>? initialEpisodes,
  int torrentSeasonCount = 1,
  int selectedSeason = 1,
  Map<int, List<TorrentStream>>? cachedTorrentStreams,
  String selectedQuality = '1080p',
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _DownloadPickerModal(
      content: content,
      tmdb: tmdb,
      isNonChineseContent: isNonChineseContent,
      initialSource: initialSource,
      initialEpisodes: initialEpisodes,
      torrentSeasonCount: torrentSeasonCount,
      initialSeason: selectedSeason,
      cachedTorrentStreams: cachedTorrentStreams,
      initialQuality: selectedQuality,
    ),
  );
}

class _DownloadPickerModal extends StatefulWidget {
  final ContentModel content;
  final TmdbResult? tmdb;
  final bool isNonChineseContent;
  final VideoSource? initialSource;
  final List<Episode>? initialEpisodes;
  final int torrentSeasonCount;
  final int initialSeason;
  final Map<int, List<TorrentStream>>? cachedTorrentStreams;
  final String initialQuality;

  const _DownloadPickerModal({
    required this.content,
    this.tmdb,
    this.isNonChineseContent = false,
    this.initialSource,
    this.initialEpisodes,
    this.torrentSeasonCount = 1,
    this.initialSeason = 1,
    this.cachedTorrentStreams,
    this.initialQuality = '1080p',
  });

  @override
  State<_DownloadPickerModal> createState() => _DownloadPickerModalState();
}

class _DownloadPickerModalState extends State<_DownloadPickerModal> {
  final DownloadService _downloadService = DownloadService();
  late VideoSource _selectedSource;
  late int _selectedSeason;
  late String _selectedQuality;
  late int _seasonCount;

  bool _isLoading = false;
  bool _isDownloading = false;
  String _loadingMessage = '';

  // VOD episodes by source
  final Map<String, List<Episode>> _episodesBySource = {};
  List<Episode> _currentVodEpisodes = [];

  // Torrent streams
  Map<int, List<TorrentStream>> _torrentStreamsByEpisode = {};
  int _torrentEpisodeCount = 1;
  List<String> _availableQualities = [];
  Map<int, TmdbEpisodeInfo> _tmdbEpisodeDetails = {};

  // Selection
  final Set<int> _selectedEpisodeIndices = {};

  bool get _isTv =>
      widget.tmdb?.mediaType == 'tv' ||
      widget.content.episodes.length > 1 ||
      widget.torrentSeasonCount > 1;

  bool get _isTorrent => _selectedSource == _torrentSource;

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.initialSeason;
    _seasonCount = widget.torrentSeasonCount < 1 ? 1 : widget.torrentSeasonCount;
    _selectedQuality = widget.initialQuality;

    if (widget.isNonChineseContent) {
      _selectedSource = widget.initialSource ?? _torrentSource;
    } else {
      _selectedSource = widget.initialSource ??
          ApiService.defaultSource ??
          ApiService.sources.first;
    }

    if (widget.initialEpisodes != null && widget.initialEpisodes!.isNotEmpty) {
      _currentVodEpisodes = List.from(widget.initialEpisodes!);
      if (!_isTorrent) {
        _episodesBySource[_selectedSource.name] = _currentVodEpisodes;
      }
    }

    if (widget.cachedTorrentStreams != null) {
      _torrentStreamsByEpisode = Map.from(widget.cachedTorrentStreams!);
    }

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (_isTorrent) {
      await _loadTorrentData();
    } else {
      await _loadVodEpisodes(_selectedSource);
    }
  }

  Future<void> _loadTorrentData() async {
    final tmdb = widget.tmdb;
    if (tmdb == null || tmdb.id == null) {
      _selectAllEpisodes();
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Loading torrent sources & qualities...';
    });

    try {
      final imdbId = await TmdbService.fetchImdbId(tmdb.id!, tmdb.mediaType);
      if (imdbId == null) {
        setState(() => _isLoading = false);
        return;
      }

      if (_isTv) {
        final episodes =
            await TmdbService.fetchSeasonEpisodes(tmdb.id!, _selectedSeason);
        _torrentEpisodeCount = episodes.isNotEmpty ? episodes.length : 1;
        _tmdbEpisodeDetails = {for (final e in episodes) e.episodeNumber: e};
      } else {
        _torrentEpisodeCount = 1;
        if (!_torrentStreamsByEpisode.containsKey(0)) {
          final streams = await TorrentService().fetchStreams(
            imdbId,
            tmdb.mediaType,
          );
          _torrentStreamsByEpisode[0] = streams;
        }
      }

      // Collect available qualities
      final allStreams = _torrentStreamsByEpisode.values.expand((l) => l).toList();
      if (allStreams.isNotEmpty) {
        _availableQualities = allStreams.map((s) => s.quality).toSet().toList()
          ..sort((a, b) => _qualityRank(a).compareTo(_qualityRank(b)));
        if (!_availableQualities.contains(_selectedQuality)) {
          _selectedQuality = _availableQualities.contains('1080p')
              ? '1080p'
              : _availableQualities.first;
        }
      } else {
        _availableQualities = ['4K', '1080p', '720p'];
      }
    } catch (e) {
      debugPrint('[DownloadPicker] Error loading torrent data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _selectAllEpisodes();
      }
    }
  }

  Future<void> _loadVodEpisodes(VideoSource source) async {
    if (_episodesBySource.containsKey(source.name)) {
      setState(() {
        _currentVodEpisodes = _episodesBySource[source.name]!;
        _selectAllEpisodes();
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Fetching episodes from ${source.name}...';
    });

    try {
      final api = ApiService();
      final tmdb = widget.tmdb;
      List<Episode> eps = [];

      if (tmdb != null) {
        final result = await api.matchTmdbToProviderFromSource(tmdb, source);
        eps = result?.episodes ?? [];

        if (eps.isEmpty) {
          final fallback = await api.searchByTitleFromSource(
              widget.content.title, source);
          for (final r in fallback) {
            eps.addAll(r.episodes);
          }
        }
      } else {
        final results = await api.searchByTitleFromSource(
            widget.content.title, source);
        for (final r in results) {
          eps.addAll(r.episodes);
        }
      }

      if (mounted) {
        setState(() {
          _episodesBySource[source.name] = eps;
          _currentVodEpisodes = eps;
        });
      }
    } catch (e) {
      debugPrint('[DownloadPicker] Error loading VOD episodes: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _selectAllEpisodes();
      }
    }
  }

  void _selectAllEpisodes() {
    _selectedEpisodeIndices.clear();
    final count = _effectiveEpisodeCount;
    for (int i = 0; i < count; i++) {
      _selectedEpisodeIndices.add(i);
    }
    setState(() {});
  }

  void _deselectAllEpisodes() {
    setState(() {
      _selectedEpisodeIndices.clear();
    });
  }

  int get _effectiveEpisodeCount {
    if (!_isTv) return 1;
    if (_isTorrent) return _torrentEpisodeCount;
    return _currentVodEpisodes.isNotEmpty
        ? _currentVodEpisodes.length
        : widget.content.episodes.length;
  }

  int _qualityRank(String q) {
    switch (q.toUpperCase()) {
      case '4K':
        return 0;
      case '1080P':
        return 1;
      case '720P':
        return 2;
      case '480P':
        return 3;
      default:
        return 4;
    }
  }

  Color _qualityBadgeColor(String q) {
    switch (q.toUpperCase()) {
      case '4K':
        return const Color(0xFFE50914);
      case '1080P':
        return const Color(0xFF46D369);
      case '720P':
        return const Color(0xFF4DA6FF);
      default:
        return const Color(0xFFAAAAAA);
    }
  }

  Future<void> _startBatchDownload() async {
    if (_selectedEpisodeIndices.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _loadingMessage = 'Starting downloads...';
    });

    final tmdb = widget.tmdb;
    final contentId = tmdb?.id?.toString() ?? widget.content.title;
    final contentTitle = tmdb?.englishTitle ?? widget.content.title;
    final posterUrl = tmdb?.posterUrl.isNotEmpty == true
        ? tmdb!.posterUrl
        : widget.content.thumbnailUrl;

    int queuedCount = 0;

    try {
      if (_isTorrent) {
        final imdbId = tmdb?.id != null
            ? await TmdbService.fetchImdbId(tmdb!.id!, tmdb.mediaType)
            : null;

        for (final epIdx in _selectedEpisodeIndices) {
          final episodeNum = _torrentEpisodeCount <= 1 ? 0 : epIdx + 1;
          final episodeName = _torrentEpisodeCount > 1
              ? 'S${_selectedSeason}E${epIdx + 1}'
              : (tmdb?.englishTitle ?? widget.content.title);

          if (!_torrentStreamsByEpisode.containsKey(episodeNum) && imdbId != null) {
            final streams = await TorrentService().fetchStreams(
              imdbId,
              tmdb!.mediaType,
              season: _selectedSeason,
              episode: episodeNum,
            );
            _torrentStreamsByEpisode[episodeNum] = streams;
          }

          final streams = _torrentStreamsByEpisode[episodeNum] ?? [];
          TorrentStream? picked;

          if (streams.isNotEmpty) {
            final qualityMatches =
                streams.where((s) => s.quality == _selectedQuality).toList();
            picked = qualityMatches.isNotEmpty ? qualityMatches.first : streams.first;
          }

          if (picked == null) continue;

          String? directUrl = picked.url;
          if (directUrl == null || directUrl.isEmpty) {
            if (TorBoxService().isConfigured) {
              directUrl = await TorBoxService().resolveStream(picked);
            }
          }

          if (directUrl != null && directUrl.isNotEmpty) {
            await _downloadService.startDownload(
              contentId: contentId,
              contentTitle: contentTitle,
              episodeIndex: epIdx,
              episodeName: episodeName,
              m3u8Url: directUrl,
              thumbnailUrl: posterUrl,
            );
            queuedCount++;
          }
        }
      } else {
        // VOD sources
        final episodes = _currentVodEpisodes.isNotEmpty
            ? _currentVodEpisodes
            : widget.content.episodes;

        if (episodes.isEmpty) {
          await _downloadService.startDownload(
            contentId: contentId,
            contentTitle: contentTitle,
            episodeIndex: 0,
            episodeName: contentTitle,
            m3u8Url: widget.content.m3u8Url,
            thumbnailUrl: posterUrl,
          );
          queuedCount = 1;
        } else {
          for (final epIdx in _selectedEpisodeIndices) {
            if (epIdx >= episodes.length) continue;
            final ep = episodes[epIdx];
            final epName = ep.name.isNotEmpty ? ep.name : 'Episode ${epIdx + 1}';

            await _downloadService.startDownload(
              contentId: contentId,
              contentTitle: contentTitle,
              episodeIndex: epIdx,
              episodeName: epName,
              m3u8Url: ep.url,
              thumbnailUrl: posterUrl,
            );
            queuedCount++;
          }
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1F1F1F),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            content: Row(
              children: [
                const Icon(LucideIcons.checkCircle2,
                    color: AppTheme.accent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    queuedCount > 1
                        ? 'Added $queuedCount episodes to Downloads.'
                        : 'Download started. Check My List > Downloads.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('[DownloadPicker] Error starting batch download: $e');
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start download: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);
    final isDesktop = !layout.isPhone;
    final totalEpisodes = _effectiveEpisodeCount;
    final contentTitle =
        widget.tmdb?.englishTitle ?? widget.content.title;

    return Center(
      child: Container(
        width: isDesktop ? 700 : double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * (isDesktop ? 0.86 : 0.92),
        ),
        margin: EdgeInsets.symmetric(
          horizontal: isDesktop ? 32 : 0,
          vertical: isDesktop ? 24 : 0,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF141414), // Netflix deep dark background
          borderRadius: BorderRadius.circular(isDesktop ? 16 : 0),
          border: isDesktop
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1.0,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 36,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isDesktop ? 16 : 0),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header (Netflix-styled with badge & metadata)
                _buildHeader(contentTitle),

                // Source & Quality Segmented Bar
                _buildSourceAndQualityBar(),

                const Divider(color: Color(0xFF262626), height: 1),

                // Episodes or Movie Selection Area
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppTheme.accent,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _loadingMessage,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildEpisodeSelectionArea(totalEpisodes),
                ),

                const Divider(color: Color(0xFF262626), height: 1),

                // Bottom Action Bar
                _buildBottomActionBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    final year = widget.tmdb?.year.isNotEmpty == true
        ? widget.tmdb!.year
        : widget.content.year;
    final rating = widget.tmdb?.voteAverage != null && widget.tmdb!.voteAverage > 0
        ? '${(widget.tmdb!.voteAverage * 10).toInt()}% Match'
        : '80% Match';

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF181818),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Netflix N / HY Red Tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'HY',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _isTv ? 'SERIES DOWNLOAD' : 'MOVIE DOWNLOAD',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      rating,
                      style: const TextStyle(
                        color: Color(0xFF46D369),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (year.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        year,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          HoverButton(
            onTap: () => Navigator.pop(context),
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(LucideIcons.x, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceAndQualityBar() {
    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Source Segmented Row
          Row(
            children: [
              const Text(
                'SOURCE',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (widget.isNonChineseContent)
                        _buildSourcePill(
                          source: _torrentSource,
                          isTorrent: true,
                        ),
                      ...ApiService.sources.map((s) => _buildSourcePill(source: s)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Torrent Controls (Quality Badges & Season Picker)
          if (_isTorrent) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'QUALITY',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 14),
                ...(_availableQualities.isNotEmpty
                        ? _availableQualities
                        : ['4K', '1080p', '720p'])
                    .map((q) => _buildQualityBadge(q)),
                if (_isTv && _seasonCount > 1) ...[
                  const Spacer(),
                  const Text(
                    'SEASON',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedSeason,
                        dropdownColor: const Color(0xFF222222),
                        icon: const Icon(LucideIcons.chevronDown,
                            color: Colors.white70, size: 14),
                        isDense: true,
                        items: List.generate(_seasonCount, (i) => i + 1)
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    'Season $s',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null && v != _selectedSeason) {
                            setState(() => _selectedSeason = v);
                            _loadTorrentData();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourcePill({
    required VideoSource source,
    bool isTorrent = false,
  }) {
    final isSelected = _selectedSource.name == source.name;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: HoverButton(
        onTap: () {
          if (isSelected) return;
          setState(() {
            _selectedSource = source;
          });
          if (isTorrent) {
            _loadTorrentData();
          } else {
            _loadVodEpisodes(source);
          }
        },
        backgroundColor: isSelected
            ? (isTorrent ? AppTheme.accent : const Color(0xFFE5E5E5))
            : const Color(0xFF222222),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isTorrent) ...[
                Icon(
                  LucideIcons.zap,
                  size: 13,
                  color: isSelected ? Colors.white : AppTheme.accent,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                source.name,
                style: TextStyle(
                  color: isSelected
                      ? (isTorrent ? Colors.white : Colors.black)
                      : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityBadge(String quality) {
    final isSelected = _selectedQuality == quality;
    final color = _qualityBadgeColor(quality);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: HoverButton(
        onTap: () => setState(() => _selectedQuality = quality),
        backgroundColor: isSelected
            ? color.withValues(alpha: 0.18)
            : const Color(0xFF1E1E1E),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? color : Colors.white.withValues(alpha: 0.12),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                quality,
                style: TextStyle(
                  color: isSelected ? color : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeSelectionArea(int totalEpisodes) {
    if (!_isTv) {
      // Movie selection: Clean horizontal cinematic tile
      final isDownloaded = _downloadService.isDownloaded(
        widget.tmdb?.id?.toString() ?? widget.content.title,
        0,
      );
      final isSelected = _selectedEpisodeIndices.contains(0);
      final poster = widget.tmdb?.posterUrl.isNotEmpty == true
          ? widget.tmdb!.posterUrl
          : widget.content.thumbnailUrl;

      return Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: HoverButton(
            onTap: () {
              setState(() {
                if (isSelected) {
                  _selectedEpisodeIndices.remove(0);
                } else {
                  _selectedEpisodeIndices.add(0);
                }
              });
            },
            backgroundColor: isSelected
                ? const Color(0xFF222222)
                : const Color(0xFF1A1A1A),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.accent
                      : Colors.white.withValues(alpha: 0.1),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  // Movie Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: poster.isNotEmpty
                        ? Image.network(
                            proxyImageUrl(poster),
                            width: 100,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _moviePlaceholder(),
                          )
                        : _moviePlaceholder(),
                  ),
                  const SizedBox(width: 16),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.tmdb?.englishTitle ?? widget.content.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _isTorrent ? _selectedQuality : 'HD',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Full Movie • ${_isTorrent ? 'TorBox' : _selectedSource.name}',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (isDownloaded)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF46D369).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.check,
                              color: Color(0xFF46D369), size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Downloaded',
                            style: TextStyle(
                              color: Color(0xFF46D369),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    _buildNetflixCheckbox(isSelected),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Series: Netflix-style Episode List
    final contentId = widget.tmdb?.id?.toString() ?? widget.content.title;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sub-header with episode count & Select All
          Row(
            children: [
              Text(
                'Episodes (${_selectedEpisodeIndices.length}/$totalEpisodes)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              HoverButton(
                onTap: _selectedEpisodeIndices.length == totalEpisodes
                    ? _deselectAllEpisodes
                    : _selectAllEpisodes,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _selectedEpisodeIndices.length == totalEpisodes
                            ? LucideIcons.xSquare
                            : LucideIcons.checkSquare,
                        size: 14,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _selectedEpisodeIndices.length == totalEpisodes
                            ? 'Deselect All'
                            : 'Select All',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Episodes List
          Expanded(
            child: ListView.separated(
              itemCount: totalEpisodes,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final isSelected = _selectedEpisodeIndices.contains(index);
                final downloadItem =
                    _downloadService.getDownload(contentId, index);
                final isDownloaded =
                    downloadItem?.status == DownloadStatus.completed;
                final isDownloading =
                    downloadItem?.status == DownloadStatus.downloading;

                String epName;
                String? stillPath;
                if (_isTorrent) {
                  final tmdbEp = _tmdbEpisodeDetails[index + 1];
                  epName = tmdbEp?.name.isNotEmpty == true
                      ? tmdbEp!.name
                      : 'Episode ${index + 1}';
                  stillPath = tmdbEp?.stillPath;
                } else if (index < _currentVodEpisodes.length) {
                  epName = _currentVodEpisodes[index].name.isNotEmpty
                      ? _currentVodEpisodes[index].name
                      : 'Episode ${index + 1}';
                } else {
                  epName = 'Episode ${index + 1}';
                }

                return HoverButton(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedEpisodeIndices.remove(index);
                      } else {
                        _selectedEpisodeIndices.add(index);
                      }
                    });
                  },
                  backgroundColor: isSelected
                      ? const Color(0xFF222222)
                      : const Color(0xFF1A1A1A),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.accent.withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.05),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Episode Index Number
                        SizedBox(
                          width: 28,
                          child: Text(
                            (index + 1).toString().padLeft(2, '0'),
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Mini Thumbnail (if available)
                        if (stillPath != null && stillPath.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              proxyImageUrl(
                                  'https://image.tmdb.org/t/p/w185$stillPath'),
                              width: 64,
                              height: 36,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],

                        // Title
                        Expanded(
                          child: Text(
                            epName,
                            style: TextStyle(
                              color:
                                  isSelected ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Download state / checkbox
                        if (isDownloaded)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF46D369)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Downloaded',
                              style: TextStyle(
                                color: Color(0xFF46D369),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else if (isDownloading)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4DA6FF)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Downloading...',
                              style: TextStyle(
                                color: Color(0xFF4DA6FF),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else
                          _buildNetflixCheckbox(isSelected),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetflixCheckbox(bool isChecked) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: isChecked ? AppTheme.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isChecked
              ? AppTheme.accent
              : Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: isChecked
          ? const Icon(LucideIcons.check, color: Colors.white, size: 14)
          : null,
    );
  }

  Widget _moviePlaceholder() {
    return Container(
      width: 100,
      height: 60,
      color: const Color(0xFF2B2B2B),
      child: const Icon(LucideIcons.film, color: Colors.white38, size: 24),
    );
  }

  Widget _buildBottomActionBar() {
    final count = _selectedEpisodeIndices.length;

    return Container(
      color: const Color(0xFF181818),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count ${count == 1 ? 'Episode' : 'Episodes'} Selected',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _isTorrent
                    ? 'Torrent • $_selectedQuality'
                    : 'VOD • ${_selectedSource.name}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Spacer(),
          HoverButton(
            onTap: () => Navigator.pop(context),
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _isDownloading
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Starting...',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : HoverButton(
                  onTap: count > 0 ? _startBatchDownload : () {},
                  backgroundColor:
                      count > 0 ? AppTheme.accent : const Color(0xFF333333),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 11),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.download,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Download ($count)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
