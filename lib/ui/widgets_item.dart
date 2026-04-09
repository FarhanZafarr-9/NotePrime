

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
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min, // Shrinks to fit the text width
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              timeText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WidgetTimeStampPinnedStarred extends StatelessWidget {
  final ModelItem item;
  final bool showTimestamp;
  final double? revealOffset;

  const WidgetTimeStampPinnedStarred(
      {super.key,
      required this.item,
      required this.showTimestamp,
      this.revealOffset});

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
      children: [
        item.pinned == 1
            ? Icon(LucideIcons.pin,
                size: 12, color: Theme.of(context).colorScheme.inversePrimary)
            : const SizedBox.shrink(),
        const SizedBox(width: 2),
        item.starred == 1
            ? Icon(LucideIcons.star,
                size: 12, color: Theme.of(context).colorScheme.inversePrimary)
            : const SizedBox.shrink(),
        const SizedBox(
          width: 2,
        ),
        itemStateIcon(item),
        const SizedBox(width: 4),
        if (showTimestamp)
          Transform.translate(
            offset: Offset(60 - (revealOffset ?? 0), 0),
            child: Opacity(
              opacity: (revealOffset ?? 0) > 0 ? 1.0 : 0.6,
              child: Text(
                getFormattedTime(item.at!),
                style: const TextStyle(
                  fontSize: 10,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ItemWidgetText extends StatefulWidget {
  final ModelItem item;
  final bool showTimestamp;

  final double? revealOffset;

  const ItemWidgetText(
      {super.key,
      required this.item,
      required this.showTimestamp,
      this.revealOffset});

  @override
  State<ItemWidgetText> createState() => _ItemWidgetTextState();
}

class _ItemWidgetTextState extends State<ItemWidgetText> {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(width: 4),
        Flexible(child: WidgetTextWithLinks(text: widget.item.text)),
        WidgetTimeStampPinnedStarred(
          item: widget.item,
          showTimestamp: widget.showTimestamp,
          revealOffset: widget.revealOffset,
        ),
      ],
    );
  }
}

class ItemWidgetTask extends StatefulWidget {
  final ModelItem item;
  final bool showTimestamp;

  final double? revealOffset;

  const ItemWidgetTask(
      {super.key,
      required this.item,
      required this.showTimestamp,
      this.revealOffset});

  @override
  State<ItemWidgetTask> createState() => _ItemWidgetTaskState();
}

class _ItemWidgetTaskState extends State<ItemWidgetTask> {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: WidgetTextWithLinks(text: widget.item.text)),
              const SizedBox(width: 8),
              Icon(
                widget.item.type == ItemType.completedTask
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: widget.item.type == ItemType.task
                    ? Theme.of(context).colorScheme.inversePrimary
                    : Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
        WidgetTimeStampPinnedStarred(
          item: widget.item,
          showTimestamp: widget.showTimestamp,
          revealOffset: widget.revealOffset,
        )
      ],
    );
  }
}

class ItemWidgetImage extends StatefulWidget {
  final ModelItem item;
  final Function(ModelItem) onTap;
  final bool showTimestamp;

  final double? revealOffset;

  const ItemWidgetImage(
      {super.key,
      required this.item,
      required this.onTap,
      required this.showTimestamp,
      this.revealOffset});

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
  Widget build(BuildContext context) {
    bool displayDownloadButton =
        widget.item.state == SyncState.downloadable.value;
    double size = 200;
    return GestureDetector(
      onTap: () {
        widget.onTap(widget.item);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: size,
              child: widget.item.thumbnail == null
                  ? Image.asset(
                      "assets/image.webp",
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.memory(
                          widget.item.thumbnail!,
                          width: double.infinity, // Full width of container
                          fit: BoxFit.cover,
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
          const SizedBox(
            height: 5,
          ),
          WidgetTimeStampPinnedStarred(
            item: widget.item,
            showTimestamp: widget.showTimestamp,
            revealOffset: widget.revealOffset,
          ),
        ],
      ),
    );
  }
}

class ItemWidgetVideo extends StatefulWidget {
  final ModelItem item;
  final Function(ModelItem) onTap;
  final bool showTimestamp;

  final double? revealOffset;

  const ItemWidgetVideo(
      {super.key,
      required this.item,
      required this.onTap,
      required this.showTimestamp,
      this.revealOffset});

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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // File size text at the left
                Row(
                  children: [
                    Opacity(
                        opacity: 0.6,
                        child: const Icon(LucideIcons.video, size: 20)),
                    const SizedBox(
                      width: 2,
                    ),
                    Opacity(
                      opacity: 0.6,
                      child: Text(
                        widget.item.data!["duration"],
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
                WidgetTimeStampPinnedStarred(
                  item: widget.item,
                  showTimestamp: widget.showTimestamp,
                ),
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
  final bool showTimestamp;

  final double? revealOffset;

  const ItemWidgetAudio(
      {super.key, required this.item, required this.showTimestamp, this.revealOffset});

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
        widgetAudioDetails(widget.item, widget.showTimestamp, widget.revealOffset),
      ],
    );
  }
}

Widget widgetAudioDetails(ModelItem item, bool showTimestamp, double? revealOffset) {
  if (showTimestamp) {
    return WidgetTimeStampPinnedStarred(
        item: item, showTimestamp: showTimestamp, revealOffset: revealOffset);
  } else {
    return const SizedBox.shrink();
  }
}

class ItemWidgetDocument extends StatefulWidget {
  final ModelItem item;
  final Function(ModelItem) onTap;
  final bool showTimestamp;

  final double? revealOffset;

  const ItemWidgetDocument(
      {super.key,
      required this.item,
      required this.onTap,
      required this.showTimestamp,
      this.revealOffset});

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
    String title = widget.item.data!.containsKey("title")
        ? widget.item.data!["title"]
        : widget.item.data!["name"];
    bool hasThumbnail = widget.item.thumbnail != null;
    String fileName = widget.item.data!["name"] ?? "";
    String ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : "FILE";
    String size = readableFileSizeFromBytes(widget.item.data!["size"]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              width: 0.75,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                      width: 0.75),
                ),
                child: hasThumbnail
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child:
                            Image.memory(widget.item.thumbnail!, fit: BoxFit.cover))
                    : Icon(LucideIcons.file,
                        size: 18, color: Theme.of(context).colorScheme.primary),
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
                        padding:
                            const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.2),
                              width: 0.75),
                        ),
                        child: Text(ext,
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.primary,
                                letterSpacing: 0.3)),
                      ),
                      const SizedBox(width: 6),
                      Text(size,
                          style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.5))),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
          const SizedBox(height: 4),
          WidgetTimeStampPinnedStarred(
              item: widget.item,
              showTimestamp: widget.showTimestamp,
              revealOffset: widget.revealOffset),
      ],
    );
  }
}

class ItemWidgetLocation extends StatelessWidget {
  final ModelItem item;
  final Function(ModelItem) onTap;
  final bool showTimestamp;

  final double? revealOffset;

  const ItemWidgetLocation(
      {super.key,
      required this.item,
      required this.onTap,
      required this.showTimestamp,
      this.revealOffset});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.red.withValues(alpha: 0.15),
                  width: 0.75),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.red.withValues(alpha: 0.2), width: 0.75),
                  ),
                  child:
                      const Icon(LucideIcons.mapPin, size: 18, color: Colors.red),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Location",
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    const Text("Tap to open in maps",
                        style: TextStyle(fontSize: 10)),
                  ],
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: Colors.red.withValues(alpha: 0.2), width: 0.75),
                  ),
                  child: const Text("View",
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.red,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          WidgetTimeStampPinnedStarred(
              item: item,
              showTimestamp: showTimestamp,
              revealOffset: revealOffset),
        ],
      ),
    );
  }
}

class ItemWidgetContact extends StatelessWidget {
  final ModelItem item;
  final Function(ModelItem) onTap;
  final bool showTimestamp;

  final double? revealOffset;

  const ItemWidgetContact(
      {super.key,
      required this.item,
      required this.onTap,
      required this.showTimestamp,
      this.revealOffset});

  @override
  Widget build(BuildContext context) {
    final Color avatarColor = Colors.green;
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
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.green.withValues(alpha: 0.15),
                  width: 0.75),
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.55))),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          WidgetTimeStampPinnedStarred(
              item: item, 
              showTimestamp: showTimestamp,
              revealOffset: revealOffset),
        ],
      ),
    );
  }
}

class NotePreviewSummary extends StatelessWidget {
  final ModelItem? item;
  final bool? showTimestamp;
  final bool? showImagePreview;
  final bool? expanded;

  const NotePreviewSummary({
    super.key,
    this.item,
    this.showTimestamp,
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

  Widget _previewImage(ModelItem item) {
    switch (item.type) {
      case ItemType.image:
      case ItemType.video:
      case ItemType.contact:
        return item.thumbnail == null
            ? const SizedBox.shrink()
            : ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  width: 40,
                  child: Image.memory(
                    item.thumbnail!, // Full width of container
                    fit: BoxFit.cover,
                  ),
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
        if (showImagePreview!) _previewImage(item!),
        const SizedBox(width: 8),
        if (showTimestamp!)
          Text(
            item == null ? "" : getFormattedTime(item!.at!),
            style: const TextStyle(
              fontSize: 10,
            ),
          ),
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

  Future<void> remove() async {
    removed = await ModelItem.removeUrlInfo(widget.itemId);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return removed
        ? const SizedBox.shrink()
        : Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.35),
                  width: 0.75),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // accent bar
                  Container(
                      width: 3, color: Theme.of(context).colorScheme.primary),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.urlInfo["title"] != null)
                            Text(widget.urlInfo["title"],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          if (widget.urlInfo["desc"] != null) ...[
                            const SizedBox(height: 3),
                            Text(widget.urlInfo["desc"],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.6))),
                          ],
                          const SizedBox(height: 4),
                          Text(
                              Uri.tryParse(widget.urlInfo["url"] ?? "")?.host ??
                                  widget.urlInfo["url"] ??
                                  "",
                              style: TextStyle(
                                  fontSize: 10,
                                  color:
                                      Theme.of(context).colorScheme.primary)),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                      onPressed: remove,
                      icon: Icon(LucideIcons.x,
                          size: 16,
                          color: Theme.of(context).colorScheme.outline),
                      padding: const EdgeInsets.all(8)),
                ],
              ),
            ),
          );
  }
}
