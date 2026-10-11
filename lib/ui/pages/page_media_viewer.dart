import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:ntsapp/utils/common.dart';
import 'package:ntsapp/utils/enums.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/model_item.dart';

class PageMediaViewer extends StatefulWidget {
  final bool runningOnDesktop;
  final Function(PageType, bool, PageParams)? setShowHidePage;
  final String id;
  final String groupId;
  final int index;
  final int count;

  const PageMediaViewer(
      {super.key,
      required this.id,
      required this.groupId,
      required this.index,
      required this.count,
      required this.runningOnDesktop,
      this.setShowHidePage});

  @override
  State<PageMediaViewer> createState() => _PageMediaViewerState();
}

class _PageMediaViewerState extends State<PageMediaViewer> {
  late PageController _pageController;
  ModelItem? currentItem;
  ModelItem? previousItem;
  ModelItem? nextItem;
  late String currentId;
  late int currentIndex;
  late int mediaCount;
  late String groupId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.index);
    currentId = widget.id;
    currentIndex = widget.index;
    mediaCount = widget.count;
    groupId = widget.groupId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadItems();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _saveToDownloads(String filePath) async {
    Directory? directory;
    if (Platform.isAndroid) {
      directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        directory = await getExternalStorageDirectory();
      }
    } else if (Platform.isIOS) {
      directory = await getApplicationDocumentsDirectory();
    } else {
      directory = await getDownloadsDirectory();
    }

    if (directory != null && await directory.exists()) {
      File file = File(filePath);
      if (await file.exists()) {
        try {
          String newPath =
              "${directory.path}/${DateTime.now().millisecondsSinceEpoch}_${file.uri.pathSegments.last}";
          await file.copy(newPath);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saved to Downloads!')));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to save file: $e')));
          }
        }
      }
    }
  }

  void loadItems() async {
    ModelItem? currentModelItem = await ModelItem.get(currentId);
    previousItem =
        await ModelItem.getPreviousMediaItemInGroup(groupId, currentId);
    nextItem = await ModelItem.getNextMediaItemInGroup(groupId, currentId);
    setState(() {
      currentItem = currentModelItem;
    });
  }

  void indexChanged(int index) async {
    if (index > currentIndex) {
      // Next Item
      previousItem = currentItem;
      currentItem = nextItem;
      currentId = currentItem!.id!;
      ModelItem? item =
          await ModelItem.getNextMediaItemInGroup(groupId, currentId);
      if (item != null) {
        nextItem = item;
      }
    } else if (index < currentIndex) {
      // Previous Item
      nextItem = currentItem;
      currentItem = previousItem;
      currentId = currentItem!.id!;
      ModelItem? item =
          await ModelItem.getPreviousMediaItemInGroup(groupId, currentId);
      if (item != null) {
        previousItem = item;
      }
    }
    currentIndex = index;
    if (mounted) setState(() {});
  }

  ModelItem? getItem(int index) {
    ModelItem? item;
    if (index == currentIndex) {
      item = currentItem;
    } else if (index > currentIndex) {
      // Next Item
      item = nextItem;
    } else if (index < currentIndex) {
      // Previous Item
      item = previousItem;
    }
    return item;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        title: Text(
          currentItem == null ? "Media" : "${currentIndex + 1} / $mediaCount",
          style: const TextStyle(fontSize: 15),
        ),
        leading: widget.runningOnDesktop
            ? BackButton(
                onPressed: () {
                  widget.setShowHidePage!(
                      PageType.mediaViewer, false, PageParams());
                },
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.folderOpen),
            tooltip: 'Open in gallery/app',
            onPressed: () {
              if (currentItem != null && currentItem!.data != null) {
                final path = currentItem!.data!["path"];
                if (path != null) {
                  openMedia(path);
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.download),
            tooltip: 'Download',
            onPressed: () {
              if (currentItem != null && currentItem!.data != null) {
                final path = currentItem!.data!["path"];
                if (path != null) {
                  _saveToDownloads(path);
                }
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageView.builder(
        itemCount: mediaCount,
        controller: _pageController,
        scrollDirection: Axis.horizontal,
        onPageChanged: (value) => indexChanged(value),
        itemBuilder: (context, index) => _buildPage(index),
      ),
    );
  }

  // Builds each page with content based on the index
  Widget _buildPage(int index) {
    ModelItem? item = getItem(index);
    if (item == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(child: renderMedia(item)),
    );
  }

  Widget renderMedia(ModelItem item) {
    bool fileAvailable = false;

    if (item.data != null) {
      File file = File(item.data!["path"]);
      fileAvailable = file.existsSync();
    }
    Widget widget = const SizedBox.shrink();
    switch (item.type) {
      case ItemType.image: // image
        widget = fileAvailable
            ? WidgetImageViewer(
                imagePath: item.data!["path"],
                imgWidth: item.data!["width"]?.toDouble(),
                imgHeight: item.data!["height"]?.toDouble(),
              )
            : item.thumbnail != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.memory(
                      item.thumbnail!,
                      fit: BoxFit.contain,
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      "assets/image.webp",
                      fit: BoxFit.contain,
                    ),
                  );
      case ItemType.video: // video
        widget = fileAvailable
            ? canUseVideoPlayer
                ? WidgetVideoPlayer(videoPath: item.data!["path"])
                : WidgetMediaKitPlayer(videoPath: item.data!["path"])
            : ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  "assets/image.webp",
                  fit: BoxFit.contain,
                ),
              );
      default:
        widget = const SizedBox.shrink();
    }
    return widget;
  }
}

class WidgetImageViewer extends StatelessWidget {
  final String imagePath;
  final double? imgWidth;
  final double? imgHeight;

  const WidgetImageViewer({
    super.key,
    required this.imagePath,
    this.imgWidth,
    this.imgHeight,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (imgWidth != null &&
            imgHeight != null &&
            imgWidth! > 0 &&
            imgHeight! > 0) {
          final double heightFactor = imgHeight! / constraints.maxHeight;
          final double widthFactor = imgWidth! / constraints.maxWidth;

          // An image is exceptionally tall only if its height substantially exceeds the screen height (>= 1.5x)
          // AND it naturally outstretches vertically much more than it does horizontally compared to the view.
          bool isExceptionallyTall =
              heightFactor >= 1.5 && heightFactor >= widthFactor * 1.5;
          bool isExceptionallyWide =
              widthFactor >= 1.5 && widthFactor >= heightFactor * 1.8;

          // Exceptionally tall image -> Scroll vertically without pinch-zoom
          if (isExceptionallyTall) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.fitWidth,
                  ),
                ),
              ),
            );
          }

          // Exceptionally wide image -> Scroll horizontally without pinch-zoom
          if (isExceptionallyWide) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.fitHeight,
                  ),
                ),
              ),
            );
          }
        }

        // Regular proportion image
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.file(
            File(imagePath),
            fit: BoxFit.scaleDown,
          ),
        );
      },
    );
  }
}

class WidgetVideoPlayer extends StatefulWidget {
  final String videoPath;

  const WidgetVideoPlayer({super.key, required this.videoPath});

  @override
  State<WidgetVideoPlayer> createState() => _WidgetVideoPlayerState();
}

class _WidgetVideoPlayerState extends State<WidgetVideoPlayer> {
  late final VideoPlayerController _controller;
  ChewieController? _chewieController;
  bool _showControls = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath));
    initialize();
  }

  Future<void> initialize() async {
    await _controller.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _controller,
      autoPlay: true,
      looping: true,
      showControls: false,
    );
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: GestureDetector(
            onTap: () {
              if (_chewieController == null) return;
              setState(() {
                _showControls = !_showControls;
                _chewieController = _chewieController!.copyWith(
                  showControls: _showControls,
                );
              });
            },
            child: _chewieController == null
                ? const SizedBox.shrink()
                : Chewie(controller: _chewieController!),
          ),
        ),
      ),
    );
  }
}

class WidgetMediaKitPlayer extends StatefulWidget {
  final String videoPath;
  const WidgetMediaKitPlayer({super.key, required this.videoPath});

  @override
  State<WidgetMediaKitPlayer> createState() => _WidgetMediaKitPlayerState();
}

class _WidgetMediaKitPlayerState extends State<WidgetMediaKitPlayer> {
  // Create a [Player] to control playback.
  final player = Player();
  // Create a [VideoController] to handle video output from [Player].
  late final controller = VideoController(player);

  @override
  void initState() {
    super.initState();
    player.open(
      Media(widget.videoPath),
    );
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Video(controller: controller),
      ),
    );
  }
}
