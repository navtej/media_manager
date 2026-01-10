import 'dart:convert';
import 'package:flutter/cupertino.dart';
// import 'package:flutter/material.dart'; // Unnecessary
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
// import 'package:url_launcher/url_launcher.dart'; // Unused
import 'package:flutter/services.dart';
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
                color: theme.primaryColor.withValues(alpha: 0.2),
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
                              color: MacosColors.black.withValues(alpha: 0.85),
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
                              color: theme.typography.caption1.color?.withValues(alpha: 0.5),
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
                      _TagAutocompleteInput(video: video),
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
          onPressed: () => NaturalLanguageService().playVideo(widget.video.absolutePath),
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

  // Removed _buildTagInput and replaced with _TagAutocompleteInput class below

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
            children: tags.map((t) {
              final isSelected = ref.watch(combinedSelectedTagsProvider).contains(t.tagText);
              return GestureDetector(
                onTap: () => ref.read(primarySelectedTagsProvider.notifier).toggle(t.tagText),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? MacosTheme.of(context).primaryColor 
                        : MacosTheme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: MacosTheme.of(context).primaryColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.tagText, 
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected ? MacosColors.white : null,
                        )
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => ref.read(tagsDaoProvider).deleteTag(videoId, t.tagText),
                        child: Icon(
                          CupertinoIcons.trash, 
                          size: 8,
                          color: isSelected ? MacosColors.white.withOpacity(0.8) : null,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
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

class _TagAutocompleteInput extends ConsumerStatefulWidget {
  final Video video;
  const _TagAutocompleteInput({required this.video});

  @override
  ConsumerState<_TagAutocompleteInput> createState() => _TagAutocompleteInputState();
}

class _TagAutocompleteInputState extends ConsumerState<_TagAutocompleteInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<String> _suggestions = [];
  int _selectedIndex = -1;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _hideOverlay();
    _focusNode.removeListener(_onFocusChanged);
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _hideOverlay();
    }
  }

  void _onTextChanged() {
    final text = _controller.text;
    if (text.isEmpty) {
      _hideOverlay();
      return;
    }

    // Get the last part after comma
    final parts = text.split(',');
    final query = parts.last.trim().toLowerCase();

    if (query.isEmpty) {
      _hideOverlay();
      return;
    }

    final allTagsAsync = ref.read(allUniqueTagsProvider);
    final allTags = allTagsAsync.value ?? [];
    
    final filtered = allTags
        .where((tag) => tag.toLowerCase().contains(query))
        .take(5)
        .toList();

    if (filtered.isNotEmpty) {
      setState(() {
        _suggestions = filtered;
        _selectedIndex = -1;
      });
      _showOverlay();
    } else {
      _hideOverlay();
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) {
        final theme = MacosTheme.of(context);
        return Positioned(
          width: 200,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 4), // Show BELOW input
            followerAnchor: Alignment.topLeft,
            targetAnchor: Alignment.bottomLeft,
            child: TapRegion(
              onTapOutside: (_) => _hideOverlay(),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.canvasColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.dividerColor),
                  boxShadow: [
                    BoxShadow(
                      color: MacosColors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _suggestions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final tag = entry.value;
                    final isHighlighted = index == _selectedIndex;

                    return MouseRegion(
                      onEnter: (_) => setState(() => _selectedIndex = index),
                      child: GestureDetector(
                        onTap: () => _selectTag(tag),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isHighlighted ? theme.primaryColor.withValues(alpha: 0.1) : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 10,
                              color: isHighlighted ? theme.primaryColor : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selectTag(String tag) {
    final text = _controller.text;
    final parts = text.split(',');
    parts.removeLast();
    parts.add(tag);
    
    final newText = '${parts.join(', ')}, ';
    _controller.text = newText;
    _controller.selection = TextSelection.fromPosition(TextPosition(offset: newText.length));
    
    _hideOverlay();
    _focusNode.requestFocus();
  }

  Future<void> _submitTags() async {
    final val = _controller.text;
    if (val.trim().isNotEmpty) {
      final tags = val.split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toSet();
      
      for (final tag in tags) {
        await ref.read(tagsDaoProvider).insertTag(TagsCompanion.insert(
          videoId: widget.video.id,
          tagText: tag,
          source: const Value('user'),
        ));
      }
      _controller.clear();
      _hideOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch to keep the provider alive and ensure data is ready
    ref.watch(allUniqueTagsProvider);

    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        height: 24,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                if (_overlayEntry != null && _suggestions.isNotEmpty) {
                  setState(() {
                    _selectedIndex = (_selectedIndex + 1) % _suggestions.length;
                  });
                  _overlayEntry!.markNeedsBuild();
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                if (_overlayEntry != null && _suggestions.isNotEmpty) {
                  setState(() {
                    _selectedIndex = (_selectedIndex - 1 + _suggestions.length) % _suggestions.length;
                  });
                  _overlayEntry!.markNeedsBuild();
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                if (_overlayEntry != null && _selectedIndex != -1) {
                  _selectTag(_suggestions[_selectedIndex]);
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                if (_overlayEntry != null) {
                  _hideOverlay();
                  return KeyEventResult.handled;
                }
              }
            }
            return KeyEventResult.ignored;
          },
          child: MacosTextField(
            controller: _controller,
            focusNode: _focusNode,
            placeholder: 'Add tags...',
            placeholderStyle: const TextStyle(color: MacosColors.systemGrayColor),
            style: const TextStyle(fontSize: 11),
            onSubmitted: (_) => _submitTags(),
          ),
        ),
      ),
    );
  }
}
