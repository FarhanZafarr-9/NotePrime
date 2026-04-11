import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:ntsapp/utils/common.dart';
import 'package:ntsapp/utils/enums.dart';
import 'package:video_player/video_player.dart';
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
            ? ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: InteractiveViewer(
                  maxScale: 3.5,
                  child: Image.file(
                    File(item.data!["path"]),
                    fit: BoxFit.contain,
                  ),
                ),
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
    return Padding(
      padding: const EdgeInsets.all(16),
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Video(controller: controller),
      ),
    );
  }
}
