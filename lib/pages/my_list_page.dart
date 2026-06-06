import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/responsive.dart';
import '../core/proxy_url.dart';
import '../core/theme.dart';
import '../models/episode.dart';
import '../pages/video_player_screen.dart';
import '../services/download_service.dart';
import '../services/watchlist_service.dart';
import '../widgets/movie_card.dart';

class MyListPage extends StatefulWidget {
  const MyListPage({super.key});

  @override
  State<MyListPage> createState() => _MyListPageState();
}

class _MyListPageState extends State<MyListPage> {
  final _watchlistService = WatchlistService();
  final _downloadService = DownloadService();
  String _selectedList = 'My List';

  @override
  void initState() {
    super.initState();
    _watchlistService.addListener(_onListUpdated);
    _downloadService.addListener(_onListUpdated);
  }

  @override
  void dispose() {
    _watchlistService.removeListener(_onListUpdated);
    _downloadService.removeListener(_onListUpdated);
    super.dispose();
  }

  void _onListUpdated() {
    if (mounted) {
      if (!_allListNames.contains(_selectedList)) {
        _selectedList = 'My List';
      }
      setState(() {});
    }
  }

  List<String> get _allListNames => ['My Downloads', ..._watchlistService.listNames];

  void _playDownload(DownloadItem item) {
    if (item.filePath == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: item.filePath!,
          title: item.contentTitle,
          originalTitle: item.contentTitle,
          episodes: [Episode(name: item.episodeName, url: item.filePath!, imageUrl: '')],
          initialEpisodeIndex: 0,
          isTvShow: false,
          posterUrl: item.thumbnailUrl ?? '',
        ),
      ),
    );
  }

  void _showDeleteDialog(DownloadItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Delete Download', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "${item.episodeName}" from downloads?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              _downloadService.deleteDownload(item.contentId, item.episodeIndex);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  void _showCreateListDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text(
          'Create New List',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g. Weekend Binge',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.accent),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _watchlistService.createList(controller.text);
              }
              Navigator.pop(context);
            },
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);
    final lists = _allListNames;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppTheme.background.withOpacity(0.9),
            pinned: true,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'My Lists',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Container(
                height: 60,
                padding: const EdgeInsets.only(bottom: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      ...lists.map((listName) {
                        final isSelected = listName == _selectedList;
                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedList = listName),
                            child: Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.accent
                                    : AppTheme.cardLight.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.accent
                                      : Colors.white24,
                                  width: 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                children: [
                                  if (listName == 'My Downloads') ...[
                                    Icon(
                                      LucideIcons.download,
                                      size: 14,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white70,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    listName,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  if (isSelected &&
                                      listName != 'My List' &&
                                      listName != 'My Downloads') ...[
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () async => await _watchlistService.deleteList(
                                        listName,
                                      ),
                                      child: const Icon(
                                        LucideIcons.x,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      GestureDetector(
                        onTap: _showCreateListDialog,
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white38, width: 1),
                          ),
                          alignment: Alignment.center,
                          child: const Row(
                            children: [
                              Icon(
                                LucideIcons.plus,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Create List',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_selectedList == 'My Downloads')
            _buildDownloadsList(layout)
          else
            _buildWatchlistContent(layout),
        ],
      ),
    );
  }

  Widget _buildDownloadsList(ResponsiveLayout layout) {
    final allDownloads = _downloadService.items
        .where((i) =>
            i.status == DownloadStatus.completed ||
            i.status == DownloadStatus.downloading ||
            i.status == DownloadStatus.pending ||
            i.status == DownloadStatus.failed)
        .toList();

    if (allDownloads.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.download,
                size: 64,
                color: Colors.white.withOpacity(0.2),
              ),
              const SizedBox(height: 16),
              Text(
                'No downloads yet',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Download episodes to watch them offline.\nTap the download icon on any episode.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Group downloads by series
    final grouped = <String, List<DownloadItem>>{};
    for (final item in allDownloads) {
      grouped.putIfAbsent(item.contentTitle, () => []).add(item);
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, sectionIndex) {
          final seriesName = grouped.keys.elementAt(sectionIndex);
          final episodes = grouped[seriesName]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.pagePadding,
                  sectionIndex == 0 ? 16 : 24,
                  layout.pagePadding,
                  8,
                ),
                child: Text(
                  seriesName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...episodes.map((item) => _buildDownloadTile(item, layout)),
            ],
          );
        },
        childCount: grouped.length,
      ),
    );
  }

  Widget _buildDownloadTile(DownloadItem item, ResponsiveLayout layout) {
    final isDownloading = item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.pending;
    final isCompleted = item.status == DownloadStatus.completed;
    final isFailed = item.status == DownloadStatus.failed;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: layout.pagePadding,
        vertical: 4,
      ),
      child: Material(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isCompleted ? () => _playDownload(item) : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.thumbnailUrl != null &&
                          item.thumbnailUrl!.isNotEmpty
                      ? Image.network(
                          proxyImageUrl(item.thumbnailUrl!),
                          width: 80,
                          height: 45,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _downloadPlaceholder(),
                        )
                      : _downloadPlaceholder(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.episodeName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (isDownloading) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: item.progress,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                AppTheme.accent),
                            minHeight: 4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${(item.progress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: AppTheme.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (item.speed > 0)
                              Text(
                                _formatSpeed(item.speed),
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            const Spacer(),
                            if (item.etaSeconds > 0)
                              Text(
                                _formatEta(item.etaSeconds),
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ] else if (isFailed)
                        const Text(
                          'Download failed - tap retry',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                          ),
                        )
                      else
                        const Text(
                          'Downloaded',
                          style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isDownloading)
                  GestureDetector(
                    onTap: () => _downloadService.cancelDownload(
                        item.contentId, item.episodeIndex),
                    child: const Icon(
                      LucideIcons.xCircle,
                      color: AppTheme.textSecondary,
                      size: 22,
                    ),
                  )
                else if (isFailed) ...[
                  GestureDetector(
                    onTap: () => _downloadService.retryDownload(
                      contentId: item.contentId,
                      contentTitle: item.contentTitle,
                      episodeIndex: item.episodeIndex,
                      episodeName: item.episodeName,
                      m3u8Url: item.m3u8Url,
                      thumbnailUrl: item.thumbnailUrl,
                    ),
                    child: const Icon(
                      LucideIcons.refreshCw,
                      color: Colors.orange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _showDeleteDialog(item),
                    child: const Icon(
                      LucideIcons.trash2,
                      color: AppTheme.textSecondary,
                      size: 18,
                    ),
                  ),
                ] else ...[
                  const Icon(
                    LucideIcons.playCircle,
                    color: AppTheme.textSecondary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _showDeleteDialog(item),
                    child: const Icon(
                      LucideIcons.trash2,
                      color: AppTheme.textSecondary,
                      size: 18,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '';
    if (bytesPerSecond < 1024) return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _formatEta(int seconds) {
    if (seconds <= 0) return '';
    if (seconds < 60) return '${seconds}s left';
    if (seconds < 3600) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return '${m}m ${s}s left';
    }
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return '${h}h ${m}m left';
  }

  Widget _downloadPlaceholder() {
    return Container(
      width: 80,
      height: 45,
      decoration: BoxDecoration(
        color: AppTheme.cardLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        LucideIcons.download,
        color: AppTheme.textSecondary,
        size: 18,
      ),
    );
  }

  Widget _buildWatchlistContent(ResponsiveLayout layout) {
    final items = _watchlistService.getListItems(_selectedList);

    if (items.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.listPlus,
                size: 64,
                color: Colors.white.withOpacity(0.2),
              ),
              const SizedBox(height: 16),
              Text(
                'Your list is empty',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add shows and movies to keep track\nof what you want to watch.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: layout.pagePadding,
        vertical: 16,
      ),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: layout.gridMaxExtent(
            compact: 144,
            tablet: 160,
            desktop: 170,
          ),
          childAspectRatio: 0.52,
          crossAxisSpacing: layout.isPhone ? 12 : 16,
          mainAxisSpacing: layout.isPhone ? 16 : 24,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = items[index];
          return Stack(
            children: [
              MovieCard(
                content: item,
                width: null,
                margin: EdgeInsets.zero,
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () async => await _watchlistService.removeFromList(
                    _selectedList,
                    item.title,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.x,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          );
        }, childCount: items.length),
      ),
    );
  }
}
