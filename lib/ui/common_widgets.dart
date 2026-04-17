import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:ntsapp/services/service_logger.dart';
import 'package:ntsapp/ui/widgets_item.dart';
import 'package:provider/provider.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../utils/common.dart';
import '../utils/enums.dart';
import '../models/model_category_group.dart';
import '../models/model_item.dart';
import '../utils/utils_crypto.dart';

class MessageInCenter extends StatelessWidget {
  final String text;

  const MessageInCenter({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(text),
          ),
        ],
      ),
    );
  }
}

class PrivacyShield extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final bool isEnabled;
  final VoidCallback? onLongPress;

  const PrivacyShield({
    super.key,
    required this.child,
    required this.borderRadius,
    this.isEnabled = true,
    this.onLongPress,
  });

  @override
  State<PrivacyShield> createState() => _PrivacyShieldState();
}

class _PrivacyShieldState extends State<PrivacyShield> {
  bool _isRevealed = false;
  Timer? _timer;

  void _reveal() {
    if (_isRevealed) return;
    setState(() => _isRevealed = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isRevealed = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEnabled) return widget.child;

    return GestureDetector(
      onTap: _reveal,
      onLongPress: widget.onLongPress != null
          ? (_isRevealed ? widget.onLongPress : () {})
          : null,
      behavior: HitTestBehavior.opaque,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        tween: Tween<double>(begin: _isRevealed ? 0 : 1, end: _isRevealed ? 0 : 1),
        builder: (context, value, child) {
          final sigma = value * 16.0;
          return Stack(
            children: [
              // Content with stable ImageFiltered blur
              ClipRRect(
                borderRadius: widget.borderRadius,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: sigma,
                    sigmaY: sigma,
                  ),
                  child: AbsorbPointer(
                    absorbing: !_isRevealed,
                    child: widget.child,
                  ),
                ),
              ),
              // Clean Gradient Overlay matching the shape
              if (value > 0)
                Positioned.fill(
                  child: Opacity(
                    opacity: value,
                    child: ClipRRect(
                      borderRadius: widget.borderRadius,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withValues(alpha: 0.4),
                              Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withValues(alpha: 0.1),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}


class FloatingActionButtonWithBadge extends StatelessWidget {
  final int filterCount;
  final VoidCallback onPressed;
  final Icon icon;
  final String heroTag;

  const FloatingActionButtonWithBadge({
    super.key,
    required this.filterCount,
    required this.onPressed,
    required this.icon,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topRight,
      clipBehavior:
          Clip.none, // Allows the badge to be positioned outside the FAB
      children: [
        FloatingActionButton(
          heroTag: heroTag,
          shape: const ContinuousRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(28))),
          onPressed: onPressed,
          child: icon,
        ),
        if (filterCount > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
                border:
                    Border.all(color: Theme.of(context).colorScheme.onError),
              ),
              constraints: const BoxConstraints(
                minWidth: 20,
                minHeight: 20,
              ),
              child: Text(
                '$filterCount',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onError,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class WidgetKeyValueTable extends StatelessWidget {
  final Map data;

  const WidgetKeyValueTable({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(), // Column for keys
        1: IntrinsicColumnWidth(), // Column for values
      },
      children: data.entries.map((entry) {
        return TableRow(
          children: [
            Container(
              padding: const EdgeInsets.all(11.0),
              child: Text(
                capitalize(entry.key),
                textAlign: TextAlign.right,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                entry.value.toString(),
                textAlign: TextAlign.left,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class WidgetCategoryGroupAvatar extends StatelessWidget {
  final String type;
  final Uint8List? thumbnail;
  final double size;
  final String color;
  final String title;

  const WidgetCategoryGroupAvatar(
      {super.key,
      required this.type,
      required this.size,
      this.thumbnail,
      required this.color,
      required this.title});

  @override
  Widget build(BuildContext context) {
    final parsedColor = colorFromHex(color);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: parsedColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Icon(
          type == "group" ? Icons.circle : Icons.workspaces,
          size: type == "group" ? 14 : 20,
          color: parsedColor,
        ),
      ),
    );
  }
}

class WidgetCategoryGroup extends StatelessWidget {
  final ModelCategoryGroup categoryGroup;
  final bool showSummary;
  final bool showCategorySign;

  const WidgetCategoryGroup(
      {super.key,
      required this.categoryGroup,
      required this.showSummary,
      required this.showCategorySign});

  @override
  Widget build(BuildContext context) {
    double size = 40;
    return ListTile(
      leading: WidgetCategoryGroupAvatar(
        type: categoryGroup.type,
        size: size,
        color: categoryGroup.color,
        title: categoryGroup.title,
        thumbnail: categoryGroup.thumbnail,
      ),
      horizontalTitleGap: 20.0,
      title: Row(
        children: [
          Expanded(
            child: Text(
              categoryGroup.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  letterSpacing: 0,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
      subtitle: showSummary
          ? categoryGroup.type == "group"
              ? NotePreviewSummary(
                  item: categoryGroup.group!.lastItem,
                  showImagePreview: false,
                  expanded: true,
                )
              : Text(
                  (categoryGroup.category!.groupCount == 1)
                      ? "${categoryGroup.category!.groupCount} note group"
                      : "${categoryGroup.category!.groupCount} note groups",
                  overflow: TextOverflow.ellipsis, // Ellipsis for long text
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                )
          : const SizedBox.shrink(),
      trailing: categoryGroup.type == "category"
          ? showCategorySign
              ? Icon(
                  LucideIcons.chevronRight,
                  color: Theme.of(context).colorScheme.outlineVariant,
                )
              : const SizedBox.shrink()
          : const SizedBox.shrink(),
    );
  }
}

class WidgetVideoImageThumbnail extends StatefulWidget {
  final VoidCallback onPressed;
  final ModelItem item;
  final double iconSize;

  const WidgetVideoImageThumbnail(
      {super.key,
      required this.item,
      required this.iconSize,
      required this.onPressed});

  @override
  State<WidgetVideoImageThumbnail> createState() =>
      _WidgetVideoImageThumbnailState();
}

class _WidgetVideoImageThumbnailState extends State<WidgetVideoImageThumbnail> {
  @override
  Widget build(BuildContext context) {
    bool showPlay = widget.item.state != SyncState.downloadable.value;
    ModelItem item = widget.item;
    return Stack(
      alignment: Alignment.center, // Center the play button overlay
      children: [
        AspectRatio(
          aspectRatio: item.data == null ? 16 / 9 : item.data!['aspect'],
          child: Image.memory(
            item.thumbnail!,
            width: double.infinity, // Full width of container
            fit: BoxFit.cover,
          ),
        ),
        // Play button overlay
        VideoPlayDownloadButton(
            iconSize: widget.iconSize,
            onPressed: widget.onPressed,
            showPlay: showPlay),
      ],
    );
  }
}

class WidgetVideoPlayerThumbnail extends StatefulWidget {
  final VoidCallback onPressed;
  final ModelItem item;
  final double iconSize;

  const WidgetVideoPlayerThumbnail(
      {super.key,
      required this.item,
      required this.iconSize,
      required this.onPressed});

  @override
  State<WidgetVideoPlayerThumbnail> createState() =>
      _WidgetVideoPlayerThumbnailState();
}

class _WidgetVideoPlayerThumbnailState
    extends State<WidgetVideoPlayerThumbnail> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _fileAvailable = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    String videoPath = widget.item.data!["path"];
    File videoFile = File(videoPath);
    if (videoFile.existsSync()) {
      _fileAvailable = true;
      _controller = VideoPlayerController.file(File(videoPath));
      // Initialize the controller and display the first frame as a thumbnail
      await _controller.initialize();
      await _controller.setLooping(false); // No looping
      await _controller.pause(); // Pause to display the first frame
    }

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool showPlay = widget.item.state != SyncState.downloadable.value;
    return _isInitialized
        ? _fileAvailable
            ? Stack(
                alignment: Alignment.center, // Center the play button overlay
                children: [
                  AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                  // Play button overlay
                  VideoPlayDownloadButton(
                      iconSize: widget.iconSize,
                      onPressed: widget.onPressed,
                      showPlay: showPlay),
                ],
              )
            : Image.asset(
                // handle downloading with icon
                'assets/image.webp',
                fit: BoxFit
                    .cover, // Ensures the image covers the available space
              )
        : const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(child: CircularProgressIndicator()),
          );
  }
}

class WidgetMediaKitThumbnail extends StatefulWidget {
  final VoidCallback onPressed;
  final ModelItem item;
  final double iconSize;

  const WidgetMediaKitThumbnail(
      {super.key,
      required this.item,
      required this.iconSize,
      required this.onPressed});

  @override
  State<WidgetMediaKitThumbnail> createState() =>
      _WidgetMediaKitThumbnailState();
}

class _WidgetMediaKitThumbnailState extends State<WidgetMediaKitThumbnail> {
  // Create a [Player] to control playback.
  late final player = Player();

  // Create a [VideoController] to handle video output from [Player].
  late final controller = VideoController(player);

  bool _isInitialized = false;
  bool _fileAvailable = false;

  @override
  void initState() {
    super.initState();
    if (widget.item.data != null) {
      String videoPath = widget.item.data!["path"];
      File videoFile = File(videoPath);
      if (videoFile.existsSync()) {
        _fileAvailable = true;
        player.open(Media(videoPath), play: false);
      }
    }
    _isInitialized = true;
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool showPlay = widget.item.state != SyncState.downloadable.value;
    return _isInitialized
        ? _fileAvailable
            ? Stack(
                alignment: Alignment.center, // Center the play button overlay
                children: [
                  AspectRatio(
                    aspectRatio: widget.item.data == null
                        ? 1 / 1
                        : widget.item.data!["aspect"],
                    child: Video(
                      controller: controller,
                      controls: NoVideoControls,
                    ),
                  ),
                  // Play button overlay
                  VideoPlayDownloadButton(
                      iconSize: widget.iconSize,
                      onPressed: widget.onPressed,
                      showPlay: showPlay),
                ],
              )
            : Image.asset(
                // handle downloading with icon
                'assets/image.webp',
                fit: BoxFit
                    .cover, // Ensures the image covers the available space
              )
        : const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(child: CircularProgressIndicator()),
          );
  }
}

class WidgetAudio extends StatefulWidget {
  final ModelItem item;
  final bool showBorder;
  const WidgetAudio({
    super.key,
    required this.item,
    this.showBorder = true,
  });

  @override
  State<WidgetAudio> createState() => _WidgetAudioState();
}

class _WidgetAudioState extends State<WidgetAudio> {
  late AudioPlayer _audioPlayer;
  Duration _totalDuration = Duration.zero;
  Duration _currentPosition = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    int savedDurationSeconds =
        mediaFileDurationFromString(widget.item.data!["duration"]);
    _totalDuration = Duration(seconds: savedDurationSeconds);
    _audioPlayer = AudioPlayer();

    // Load audio file duration
    _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          if (duration.inMilliseconds > 0) {
            _totalDuration = duration;
          }
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false; // Fixed: Set to false instead of toggling
          _currentPosition = Duration.zero; // Reset position
        });
      }
    });

    // Track current position of the audio
    _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          // Ensure position is within valid bounds
          if (position < Duration.zero) {
            _currentPosition = Duration.zero;
          } else if (_totalDuration.inMilliseconds > 0 &&
              position.inMilliseconds > _totalDuration.inMilliseconds) {
            _currentPosition = _totalDuration;
          } else {
            _currentPosition = position;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> downloadMedia() async {
    SodiumSumo sodium = await SodiumSumoInit.init();
    CryptoUtils cryptoUtils = CryptoUtils(sodium);
    widget.item.state = SyncState.downloading.value;
    widget.item.update(["state"], pushToSync: false);
    if (mounted) {
      setState(() {});
    }
    bool downloadedDecrypted =
        await cryptoUtils.downloadDecryptFile(widget.item.data!);
    if (downloadedDecrypted) {
      widget.item.state = SyncState.downloaded.value;
      widget.item.update(["state"], pushToSync: false);
      if (mounted) {
        setState(() {});
      }
    } else {
      widget.item.state = SyncState.downloadable.value;
      widget.item.update(["state"], pushToSync: false);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _togglePlayPause() async {
    String filePath = widget.item.data!["path"];
    File audioFile = File(filePath);
    if (!audioFile.existsSync()) {
      if (mounted) {
        showAlertMessage(context, "Please wait", "File not available yet.");
      }
      return;
    }
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.setSourceDeviceFile(filePath);
      await _audioPlayer.resume();
    }
    if (mounted) {
      setState(() {
        _isPlaying = !_isPlaying;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    bool displayDownloadButton =
        widget.item.state == SyncState.downloadable.value;

    // Calculate safe slider value to avoid range errors
    double sliderMax = max(_totalDuration.inMilliseconds.toDouble(), 1.0);
    double sliderValue =
        min(max(_currentPosition.inMilliseconds.toDouble(), 0.0), sliderMax);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: widget.showBorder
            ? Border.all(
                color: cs.secondary.withValues(alpha: 0.15),
                width: 0.75,
              )
            : null,
      ),
      child: Row(
        children: [
          // Boxed Play/Pause button
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: cs.secondary.withValues(alpha: 0.2),
                width: 0.75,
              ),
            ),
            child: displayDownloadButton
                ? DownloadButton(
                    onPressed: downloadMedia,
                    item: widget.item,
                    iconSize: 22,
                  )
                : IconButton(
                    tooltip: "Play/pause",
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 24,
                      color: cs.secondary,
                    ),
                    onPressed: _togglePlayPause,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: cs.secondary,
                    inactiveTrackColor: cs.secondary.withValues(alpha: 0.15),
                    thumbColor: cs.secondary,
                    overlayColor: cs.secondary.withValues(alpha: 0.12),
                  ),
                  child: Slider(
                    min: 0,
                    max: sliderMax,
                    value: sliderValue,
                    onChanged: (value) async {
                      Duration newPosition =
                          Duration(milliseconds: value.toInt());
                      await _audioPlayer.seek(newPosition);
                      if (mounted) {
                        setState(() {
                          _currentPosition = newPosition;
                        });
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        mediaFileDurationFromSeconds(_currentPosition.inSeconds),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: cs.secondary.withValues(alpha: 0.7)),
                      ),
                      Text(
                        mediaFileDurationFromSeconds(_totalDuration.inSeconds),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget widgetAudioDetails(ModelItem item) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      WidgetTimeStampPinnedStarred(
        item: item,
      ),
    ],
  );
}

class WidgetTextWithLinks extends StatefulWidget {
  final String text;
  final TextAlign? align;
  final bool isCompleted;

  const WidgetTextWithLinks(
      {super.key, required this.text, this.align, this.isCompleted = false});

  @override
  State<WidgetTextWithLinks> createState() => _WidgetTextWithLinksState();
}

class _WidgetTextWithLinksState extends State<WidgetTextWithLinks> {
  @override
  Widget build(BuildContext context) {
    return Consumer<FontSizeController>(builder: (context, controller, child) {
      return RichText(
        text: TextSpan(
          children: _buildTextWithLinks(context, controller, widget.text),
        ),
        textAlign: widget.align == null ? TextAlign.left : widget.align!,
      );
    });
  }

  List<TextSpan> _buildTextWithLinks(
      BuildContext context, FontSizeController controller, String text) {
    final List<TextSpan> spans = [];
    final RegExp linkRegExp = RegExp(r'(https?://[^\s]+)');
    final matches = linkRegExp.allMatches(text);

    int lastMatchEnd = 0;

    double fontSize = 15;

    for (final match in matches) {
      final start = match.start;
      final end = match.end;

      // Add plain text before the link
      if (start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, start),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: controller.getScaledSize(fontSize),
              decoration:
                  widget.isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
        );
      }

      // Add the link text
      final linkText = text.substring(start, end);
      try {
        final TextStyle linkStyle = TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: controller.getScaledSize(fontSize),
          fontWeight: FontWeight.w600,
          decoration: widget.isCompleted ? TextDecoration.lineThrough : null,
        );

        final linkUri = Uri.parse(linkText);
        spans.add(TextSpan(
          text: linkText,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              if (await canLaunchUrl(linkUri)) {
                await launchUrl(linkUri);
              } else {
                final logger = AppLogger(
                    prefixes: ["common_widgets", "WidgetTextWithLink"]);
                logger.error("Could not launch $linkText");
              }
            },
        ));
      } catch (e) {
        spans.add(
          TextSpan(
            text: linkText,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: controller.getScaledSize(fontSize),
              decoration:
                  widget.isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
        );
      }

      lastMatchEnd = end;
    }

    // Add the remaining plain text after the last link
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: controller.getScaledSize(fontSize),
          decoration: widget.isCompleted ? TextDecoration.lineThrough : null,
        ),
      ));
    }

    return spans;
  }
}

class TimerWidget extends StatefulWidget {
  final int runningState;

  const TimerWidget({
    super.key,
    required this.runningState,
  });

  @override
  State<TimerWidget> createState() => TimerWidgetState();
}

class TimerWidgetState extends State<TimerWidget> {
  late int _secondsElapsed;
  Timer? _timer;
  int runningState = 0;

  @override
  void initState() {
    super.initState();
    _secondsElapsed = 0; // Initialize timer duration
  }

  @override
  void dispose() {
    _timer?.cancel(); // Clean up the timer when the widget is disposed
    super.dispose();
  }

  /// Start the timer
  void start() {
    if (_timer != null && _timer!.isActive) return; // Prevent multiple timers
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });
    });
  }

  /// Stop the timer
  void stop() {
    _timer?.cancel();
  }

  /// Reset the timer
  void reset() {
    stop();
    setState(() {
      _secondsElapsed = 0;
    });
  }

  String get _formattedTime {
    final minutes = (_secondsElapsed ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsElapsed % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  void setRunningState() {
    if (widget.runningState == 2) {
      stop();
    } else if (widget.runningState == 1) {
      start();
    } else if (widget.runningState == 0) {
      reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    setRunningState();
    return Text(
      _formattedTime,
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: 16.0,
      ),
    );
  }
}

Future<void> displaySnackBar(BuildContext context,
    {required String message, required int seconds}) async {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(
      message,
    ),
    duration: Duration(seconds: seconds),
  ));
}

class ColorPickerDialog extends StatefulWidget {
  final String? color;

  const ColorPickerDialog({super.key, this.color});

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  Color selectedColor = colorFromHex("#06b6d4"); // Default selected color
  double hue = 0.0; // Default hue for the color bar

  @override
  void initState() {
    super.initState();
    if (widget.color != null) {
      selectedColor = colorFromHex(widget.color!);
      hue = HSVColor.fromColor(selectedColor).hue / 360.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final String hexCode = colorToHex(selectedColor);

    return AlertDialog(
      backgroundColor: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Preview Card
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: selectedColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: selectedColor.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: Stack(
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            hexCode.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Color Grid
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12.0,
              runSpacing: 12.0,
              children: predefinedColors.map((color) {
                final bool isSelected = selectedColor == color;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedColor = color;
                      hue = HSVColor.fromColor(selectedColor).hue / 360.0;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(isSelected ? 10 : 14),
                      border: Border.all(
                        color: isSelected
                            ? Colors.white
                            : color.computeLuminance() > 0.8
                                ? cs.outlineVariant
                                : Colors.transparent,
                        width: isSelected ? 3 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            color: color.computeLuminance() > 0.6
                                ? Colors.black87
                                : Colors.white,
                            size: 18,
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // Custom Color Section Label
            Text(
              "CUSTOM COLOR",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),

            // Modern Hue Slider
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                alignment: AlignmentDirectional.center,
                children: [
                  Container(
                    height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: LinearGradient(
                        colors: [
                          for (double i = 0; i <= 1; i += 0.1)
                            HSVColor.fromAHSV(1.0, i * 360, 1.0, 1.0).toColor()
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 18,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 12,
                        elevation: 4,
                        pressedElevation: 8,
                      ),
                      overlayColor: Colors.white.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: hue,
                      onChanged: (newHue) {
                        setState(() {
                          hue = newHue;
                          selectedColor =
                              HSVColor.fromAHSV(1.0, hue * 360, 1.0, 1.0)
                                  .toColor();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          style: TextButton.styleFrom(
            foregroundColor: cs.onSurfaceVariant,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(selectedColor),
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary.withValues(alpha: 0.1),
            foregroundColor: cs.primary,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: const Text(
            "Select",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class AnimatedWidgetSwap extends StatefulWidget {
  final Widget firstWidget;
  final Widget secondWidget;
  final bool showFirst;
  final Duration duration;

  const AnimatedWidgetSwap({
    super.key,
    required this.firstWidget,
    required this.secondWidget,
    required this.showFirst,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  State<AnimatedWidgetSwap> createState() => _AnimatedWidgetSwapState();
}

class _AnimatedWidgetSwapState extends State<AnimatedWidgetSwap>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideOutAnimation;
  late Animation<Offset> _slideInAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _slideOutAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(1.0, 0.0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _slideInAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(AnimatedWidgetSwap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showFirst != widget.showFirst) {
      if (widget.showFirst) {
        _controller.reverse();
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SlideTransition(
          position: _slideOutAnimation,
          child: widget.showFirst ? widget.firstWidget : Container(),
        ),
        SlideTransition(
          position: _slideInAnimation,
          child: widget.showFirst ? Container() : widget.secondWidget,
        ),
      ],
    );
  }
}

class AnimatedPageRoute extends PageRouteBuilder {
  final Widget child;

  AnimatedPageRoute({required this.child})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: const Duration(milliseconds: 150),
          reverseTransitionDuration: const Duration(milliseconds: 150),
        );

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    // Animation for the new screen (Child)
    const curve = Curves.linear;
    final childSlideAnimation = Tween(
      begin: const Offset(0.0, 0.02),
      end: Offset.zero,
    ).chain(CurveTween(curve: curve)).animate(animation);

    final childFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).chain(CurveTween(curve: curve)).animate(animation);

    // Animation for the previous screen (Parent)
    final parentScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).chain(CurveTween(curve: curve)).animate(secondaryAnimation);

    final parentFadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.8,
    ).chain(CurveTween(curve: curve)).animate(secondaryAnimation);

    return Stack(
      children: [
        // Animate the Parent screen
        FadeTransition(
          opacity: parentFadeAnimation,
          child: ScaleTransition(
            scale: parentScaleAnimation,
            child: Container(), // This will be the parent screen
          ),
        ),
        // Animate the Child screen
        FadeTransition(
          opacity: childFadeAnimation,
          child: SlideTransition(
            position: childSlideAnimation,
            child: child,
          ),
        ),
      ],
    );
  }
}

class UploadDownloadIndicator extends StatefulWidget {
  final double size;
  final bool uploading;
  const UploadDownloadIndicator(
      {super.key, required this.size, required this.uploading});
  @override
  State<UploadDownloadIndicator> createState() =>
      UploadDownloadIndicatorState();
}

class UploadDownloadIndicatorState extends State<UploadDownloadIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 1),
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Opacity(
        opacity: 0.6,
        child: Icon(
          widget.uploading ? Icons.arrow_upward : Icons.arrow_downward,
          size: widget.size,
        ),
      ),
    );
  }
}

class DownloadButton extends StatefulWidget {
  final VoidCallback onPressed;
  final ModelItem item;
  final double iconSize;

  const DownloadButton({
    super.key,
    required this.item,
    this.iconSize = 30.0,
    required this.onPressed, // Default icon size
  });

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
          width: 0.75,
        ),
      ),
      child: IconButton(
        tooltip: "Download",
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: Opacity(
          opacity: 0.5,
          child: Icon(
            Icons.arrow_downward,
            size: widget.iconSize,
          ),
        ),
        onPressed: widget.onPressed,
      ),
    );
  }
}

class VideoPlayDownloadButton extends StatelessWidget {
  final double iconSize;
  final bool showPlay;
  final VoidCallback onPressed;
  const VideoPlayDownloadButton(
      {super.key,
      required this.iconSize,
      required this.showPlay,
      required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      width: iconSize,
      height: iconSize,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        // Semi-transparent grey background
        shape: BoxShape.circle,
      ),
      child: showPlay
          ? Icon(
              LucideIcons.play,
              color: Colors.white,
              size: iconSize / 2,
            )
          : IconButton(
              tooltip: "Download",
              icon: Icon(
                Icons.arrow_downward,
                color: Colors.white,
                size: iconSize / 2,
              ),
              onPressed: onPressed,
            ),
    );
  }
}

class ImageDownloadButton extends StatefulWidget {
  final VoidCallback onPressed;
  final ModelItem item;
  final double iconSize;
  const ImageDownloadButton({
    super.key,
    required this.iconSize,
    required this.item,
    required this.onPressed,
  });

  @override
  State<ImageDownloadButton> createState() => _ImageDownloadButtonState();
}

class _ImageDownloadButtonState extends State<ImageDownloadButton> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.iconSize,
      height: widget.iconSize,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        // Semi-transparent grey background
        shape: BoxShape.circle,
      ),
      child: IconButton(
        tooltip: "Download",
        icon: Icon(
          Icons.arrow_downward,
          color: Colors.white,
          size: widget.iconSize / 2,
        ),
        onPressed: widget.onPressed,
      ),
    );
  }
}
