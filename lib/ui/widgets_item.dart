import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ntsapp/utils/enums.dart';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../utils/common.dart';
import 'common_widgets.dart';
import '../models/model_item.dart';
import '../utils/utils_crypto.dart';

class ItemWidgetDate extends StatelessWidget {
  final ModelItem item;

  const ItemWidgetDate({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    String dateText = getReadableDate(
        DateTime.fromMillisecondsSinceEpoch(item.at!, isUtc: true));
    return ItemWidgetTimePill(timeText: dateText);
  }
}

class ItemWidgetTimePill extends StatelessWidget {
  final String timeText;

  const ItemWidgetTimePill({super.key, required this.timeText});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min, // Shrinks to fit the text width
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              timeText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WidgetPinnedStarredPills extends StatelessWidget {
  final ModelItem item;
  const WidgetPinnedStarredPills({super.key, required this.item});

  Widget _pill(BuildContext context, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      decoration: BoxDecoration(
        color: cs.onSurfaceVariant.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: cs.onSurfaceVariant.withValues(alpha: 0.15), width: 0.75),
      ),
      child: Icon(icon,
          size: 9, color: cs.onSurfaceVariant.withValues(alpha: 0.75)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (item.pinned != 1 && item.starred != 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.pinned == 1) _pill(context, LucideIcons.pin),
          if (item.pinned == 1 && item.starred == 1) const SizedBox(width: 3),
          if (item.starred == 1) _pill(context, LucideIcons.star),
        ],
      ),
    );
  }
}

class WidgetTimeStampPinnedStarred extends StatelessWidget {
  final ModelItem item;
  const WidgetTimeStampPinnedStarred({
    super.key,
    required this.item,
  });

  Widget itemStateIcon(ModelItem item) {
    if (item.state == SyncState.uploading.value) {
      return UploadDownloadIndicator(uploading: true, size: 12);
    } else if (item.state == SyncState.downloading.value) {
      return UploadDownloadIndicator(uploading: false, size: 12);
    } else if (item.state == SyncState.uploaded.value ||
        item.state == SyncState.downloaded.value ||
        item.state == SyncState.downloadable.value) {
      return Opacity(
        opacity: 0.6,
        child: Icon(
          LucideIcons.check,
          size: 12,
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        itemStateIcon(item),
        const SizedBox(width: 4),
      ],
    );
  }
}

class ItemWidgetText extends StatefulWidget {
  final ModelItem item;
  const ItemWidgetText({
    super.key,
    required this.item,
  });

  @override
  State<ItemWidgetText> createState() => _ItemWidgetTextState();
}

class _ItemWidgetTextState extends State<ItemWidgetText> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(width: 4),
            Flexible(child: WidgetTextWithLinks(text: widget.item.text)),
          ],
        ),
        WidgetTimeStampPinnedStarred(item: widget.item),
        WidgetPinnedStarredPills(item: widget.item),
      ],
    );
  }
}

class ItemWidgetTask extends StatefulWidget {
  final ModelItem item;
  const ItemWidgetTask({
    super.key,
    required this.item,
  });

  @override
  State<ItemWidgetTask> createState() => _ItemWidgetTaskState();
}

class _ItemWidgetTaskState extends State<ItemWidgetTask> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(child: WidgetTextWithLinks(text: widget.item.text)),
            const SizedBox(width: 8),
            Icon(
              widget.item.type == ItemType.completedTask
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: widget.item.type == ItemType.task
                  ? Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.5)
                  : Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
        WidgetTimeStampPinnedStarred(item: widget.item),
        WidgetPinnedStarredPills(item: widget.item),
      ],
    );
  }
}

class ItemWidgetImage extends StatefulWidget {
  final ModelItem item;
  final Function(ModelItem) onTap;
  const ItemWidgetImage({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  State<ItemWidgetImage> createState() => _ItemWidgetImageState();
}

class _ItemWidgetImageState extends State<ItemWidgetImage> {
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

  @override
  void initState() {
    super.initState();
    _measureAndStoreDimensionsIfNeeded();
  }

  Future<void> _measureAndStoreDimensionsIfNeeded() async {
    final data = widget.item.data;
    if (data == null) return;
    if (data.containsKey("width") && data.containsKey("height")) return;
    if (widget.item.thumbnail == null) return;

    final decoded = await decodeImageFromList(widget.item.thumbnail!);
    widget.item.data!["width"] = decoded.width.toDouble();
    widget.item.data!["height"] = decoded.height.toDouble();
    await widget.item.update(["data"]);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    bool displayDownloadButton =
        widget.item.state == SyncState.downloadable.value;
    bool hasPinStar = widget.item.pinned == 1 || widget.item.starred == 1;

    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth * 0.6;

    double imgW, imgH;

    final data = widget.item.data;
    if (data != null &&
        data.containsKey("width") &&
        data.containsKey("height")) {
      imgW = (data["width"] as num).toDouble() * 0.85;
      imgH = (data["height"] as num).toDouble() * 0.85;
      if (imgW > maxWidth) {
        imgH = imgH * (maxWidth / imgW);
        imgW = maxWidth;
      }
      if (imgH > maxWidth) {
        imgW = imgW * (maxWidth / imgH);
        imgH = maxWidth;
      }
    } else {
      imgW = maxWidth * 0.7;
      imgH = imgW;
    }

    return GestureDetector(
      onTap: () {
        widget.onTap(widget.item);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: imgW,
                  height: imgH,
                  child: widget.item.thumbnail == null
                      ? Image.asset(
                          "assets/image.webp",
                          width: double.infinity,
                          fit: BoxFit.contain,
                        )
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.memory(
                              widget.item.thumbnail!,
                              width: double.infinity,
                              fit: BoxFit.contain,
                            ),
                            if (displayDownloadButton)
                              ImageDownloadButton(
                                  item: widget.item,
                                  onPressed: downloadMedia,
                                  iconSize: 50)
                          ],
                        ),
                ),
              ),
              // Pin / star overlay pills — top-right corner
              if (hasPinStar)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.item.pinned == 1)
                          Icon(LucideIcons.pin, size: 11, color: Colors.white),
                        if (widget.item.pinned == 1 && widget.item.starred == 1)
                          const SizedBox(width: 4),
                        if (widget.item.starred == 1)
                          Icon(LucideIcons.star, size: 11, color: Colors.white),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          WidgetTimeStampPinnedStarred(
            item: widget.item,
          ),
        ],
      ),
    );
  }
}

class ItemWidgetVideo extends StatefulWidget {
  final ModelItem item;
  final Function(ModelItem) onTap;

  const ItemWidgetVideo({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  State<ItemWidgetVideo> createState() => _ItemWidgetVideoState();
}

class _ItemWidgetVideoState extends State<ItemWidgetVideo> {
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

  @override
  Widget build(BuildContext context) {
    double size = 200;
    return GestureDetector(
      onTap: () {
        widget.onTap(widget.item);
      },
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: size,
              height: size / widget.item.data!["aspect"],
              child: widget.item.thumbnail == null
                  ? canUseVideoPlayer
                      ? WidgetVideoPlayerThumbnail(
                          onPressed: downloadMedia,
                          item: widget.item,
                          iconSize: 50,
                        )
                      : WidgetMediaKitThumbnail(
                          onPressed: downloadMedia,
                          item: widget.item,
                          iconSize: 50,
                        )
                  : WidgetVideoImageThumbnail(
                      onPressed: downloadMedia,
                      item: widget.item,
                      iconSize: 50,
                    ),
            ),
          ),
          SizedBox(
            width: size,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Opacity(
                        opacity: 0.6,
                        child: const Icon(LucideIcons.video, size: 14)),
                    const SizedBox(width: 3),
                    Opacity(
                      opacity: 0.6,
                      child: Text(
                        widget.item.data!["duration"],
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                    const SizedBox(width: 4),
                    WidgetTimeStampPinnedStarred(item: widget.item),
                  ],
                ),
                WidgetPinnedStarredPills(item: widget.item),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ItemWidgetAudio extends StatefulWidget {
  final ModelItem item;
  const ItemWidgetAudio({
    super.key,
    required this.item,
  });

  @override
  State<ItemWidgetAudio> createState() => _ItemWidgetAudioState();
}

class _ItemWidgetAudioState extends State<ItemWidgetAudio> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WidgetAudio(item: widget.item),
        widgetAudioDetails(widget.item),
      ],
    );
  }
}

Widget widgetAudioDetails(ModelItem item) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      WidgetTimeStampPinnedStarred(item: item),
      WidgetPinnedStarredPills(item: item),
    ],
  );
}

class ItemWidgetDocument extends StatefulWidget {
  final ModelItem item;
  final Function(ModelItem) onTap;
  final bool showBorder;

  const ItemWidgetDocument({
    super.key,
    required this.item,
    required this.onTap,
    this.showBorder = true,
  });

  @override
  State<ItemWidgetDocument> createState() => _ItemWidgetDocumentState();
}

class _ItemWidgetDocumentState extends State<ItemWidgetDocument> {
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String title = widget.item.data!.containsKey("title")
        ? widget.item.data!["title"]
        : widget.item.data!["name"];
    bool hasThumbnail = widget.item.thumbnail != null;
    String fileName = widget.item.data!["name"] ?? "";
    String ext = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : "FILE";
    String size = readableFileSizeFromBytes(widget.item.data!["size"]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: widget.showBorder
                ? Border.all(
                    color: cs.primary.withValues(alpha: 0.15),
                    width: 0.75,
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: cs.primary.withValues(alpha: 0.2), width: 0.75),
                ),
                child: hasThumbnail
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(widget.item.thumbnail!,
                            fit: BoxFit.cover))
                    : Icon(LucideIcons.file, size: 18, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: cs.primary.withValues(alpha: 0.2),
                              width: 0.75),
                        ),
                        child: Text(ext,
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: cs.primary,
                                letterSpacing: 0.3)),
                      ),
                      const SizedBox(width: 6),
                      Text(size,
                          style: TextStyle(
                              fontSize: 10,
                              color:
                                  cs.onSurfaceVariant.withValues(alpha: 0.6))),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        WidgetTimeStampPinnedStarred(item: widget.item),
        WidgetPinnedStarredPills(item: widget.item),
      ],
    );
  }
}

class ItemWidgetLocation extends StatelessWidget {
  final ModelItem item;
  final Function(ModelItem) onTap;
  final bool showBorder;

  const ItemWidgetLocation({
    super.key,
    required this.item,
    required this.onTap,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onTap(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: showBorder
                  ? Border.all(
                      color: cs.error.withValues(alpha: 0.15), width: 0.75)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: cs.error.withValues(alpha: 0.2), width: 0.75),
                  ),
                  child: Icon(LucideIcons.mapPin, size: 18, color: cs.error),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Location",
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface)),
                    const SizedBox(height: 2),
                    Text("Tap to open in maps",
                        style: TextStyle(
                            fontSize: 10, color: cs.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: cs.error.withValues(alpha: 0.2), width: 0.75),
                  ),
                  child: Text("View",
                      style: TextStyle(
                          fontSize: 10,
                          color: cs.error,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          WidgetTimeStampPinnedStarred(item: item),
          WidgetPinnedStarredPills(item: item),
        ],
      ),
    );
  }
}

class ItemWidgetContact extends StatelessWidget {
  final ModelItem item;
  final Function(ModelItem) onTap;
  final bool showBorder;

  const ItemWidgetContact({
    super.key,
    required this.item,
    required this.onTap,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color avatarColor = cs.tertiary;
    String initials = (item.data!["name"] as String? ?? "?").isNotEmpty
        ? (item.data!["name"] as String).trim()[0].toUpperCase()
        : "?";

    return GestureDetector(
      onTap: () => onTap(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: cs.tertiary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: showBorder
                  ? Border.all(
                      color: cs.tertiary.withValues(alpha: 0.15), width: 0.75)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                item.thumbnail != null
                    ? CircleAvatar(
                        radius: 18,
                        backgroundImage: MemoryImage(item.thumbnail!))
                    : CircleAvatar(
                        radius: 18,
                        backgroundColor: avatarColor.withValues(alpha: 0.15),
                        child: Text(initials,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: avatarColor)),
                      ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item.data!["name"]}'.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    if ((item.data!["phones"] as List).isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(item.data!["phones"][0],
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  cs.onSurfaceVariant.withValues(alpha: 0.6))),
                    ],
                  ],
                ),
              ],
            ),
          ),
          WidgetTimeStampPinnedStarred(item: item),
          WidgetPinnedStarredPills(item: item),
        ],
      ),
    );
  }
}

// ── Reply quote bubble — shown above the reply as a separate left-aligned bubble
class ReplyQuoteBubble extends StatelessWidget {
  final ModelItem replyOn;
  final VoidCallback onTap;
  final bool showBorder;

  const ReplyQuoteBubble({
    super.key,
    required this.replyOn,
    required this.onTap,
    this.showBorder = true,
  });

  // Types where a thumbnail tells the whole story — no text label needed.
  bool get _thumbnailOnly =>
      replyOn.thumbnail != null &&
      (replyOn.type == ItemType.image ||
          replyOn.type == ItemType.video ||
          replyOn.type == ItemType.contact);

  // Label for types without a self-explanatory thumbnail.
  String get _label {
    switch (replyOn.type) {
      case ItemType.text:
      case ItemType.task:
      case ItemType.completedTask:
        return replyOn.text;
      case ItemType.audio:
        return '🎵 ${replyOn.data?["name"] ?? "Audio"}';
      case ItemType.document:
        return '📄 ${replyOn.data?["title"] ?? replyOn.data?["name"] ?? "Document"}';
      case ItemType.location:
        return '📍 Location';
      default:
        return '';
    }
  }

  // Radius scales with text length for text types; fixed pill for everything else.
  double get _radius {
    final isText = replyOn.type == ItemType.text ||
        replyOn.type == ItemType.task ||
        replyOn.type == ItemType.completedTask;
    if (!isText) return 12.0;
    final len = replyOn.text.length;
    if (len <= 20) return 14.0;
    if (len >= 120) return 6.0;
    return 14.0 - (len - 20) / (120 - 20) * 8.0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final double r = _radius;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onTap,
          child: _thumbnailOnly
              // ── Thumbnail-only (image / video / contact) ────────────
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(r),
                  child: Image.memory(
                    replyOn.thumbnail!,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                )
              // ── Text / label bubble ──────────────────────────────────
              : Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(r),
                    border: showBorder
                        ? Border.all(
                            color: cs.onSurface.withValues(alpha: 0.1),
                            width: 0.75,
                          )
                        : null,
                  ),
                  child: Text(
                    _label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
        ),
        // ── Connector: drops down then bends right toward the bubble ──
        CustomPaint(
          size: const Size(60, 14),
          painter: _ReplyConnectorPainter(
            color: cs.onSurface.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }
}

class NotePreviewSummary extends StatelessWidget {
  final ModelItem? item;
  final bool? showImagePreview;
  final bool? expanded;

  const NotePreviewSummary({
    super.key,
    this.item,
    this.showImagePreview,
    this.expanded,
  });

  String _getMessageText() {
    if (item == null) {
      return "Empty";
    } else {
      switch (item!.type) {
        case ItemType.text:
          return item!.text; // Text content
        case ItemType.image:
          return "Image";
        case ItemType.video:
          return "Video";
        case ItemType.audio:
          return "Audio";
        case ItemType.document:
          return "Document";
        case ItemType.contact:
          return "Contact";
        case ItemType.location:
          return "Location";
        case ItemType.task:
        case ItemType.completedTask:
          return item!.text;
        default:
          return "Unknown";
      }
    }
  }

  Widget _previewImage(BuildContext context, ModelItem item) {
    switch (item.type) {
      case ItemType.image:
      case ItemType.video:
      case ItemType.contact:
        if (item.thumbnail == null) return const SizedBox.shrink();

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            showDialog(
              context: context,
              barrierColor: Colors.black87,
              builder: (context) => Dialog(
                backgroundColor: Colors.transparent,
                child: Stack(
                  children: [
                    Center(
                      child: InteractiveViewer(
                        maxScale: 3.5,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            item.thumbnail!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Image.memory(
                    item.thumbnail!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              // Expand icon — top-right, always visible
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.zoom_out_map,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        /* Icon(
          _getIcon(),
          size: 13,
          color: Colors.grey,
        ),
        const SizedBox(width: 5), */
        expanded == true
            ? Expanded(
                child: Text(
                  _getMessageText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis, // Ellipsis for long text
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              )
            : Flexible(
                child: Text(
                  _getMessageText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis, // Ellipsis for long text
                  style: const TextStyle(
                    fontSize: 12,
                  ),
                ),
              ),
        const SizedBox(width: 8),
        if (showImagePreview!) _previewImage(context, item!),
        const SizedBox(width: 8),
      ],
    );
  }
}

class NoteUrlPreview extends StatefulWidget {
  final String itemId;
  final String imageDirectory;
  final Map<String, dynamic> urlInfo;

  const NoteUrlPreview(
      {super.key,
      required this.urlInfo,
      required this.itemId,
      required this.imageDirectory});

  @override
  State<NoteUrlPreview> createState() => _NoteUrlPreviewState();
}

class _NoteUrlPreviewState extends State<NoteUrlPreview> {
  bool removed = false;
  // null = not yet checked, false = not found, true = found
  bool? _imageExists;

  @override
  void initState() {
    super.initState();
    _checkImageFile();
  }

  @override
  void didUpdateWidget(NoteUrlPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check if the imageDirectory or itemId changed (e.g. directory loaded late)
    if (oldWidget.imageDirectory != widget.imageDirectory ||
        oldWidget.itemId != widget.itemId) {
      _checkImageFile();
    }
  }

  Future<void> _checkImageFile() async {
    if (widget.imageDirectory.isEmpty) {
      // Directory not ready yet — wait a bit and retry
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      _checkImageFile();
      return;
    }
    final file = File("${widget.imageDirectory}/${widget.itemId}-urlimage.png");
    final exists = file.existsSync();
    if (mounted && exists != _imageExists) {
      setState(() => _imageExists = exists);
    }
  }

  Future<void> remove() async {
    removed = await ModelItem.removeUrlInfo(widget.itemId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (removed) return const SizedBox.shrink();

    final imgFile = _imageExists == true
        ? File("${widget.imageDirectory}/${widget.itemId}-urlimage.png")
        : null;

    // portrait == 1 means tall/square image → side thumbnail
    // portrait == 0 means landscape/banner image → full-width bottom strip
    final bool isLandscape =
        imgFile != null && (widget.urlInfo["portrait"] == 0);
    final bool isPortrait =
        imgFile != null && (widget.urlInfo["portrait"] != 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: cs.onSurface.withValues(alpha: 0.08), width: 0.75),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: accent bar + text + optional portrait thumbnail ──
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // left accent bar
                Container(width: 3, color: cs.primary),
                // text block
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.urlInfo["title"] != null)
                          Text(
                            widget.urlInfo["title"],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface),
                          ),
                        if (widget.urlInfo["desc"] != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            widget.urlInfo["desc"],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant
                                    .withValues(alpha: 0.65)),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          Uri.tryParse(widget.urlInfo["url"] ?? "")?.host ??
                              widget.urlInfo["url"] ??
                              "",
                          style: TextStyle(fontSize: 10, color: cs.primary),
                        ),
                      ],
                    ),
                  ),
                ),
                // portrait thumbnail — tall/square image on the right
                if (isPortrait)
                  Container(
                    width: 72,
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      image: DecorationImage(
                        image: FileImage(imgFile),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                // action buttons: expand (if image exists) + dismiss
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (imgFile != null)
                      IconButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            barrierColor: Colors.black87,
                            builder: (context) => Dialog(
                              backgroundColor: Colors.transparent,
                              child: Stack(
                                children: [
                                  Center(
                                    child: InteractiveViewer(
                                      maxScale: 3.5,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.file(
                                          imgFile,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 16,
                                    right: 16,
                                    child: IconButton(
                                      icon: const Icon(Icons.close,
                                          color: Colors.white, size: 28),
                                      onPressed: () => Navigator.pop(context),
                                      style: IconButton.styleFrom(
                                        backgroundColor:
                                            Colors.black.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        icon: Icon(Icons.zoom_out_map,
                            size: 16,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                        padding: const EdgeInsets.all(8),
                      ),
                    IconButton(
                      onPressed: remove,
                      icon: Icon(LucideIcons.x,
                          size: 16,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                      padding: const EdgeInsets.all(8),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ── Bottom banner — landscape image full-width strip ──────────
          if (isLandscape)
            SizedBox(
              height: 120,
              width: double.infinity,
              child: Image.file(
                imgFile,
                fit: BoxFit.cover,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Reply connector painter ───────────────────────────────────────────────────
class _ReplyConnectorPainter extends CustomPainter {
  final Color color;
  const _ReplyConnectorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = ui.Path()
      ..moveTo(12, 0)
      ..lineTo(12, size.height * 0.55)
      ..quadraticBezierTo(12, size.height, 28, size.height);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ReplyConnectorPainter old) => old.color != color;
}
