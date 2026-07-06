import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/torrent_service.dart';

/// Shows a bottom sheet with available torrent streams.
/// Returns the selected TorrentStream, or null if dismissed.
Future<TorrentStream?> showStreamPicker(
  BuildContext context,
  List<TorrentStream> streams,
) {
  return showModalBottomSheet<TorrentStream>(
    context: context,
    backgroundColor: AppTheme.cardDark,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _StreamPickerSheet(streams: streams),
  );
}

class _StreamPickerSheet extends StatelessWidget {
  final List<TorrentStream> streams;

  const _StreamPickerSheet({required this.streams});

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.6;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Row(
              children: [
                const Text(
                  'Select Stream',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                Text(
                  '${streams.length} available',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: streams.length,
              itemBuilder: (context, index) => _StreamTile(
                stream: streams[index],
                onTap: () => Navigator.pop(context, streams[index]),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _StreamTile extends StatelessWidget {
  final TorrentStream stream;
  final VoidCallback onTap;

  const _StreamTile({required this.stream, required this.onTap});

  Color _qualityColor(String quality) {
    switch (quality) {
      case '4K':
        return const Color(0xFFE50914);
      case '1080p':
        return const Color(0xFF46D369);
      case '720p':
        return const Color(0xFF4DA6FF);
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            // Quality badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _qualityColor(stream.quality).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _qualityColor(stream.quality).withOpacity(0.4),
                ),
              ),
              child: Text(
                stream.quality,
                style: TextStyle(
                  color: _qualityColor(stream.quality),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            if (stream.isHDR) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
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
            // Source badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: stream.url != null 
                    ? Colors.cyan.withOpacity(0.15) 
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: stream.url != null 
                      ? Colors.cyan.withOpacity(0.4) 
                      : Colors.grey.withOpacity(0.2),
                ),
              ),
              child: Text(
                stream.source.isNotEmpty ? stream.source : 'Torrent',
                style: TextStyle(
                  color: stream.url != null ? Colors.cyanAccent : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Seeders
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
            const SizedBox(width: 12),
            // Size
            Icon(Icons.storage, color: AppTheme.textSecondary, size: 14),
            const SizedBox(width: 4),
            Text(
              stream.size.isNotEmpty ? stream.size : '–',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                decoration: TextDecoration.none,
              ),
            ),
            const Spacer(),
            // Play icon
            const Icon(
              Icons.play_circle_outline,
              color: AppTheme.textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
