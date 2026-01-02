import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:path/path.dart' as p;
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../logic/filter_controller.dart';
import '../../logic/library_controller.dart';
import '../../services/natural_language_service.dart';

class SliverVideoGrid extends ConsumerWidget {
  const SliverVideoGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videosAsync = ref.watch(filteredVideosProvider);
    
    return videosAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: ProgressCircle()),
        ),
      ),
      error: (err, stack) => SliverToBoxAdapter(
        child: Center(child: Text('Error: $err')),
      ),
      data: (videos) {
        if (videos.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 50),
              child: Center(child: Text("No videos found.")),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 350,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              mainAxisExtent: 280,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => VideoGridItem(
                key: ValueKey(videos[index].id),
                video: videos[index],
              ),
              childCount: videos.length,
            ),
          ),
        );
      },
    );
  }
}

class VideoGridItem extends StatefulWidget {
  final Video video;
  const VideoGridItem({super.key, required this.video});

  @override
  State<VideoGridItem> createState() => _VideoGridItemState();
}

class _VideoGridItemState extends State<VideoGridItem> {
  bool _isHovering = false;
  bool _isThumbnailHovering = false;
  final TextEditingController _tagController = TextEditingController();

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final video = widget.video;
      final theme = MacosTheme.of(context);
      
      return MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: Container(
          decoration: BoxDecoration(
            color: theme.canvasColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isHovering ? theme.primaryColor : theme.dividerColor,
              width: _isHovering ? 2 : 1,
            ),
            boxShadow: _isHovering ? [
              BoxShadow(
                color: theme.primaryColor.withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Thumbnail area
              Expanded(
                flex: 4,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _isThumbnailHovering = true),
                  onExit: (_) => setState(() => _isThumbnailHovering = false),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                        child: video.thumbnailBlob != null
                            ? Image.memory(video.thumbnailBlob!, fit: BoxFit.cover)
                            : Container(
                                color: MacosColors.black,
                                child: const Icon(CupertinoIcons.play_circle, color: MacosColors.white, size: 40),
                              ),
                      ),
                      // Hover Details Overlay
                      if (_isThumbnailHovering)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: MacosColors.black.withOpacity(0.85),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: SingleChildScrollView(
                              child: Text(
                                _getMetaDescription(video.metadataJson),
                                style: const TextStyle(color: MacosColors.white, fontSize: 11, height: 1.3),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Content area
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MacosTooltip(
                        message: video.title,
                        child: Text(
                          video.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.typography.body.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _buildActions(ref),
                          const SizedBox(width: 8),
                          Text(
                            _formatDuration(video.duration),
                            style: theme.typography.caption1.copyWith(
                              color: theme.typography.caption1.color?.withOpacity(0.5),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Folder Path (above tags)
                      _FolderPathWidget(video: video),
                      // Tags Section
                      Expanded(
                        child: _VideoTagList(videoId: video.id),
                      ),
                      const SizedBox(height: 4),
                      // Add Tag Input
                      _buildTagInput(ref),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildActions(WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Favorite
        MacosIconButton(
          padding: EdgeInsets.zero,
          icon: Icon(
            widget.video.isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            color: widget.video.isFavorite ? MacosColors.appleRed : null,
            size: 16,
          ),
          onPressed: () => ref.read(videosDaoProvider).toggleFavorite(widget.video.id, widget.video.isFavorite),
        ),
        // Play
        MacosIconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(CupertinoIcons.play_fill, size: 16),
          onPressed: () => launchUrl(Uri.file(widget.video.absolutePath)),
        ),
        // Finder
        MacosIconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(CupertinoIcons.folder, size: 16),
          onPressed: () => NaturalLanguageService().openInFinder(widget.video.absolutePath),
        ),
        // Delete
        MacosIconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(CupertinoIcons.trash, size: 16),
          onPressed: () => _confirmDelete(ref),
        ),
      ],
    );
  }

  Widget _buildTagInput(WidgetRef ref) {
    return Container(
      height: 24,
      child: MacosTextField(
        controller: _tagController,
        placeholder: 'Add tags (comma-separated)...',
        placeholderStyle: const TextStyle(color: MacosColors.systemGrayColor),
        style: const TextStyle(fontSize: 11),
        onSubmitted: (val) async {
          if (val.trim().isNotEmpty) {
            // Split by comma and process each tag
            final tags = val.split(',')
                .map((t) => t.trim())
                .where((t) => t.isNotEmpty)
                .toSet(); // Use Set to discard duplicates
            
            for (final tag in tags) {
              await ref.read(tagsDaoProvider).insertTag(TagsCompanion.insert(
                videoId: widget.video.id,
                tagText: tag,
                source: const Value('user'),
              ));
            }
            _tagController.clear();
          }
        },
      ),
    );
  }

  void _confirmDelete(WidgetRef ref) {
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.film),
        title: const Text('Delete Video?'),
        message: Text('This will permanently delete ${widget.video.title} from your disk.'),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: const Text('Delete'),
          onPressed: () {
            ref.read(libraryControllerProvider.notifier).deleteVideo(widget.video.id);
            Navigator.of(context).pop();
          },
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  String _getMetaDescription(String json) {
    try {
      final data = jsonDecode(json);
      final raw = data['raw'] ?? {};
      final format = raw['format'] ?? {};
      final tags = format['tags'] ?? {};
      
      final description = tags['description'];
      if (description != null && description.toString().isNotEmpty) {
        return description.toString();
      }
      
      final streams = raw['streams'] as List?;
      if (streams != null && streams.isNotEmpty) {
        final v = streams.firstWhere((s) => s['codec_type'] == 'video', orElse: () => null);
        if (v != null) {
          return "Codec: ${v['codec_name']}\nRes: ${v['width']}x${v['height']}\nFrame: ${v['avg_frame_rate']}\nBitrate: ${data['bitrate']} bps";
        }
      }
    } catch (_) {}
    return "No description available.";
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _VideoTagList extends ConsumerWidget {
  final int videoId;
  const _VideoTagList({required this.videoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsStream = ref.watch(tagsDaoProvider).watchTagsForVideo(videoId);
    
    return StreamBuilder<List<Tag>>(
      stream: tagsStream,
      builder: (context, snapshot) {
        final tags = snapshot.data ?? [];
        if (tags.isEmpty) return const SizedBox();
        
        return SingleChildScrollView(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: tags.map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: MacosTheme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: MacosTheme.of(context).primaryColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.tagText, style: const TextStyle(fontSize: 10)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => ref.read(tagsDaoProvider).deleteTag(videoId, t.tagText),
                    child: const Icon(CupertinoIcons.xmark, size: 8),
                  ),
                ],
              ),
            )).toList(),
          ),
        );
      }
    );
  }
}

class _FolderPathWidget extends ConsumerWidget {
  final Video video;
  const _FolderPathWidget({required this.video});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(foldersDaoProvider).getAllFolders();
    
    return FutureBuilder<List<Folder>>(
      future: foldersAsync,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        
        final folders = snapshot.data!;
        final folder = folders.where((f) => f.id == video.folderId).firstOrNull;
        if (folder == null) return const SizedBox();
        
        final relativePath = _getRelativeFolderPath(video.absolutePath, folder.path);
        if (relativePath.isEmpty) return const SizedBox();
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: GestureDetector(
            onTap: () => ref.read(searchQueryProvider.notifier).set(relativePath),
            child: MacosTooltip(
              message: 'Click to filter by folder: $relativePath',
              child: Text(
                relativePath,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      },
    );
  }

  String _getRelativeFolderPath(String absolutePath, String rootPath) {
    final videoDir = p.dirname(absolutePath);
    if (videoDir == rootPath || !videoDir.startsWith(rootPath)) {
      return ''; // Video is at root level
    }
    
    final relativePath = videoDir.substring(rootPath.length);
    // Remove leading separator and split
    final parts = relativePath.split(p.separator).where((s) => s.isNotEmpty);
    
    // Convert each part to Title Case
    final titleCased = parts.map((part) => _toTitleCase(part));
    
    return titleCased.join(' / ');
  }

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}
