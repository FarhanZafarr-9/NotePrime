import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/contact.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:metadata_fetch/metadata_fetch.dart';
import 'package:ntsapp/ui/common_widgets.dart';
import 'package:ntsapp/utils/enums.dart';
import 'package:ntsapp/models/model_item_file.dart';
import 'package:ntsapp/ui/pages/page_edit_note.dart';
import 'package:ntsapp/services/service_logger.dart';
import 'package:ntsapp/ui/widgets_item.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:siri_wave/siri_wave.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/common.dart';
import '../../models/model_item.dart';
import '../../models/model_item_group.dart';
import 'page_contact_pick.dart';
import 'page_group_add_edit.dart';
import 'page_location_pick.dart';
import 'page_media_viewer.dart';
import '../../services/service_events.dart';

bool isMobile = Platform.isAndroid || Platform.isIOS;

class PageItems extends StatefulWidget {
  final bool runningOnDesktop;
  final Function(PageType, bool, PageParams)? setShowHidePage;
  final List<String> sharedContents;
  final ModelGroup group;
  final String? loadItemIdOnInit;

  const PageItems({
    super.key,
    required this.sharedContents,
    required this.group,
    this.loadItemIdOnInit,
    required this.runningOnDesktop,
    required this.setShowHidePage,
  });

  @override
  State<PageItems> createState() => _PageItemsState();
}

class _PageItemsState extends State<PageItems> with TickerProviderStateMixin {
  final logger = AppLogger(prefixes: ["page_items"]);
  String? showItemId;
  final List<ModelItem> _displayItemList = [];
  final List<ModelItem> _selectedItems = [];
  bool _hasNotesSelected = false;
  bool selectionHasStarredItems = true;
  bool selectionHasPinnedItem = true;
  bool selectionHasOnlyTaskItems = true;
  bool selectionHasOnlyTextItems = true;
  bool selectionHasOnlyTextOrTaskItem = true;

  final TextEditingController _textController = TextEditingController();
  final FocusNode _textControllerFocus = FocusNode();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final GlobalKey<TooltipState> _recordtooltipKey = GlobalKey<TooltipState>();

  ModelGroup? noteGroup;

  bool _isTyping = false;
  bool _isRecording = false;
  late final AudioRecorder _audioRecorder;
  String? _audioFilePath;
  Timer? _recordingTimer;
  int _recordingState = 0;

  ModelItem? replyOnItem;

  bool canScrollToBottom = false;

  bool _isCreatingTask = false;
  bool showDateTime = true;
  bool showNoteBorder = true;

  String imageDirPath = "";

  final Map<String, bool> _filters = {
    "pinned": false,
    "starred": false,
    "notes": false,
    "tasks": false,
    "links": false,
    "images": false,
    "audio": false,
    "video": false,
    "documents": false,
    "contacts": false,
    "locations": false
  };
  bool _filtersEnabled = false;
  bool _shouldBlinkItem = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    EventStream().notifier.addListener(_handleAppEvent);
  }

  @override
  void dispose() {
    EventStream().notifier.removeListener(_handleAppEvent);
    _recordingTimer?.cancel();
    _textController.dispose();
    _textControllerFocus.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _handleAppEvent() {
    final AppEvent? event = EventStream().notifier.value;
    if (event == null) return;
    switch (event.type) {
      case EventType.changedGroupId:
        if (mounted) changedGroup(event.value);
        break;
      case EventType.changedItemId:
        if (mounted) changedItem(event.value);
        break;
      default:
        break;
    }
  }

  Future<void> changedGroup(String? groupId) async {
    if (groupId == null) return;
    if (widget.group.id == groupId) {
      ModelGroup? group = await ModelGroup.get(groupId);
      if (group != null) {
        if (group.archivedAt != null && group.archivedAt! > 0) {
          if (widget.runningOnDesktop) {
            widget.setShowHidePage!(
                PageType.items, false, PageParams(group: group));
          } else {
            if (mounted) Navigator.of(context).pop();
          }
        } else {
          if (mounted) setState(() => noteGroup = group);
          await loadGroupSettings(group);
        }
      } else {
        if (widget.runningOnDesktop) {
          widget.setShowHidePage!(PageType.items, false, PageParams());
        } else {
          if (mounted) Navigator.of(context).pop();
        }
      }
    }
  }

  Future<void> changedItem(String? itemId) async {
    if (itemId == null) return;
    ModelItem? item = await ModelItem.get(itemId);
    ModelItem? oldItem;
    if (item != null) {
      int itemIndex = -1;
      if (item.groupId == widget.group.id) {
        for (ModelItem displayItem in _displayItemList) {
          if (displayItem.id == item.id) {
            oldItem = displayItem;
            itemIndex = _displayItemList.indexOf(displayItem);
            break;
          }
        }
        if (oldItem != null) {
          if (item.archivedAt! > 0) {
            _removeItemsFromDisplayList([oldItem]);
          } else {
            setState(() => _displayItemList[itemIndex] = item);
            if (oldItem.text != item.text) checkFetchUrlMetadata(item);
          }
        } else {
          fetchItems(null);
        }
      }
    }
  }

  Future<void> loadGroupSettings(ModelGroup group) async {
    Map<String, dynamic>? data = group.data;
    if (data != null && mounted) {
      setState(() {
        if (data.containsKey("date_time")) {
          showDateTime = data["date_time"] == 1;
        }
        if (data.containsKey("note_border")) {
          showNoteBorder = data["note_border"] == 1;
        }
        if (data.containsKey("task_mode")) {
          _isCreatingTask = data["task_mode"] == 1;
        }
      });
    }
  }

  Future<void> fetchItems(String? itemId) async {
    List<ModelItem> newItems =
        await ModelItem.getInGroup(noteGroup!.id!, _filters);
    canScrollToBottom = itemId != null;
    _displayItemList.clear();
    await _addItemsToDisplayList(newItems, true);
    setState(() {
      if (itemId != null) {
        ModelItem? itemInItems;
        for (ModelItem item in newItems) {
          if (item.id == itemId) {
            itemInItems = item;
            break;
          }
        }
        if (itemInItems != null) {
          int indexOfItem = _displayItemList.indexOf(itemInItems);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _itemScrollController.jumpTo(index: indexOfItem);
            triggerItemBlink();
          });
        }
      } else {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _itemScrollController.jumpTo(index: 0));
      }
    });
    if (newItems.isEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _textControllerFocus.requestFocus());
    }
  }

  Future<void> loadImageDirectoryPath() async {
    String filePath = await getFilePath("image", "dummy.png");
    setState(() => imageDirPath = path.dirname(filePath));
  }

  Future<void> _addItemsToDisplayList(
      List<ModelItem> items, bool addOlder) async {
    DateTime? lastDate;
    int? lastItemAt;
    if (addOlder) {
      ModelItem? lastDisplayItem =
          _displayItemList.isEmpty ? null : _displayItemList.last;
      DateTime? lastDisplayItemDate = lastDisplayItem == null
          ? null
          : lastDisplayItem.type == ItemType.date
              ? getLocalDateFromUtcMilliSeconds(lastDisplayItem.at!)
              : null;
      for (ModelItem item in items) {
        final currentDate = getLocalDateFromUtcMilliSeconds(item.at!);
        if (lastDisplayItemDate != null && lastDisplayItemDate == currentDate) {
          _displayItemList.removeLast();
          lastDisplayItemDate = null;
        }
        if (lastDate != null && currentDate != lastDate) {
          final ModelItem dateItem = await ModelItem.fromMap({
            "group_id": noteGroup!.id,
            "text": getReadableDate(lastDate),
            "type": 170000,
            "at": lastItemAt! - 1
          });
          _displayItemList.add(dateItem);
        }
        _displayItemList.add(item);
        lastDate = currentDate;
        lastItemAt = item.at!;
      }
      if (lastDate != null) {
        final ModelItem dateItem = await ModelItem.fromMap({
          "group_id": noteGroup!.id,
          "text": getReadableDate(lastDate),
          "type": 170000,
          "at": lastItemAt! - 1
        });
        _displayItemList.add(dateItem);
      }
    } else {
      if (_displayItemList.isNotEmpty) {
        lastDate = getLocalDateFromUtcMilliSeconds(_displayItemList.first.at!);
      }
      for (ModelItem item in items) {
        final currentDate = getLocalDateFromUtcMilliSeconds(item.at!);
        if (lastDate != null && currentDate != lastDate) {
          final ModelItem dateItem = await ModelItem.fromMap({
            "group_id": noteGroup!.id,
            "text": getReadableDate(currentDate),
            "type": 170000,
            "at": item.at! - 1
          });
          _displayItemList.insert(0, dateItem);
        } else if (lastDate == null) {
          final ModelItem dateItem = await ModelItem.fromMap({
            "group_id": noteGroup!.id,
            "text": getReadableDate(currentDate),
            "type": 170000,
            "at": item.at! - 1
          });
          _displayItemList.insert(0, dateItem);
        }
        _displayItemList.insert(0, item);
        lastDate = currentDate;
      }
    }
  }

  void _removeItemsFromDisplayList(List<ModelItem> items) {
    setState(() {
      for (ModelItem item in items) {
        int itemIndex = _displayItemList.indexOf(item);
        if (itemIndex == -1) continue;
        ModelItem nextItem = _displayItemList.elementAt(itemIndex + 1);
        if (nextItem.type == ItemType.date) {
          if (itemIndex > 0) {
            ModelItem previousItem = _displayItemList.elementAt(itemIndex - 1);
            if (previousItem.type == ItemType.date) {
              _displayItemList.removeAt(itemIndex + 1);
            }
          } else {
            _displayItemList.removeAt(itemIndex + 1);
          }
        }
        _displayItemList.remove(item);
      }
    });
  }

  Future<void> loadSharedContents() async {
    List<String> sharedFiles = [];
    List<String> sharedTexts = [];
    for (String sharedContent in widget.sharedContents) {
      File file = File(sharedContent);
      if (file.existsSync()) {
        sharedFiles.add(sharedContent);
      } else {
        sharedTexts.add(sharedContent);
      }
    }
    processFiles(sharedFiles);
    if (sharedTexts.isNotEmpty) {
      for (String text in sharedTexts) {
        _addItemToDbAndDisplayList(text, ItemType.text, null, null);
      }
    }
  }

  void triggerItemBlink() {
    const ms = 250;
    if (mounted) setState(() => _shouldBlinkItem = true);
    Future.delayed(const Duration(milliseconds: ms), () {
      if (mounted) setState(() => _shouldBlinkItem = false);
      Future.delayed(const Duration(milliseconds: ms), () {
        if (mounted) setState(() => _shouldBlinkItem = true);
        Future.delayed(const Duration(milliseconds: ms), () {
          if (mounted) setState(() => _shouldBlinkItem = false);
        });
      });
    });
  }

  void _applyFilters() {
    setState(() {
      _filtersEnabled = _filters.values.any((v) => v == true);
      fetchItems(null);
    });
  }

  void _clearFilters() {
    setState(() {
      _filters.updateAll((key, value) => false);
      _applyFilters();
    });
  }

  void _toggleFilter(String filter) {
    setState(() => _filters[filter] = !_filters[filter]!);
    _applyFilters();
  }

  // ── Filter dialog — icon grid with chip-style toggle ─────────────────────
  void _openFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            final cs = Theme.of(context).colorScheme;

            Widget filterChip(String key, IconData icon, String label) {
              final active = _filters[key]!;
              return GestureDetector(
                onTap: () {
                  setState(() => _filters[key] = !active);
                  _toggleFilter(key);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: active
                        ? cs.onSurface.withValues(alpha: 0.12)
                        : cs.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: active
                          ? cs.onSurface.withValues(alpha: 0.3)
                          : Colors.transparent,
                      width: 0.75,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 16,
                          color: active
                              ? cs.onSurface
                              : cs.onSurfaceVariant.withValues(alpha: 0.5)),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          color: active
                              ? cs.onSurface
                              : cs.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return AlertDialog(
              backgroundColor: cs.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text('Filter notes',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface)),
              content: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  filterChip("pinned", LucideIcons.pin, "Pinned"),
                  filterChip("starred", LucideIcons.star, "Starred"),
                  filterChip("notes", LucideIcons.text, "Notes"),
                  filterChip("tasks", LucideIcons.checkCircle, "Tasks"),
                  filterChip("links", LucideIcons.link, "Links"),
                  filterChip("images", LucideIcons.image, "Images"),
                  filterChip("audio", LucideIcons.music2, "Audio"),
                  filterChip("video", LucideIcons.video, "Video"),
                  filterChip("documents", LucideIcons.file, "Files"),
                  filterChip("contacts", LucideIcons.contact, "Contacts"),
                  filterChip("locations", LucideIcons.mapPin, "Locations"),
                ],
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant),
                  onPressed: () {
                    _clearFilters();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Clear'),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: cs.primary),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void updateSelectionBools() {
    selectionHasStarredItems = true;
    selectionHasOnlyTaskItems = true;
    selectionHasOnlyTextItems = true;
    selectionHasPinnedItem = true;
    selectionHasOnlyTextOrTaskItem = true;
    for (ModelItem item in _selectedItems) {
      if (item.starred == 0) selectionHasStarredItems = false;
      if (item.type.value < ItemType.task.value ||
          item.type.value > ItemType.task.value + 10000) {
        selectionHasOnlyTaskItems = false;
      }
      if (item.type.value > ItemType.text.value &&
          item.type.value < ItemType.task.value) {
        selectionHasOnlyTextOrTaskItem = false;
      }
      if (item.type != ItemType.text) selectionHasOnlyTextItems = false;
      if (item.pinned! == 0) selectionHasPinnedItem = false;
    }
  }

  void onItemLongPressed(ModelItem item) {
    setState(() {
      if (_selectedItems.contains(item)) {
        _selectedItems.remove(item);
        if (_selectedItems.isEmpty) _hasNotesSelected = false;
      } else {
        _selectedItems.add(item);
        if (!_hasNotesSelected) _hasNotesSelected = true;
      }
      updateSelectionBools();
    });
  }

  void onItemTapped(ModelItem item) async {
    if (item.type == ItemType.text) {
      onItemLongPressed(item);
    } else if (_hasNotesSelected) {
      if (_selectedItems.contains(item)) {
        _selectedItems.remove(item);
        if (_selectedItems.isEmpty) _hasNotesSelected = false;
      } else {
        _selectedItems.add(item);
      }
      updateSelectionBools();
    } else if (item.type == ItemType.task) {
      item.type = ItemType.completedTask;
      await item.update(["type"]);
    } else if (item.type == ItemType.completedTask) {
      item.type = ItemType.task;
      await item.update(["type"]);
    }
    setState(() {});
  }

  Future<void> archiveSelectedItems() async {
    for (ModelItem item in _selectedItems) {
      item.archivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
      await item.update(["archived_at"]);
      EventStream()
          .publish(AppEvent(type: EventType.changedItemId, value: item.id));
    }
    if (mounted) {
      displaySnackBar(context, message: "Moved to trash", seconds: 1);
    }
    clearSelection();
  }

  Future<void> updateSelectedItemsPinned() async {
    setState(() {
      for (ModelItem item in _selectedItems) {
        item.pinned = selectionHasPinnedItem ? 0 : 1;
        item.update(["pinned"]);
      }
    });
    clearSelection();
  }

  Future<void> updateSelectedItemsStarred() async {
    setState(() {
      for (ModelItem item in _selectedItems) {
        item.starred = selectionHasStarredItems ? 0 : 1;
        item.update(["starred"]);
      }
    });
    clearSelection();
  }

  String getTextsFromSelectedItems() {
    List<String> texts = [];
    for (ModelItem item in _selectedItems) {
      if (item.type == ItemType.text ||
          item.type == ItemType.task ||
          item.type == ItemType.completedTask) {
        texts.add(item.text);
      }
    }
    return texts.reversed.join("\n");
  }

  Future<void> copyToClipboard() async {
    Clipboard.setData(ClipboardData(text: getTextsFromSelectedItems()));
    if (mounted) {
      displaySnackBar(context, message: 'Copied to clipboard', seconds: 1);
    }
    clearSelection();
  }

  void shareNotes() {
    List<String> texts = [];
    List<XFile> medias = [];
    for (ModelItem item in _selectedItems) {
      switch (item.type) {
        case ItemType.text:
        case ItemType.task:
        case ItemType.completedTask:
          texts.add(item.text);
          break;
        case ItemType.location:
          Map<String, dynamic> locationData = item.data!;
          Map<String, String> mapUrls =
              getMapUrls(locationData["lat"], locationData["lng"]);
          texts.add(
              ["Location:", mapUrls["google"]!, mapUrls["apple"]!].join("\n"));
          break;
        case ItemType.contact:
          Map<String, dynamic> d = item.data!;
          texts.add([
            d["name"],
            ["Contact:", d["phones"].join("\n")].join("\n"),
            ["Emails:", d["emails"].join("\n")].join("\n"),
            ["Addresses:", d["addresses"].join("\n")].join("\n")
          ].join("\n"));
          break;
        case ItemType.image:
          final f = File(item.data!["path"]);
          if (f.existsSync()) medias.add(XFile(item.data!["path"]));
          break;
        case ItemType.audio:
          final f = File(item.data!["path"]);
          if (f.existsSync()) medias.add(XFile(item.data!["path"]));
          break;
        case ItemType.video:
          final f = File(item.data!["path"]);
          if (f.existsSync()) medias.add(XFile(item.data!["path"]));
          break;
        case ItemType.document:
          final f = File(item.data!["path"]);
          if (f.existsSync()) medias.add(XFile(item.data!["path"]));
          break;
        default:
          break;
      }
    }
    Share.shareXFiles(medias, text: texts.join("\n"));
    clearSelection();
  }

  void editNote() {
    ModelItem item = _selectedItems.first;
    if (widget.runningOnDesktop) {
      widget.setShowHidePage!(PageType.editNote, true, PageParams(id: item.id));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => PageEditNote(
          itemId: item.id!,
          runningOnDesktop: widget.runningOnDesktop,
          setShowHidePage: widget.setShowHidePage,
        ),
        settings: const RouteSettings(name: "EditNote"),
      ));
    }
    clearSelection();
  }

  Future<void> updateSelectedItemsTaskType() async {
    ItemType setType =
        selectionHasOnlyTaskItems ? ItemType.text : ItemType.task;
    setState(() {
      for (ModelItem item in _selectedItems) {
        if (setType == ItemType.text) {
          item.type = setType;
        } else if (setType == ItemType.task && item.type == ItemType.text) {
          item.type = setType;
        }
        item.update(["type"]);
      }
    });
    clearSelection();
  }

  void clearSelection() {
    setState(() {
      _selectedItems.clear();
      _hasNotesSelected = false;
    });
  }

  void _onInputTextChanged(String text) {
    setState(() => _isTyping = _textController.text.trim().isNotEmpty);
  }

  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final tempDir = await getTemporaryDirectory();
      final int utcSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      _audioFilePath = path.join(tempDir.path, 'recording_$utcSeconds.m4a');
      try {
        await _audioRecorder.start(const RecordConfig(), path: _audioFilePath!);
        setState(() {
          _isRecording = true;
          _recordingState = 1;
        });
        HapticFeedback.vibrate();
      } catch (e, s) {
        if (e is PlatformException && e.code == "record") {
          if (mounted) {
            displaySnackBar(context,
                message: "Microphone may not be available.", seconds: 1);
          }
        } else {
          logger.error("Recording failed", error: e, stackTrace: s);
        }
      }
    } else {
      if (mounted) {
        displaySnackBar(context,
            message: "Microphone permission is required.", seconds: 1);
      }
    }
  }

  Future<void> _pauseResumeRecording() async {
    if (_recordingState == 1) {
      await _audioRecorder.pause();
      setState(() => _recordingState = 2);
    } else {
      await _audioRecorder.resume();
      setState(() => _recordingState = 1);
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    String? p = await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _recordingState = 0;
    });
    if (p != null) {
      await processFiles([p]);
      await _audioRecorder.cancel();
    }
  }

  void addToContacts(ModelItem item) {
    if (_hasNotesSelected) onItemTapped(item);
  }

  Future<void> generateAddSeedItems() async {
    showProcessing();
    const int daysToGenerate = 10;
    const int messagesPerDay = 50;
    final now = DateTime.now();
    for (int dayOffset = 0; dayOffset < daysToGenerate; dayOffset++) {
      final date = now.subtract(Duration(days: dayOffset));
      final dateString =
          "${date.year} ${date.month.toString().padLeft(2, '0')} ${date.day.toString().padLeft(2, '0')}";
      for (int messageCount = 1;
          messageCount <= messagesPerDay;
          messageCount++) {
        final timestamp =
            DateTime(date.year, date.month, date.day, 14, messageCount)
                .millisecondsSinceEpoch;
        final text = "$dateString, $messageCount";
        final ModelItem item = await ModelItem.fromMap({
          "group_id": noteGroup!.id,
          "text": text,
          "type": ItemType.text,
          "at": timestamp
        });
        await item.insert();
      }
    }
    hideProcessing();
    if (mounted) setState(() {});
  }

  void _addItemToDbAndDisplayList(
    String text,
    ItemType type,
    Uint8List? thumbnail,
    Map<String, dynamic>? data,
  ) async {
    if (replyOnItem != null) {
      data = data ?? {};
      data["reply_on"] = replyOnItem!.id;
    }
    ModelItem item = await ModelItem.fromMap({
      "group_id": noteGroup!.id,
      "text": text,
      "type": type,
      "thumbnail": thumbnail,
      "data": data,
    });
    await item.insert();
    EventStream()
        .publish(AppEvent(type: EventType.changedItemId, value: item.id));
    await checkAddItemFileHash(item);
    setState(() {
      if (!_displayItemList.contains(item)) {
        _addItemsToDisplayList([item], false);
      }
      replyOnItem = null;
    });
    if (type == ItemType.text) checkFetchUrlMetadata(item);
  }

  Future<void> checkAddItemFileHash(ModelItem item) async {
    if (item.data != null) {
      String? fileHashName =
          getValueFromMap(item.data!, "name", defaultValue: null);
      if (fileHashName != null) {
        ModelItemFile itemFile =
            ModelItemFile(id: item.id!, fileHash: fileHashName);
        await itemFile.insert();
      }
    }
  }

  Future<void> checkFetchUrlMetadata(ModelItem item) async {
    final RegExp linkRegExp = RegExp(r'(https?://[^\s]+)');
    final matches = linkRegExp.allMatches(item.text);
    String link = "";
    for (final match in matches) {
      link = item.text.substring(match.start, match.end);
      break;
    }
    if (link.isNotEmpty) {
      try {
        final Metadata? metaData = await MetadataFetch.extract(link);
        if (metaData != null) {
          int portrait = 1;
          if (metaData.image != null) {
            portrait =
                await checkDownloadNetworkImage(item.id!, metaData.image!);
          }
          Map<String, dynamic> urlInfo = {
            "url": link,
            "title": metaData.title,
            "desc": metaData.description,
            "image": metaData.image,
            "portrait": portrait
          };
          item.data = {...?item.data, "url_info": urlInfo};
          await item.update(["data"]);
          if (mounted) setState(() {});
        }
      } catch (e) {
        logger.error("error fetch metadata", error: e);
      }
    } else {
      Map<String, dynamic>? data = item.data;
      if (data != null && data.containsKey("url_info")) {
        data.remove("url_info");
        item.data = data;
        await item.update(["data"]);
        if (mounted) setState(() {});
      }
    }
  }

  void showProcessing() => showProcessingDialog(context);
  void hideProcessing() => Navigator.pop(context);

  Future<void> processFiles(List<String> filePaths) async {
    if (filePaths.isEmpty) return;
    showProcessing();
    for (String filePath in filePaths) {
      Map<String, dynamic>? attrs = await processAndGetFileAttributes(filePath);
      if (attrs == null) continue;
      String mime = attrs["mime"];
      String newPath = attrs["path"];
      String type = mime.split("/").first;
      String fileName = attrs["name"];
      switch (type) {
        case "image":
          Uint8List fileBytes = await File(newPath).readAsBytes();
          Uint8List? thumbnail = await compute(getImageThumbnail, fileBytes);
          if (thumbnail != null) {
            final decodedImage = await decodeImageFromList(fileBytes);
            _addItemToDbAndDisplayList(
                'DND|#image|$fileName', ItemType.image, thumbnail, {
              "path": newPath,
              "mime": mime,
              "name": fileName,
              "size": attrs["size"],
              "width": decodedImage.width.toDouble(),
              "height": decodedImage.height.toDouble(),
            });
          }
          break;
        case "video":
          VideoInfoExtractor extractor = VideoInfoExtractor(newPath);
          try {
            final mediaInfo = await extractor.getVideoInfo();
            int durationSeconds = mediaInfo['duration'];
            Uint8List? thumbnail = await extractor.getThumbnail(
                seekPosition:
                    Duration(milliseconds: (durationSeconds * 500).toInt()));
            _addItemToDbAndDisplayList(
                'DND|#video|$fileName', ItemType.video, thumbnail, {
              "path": newPath,
              "mime": mime,
              "name": fileName,
              "size": attrs["size"],
              "aspect": mediaInfo['aspect'],
              "duration": mediaFileDurationFromSeconds(durationSeconds)
            });
          } catch (e, s) {
            logger.error("ExtractingVideoInfo", error: e, stackTrace: s);
          } finally {
            extractor.dispose();
          }
          break;
        case "audio":
          String? duration = await getAudioDuration(newPath);
          if (duration != null) {
            _addItemToDbAndDisplayList(
                'DND|#audio|$fileName', ItemType.audio, null, {
              "path": newPath,
              "mime": mime,
              "name": fileName,
              "size": attrs["size"],
              "duration": duration
            });
          }
          break;
        default:
          _addItemToDbAndDisplayList(
              'DND|#document|$fileName', ItemType.document, null, {
            "path": newPath,
            "mime": mime,
            "name": fileName,
            "size": attrs["size"],
            "title": attrs.containsKey("title") ? attrs["title"] : fileName
          });
      }
    }
    hideProcessing();
  }

  void _addMedia(String type) async {
    if (type == "files") {
      try {
        FilePickerResult? result = await FilePicker.platform
            .pickFiles(allowMultiple: true, type: FileType.any);
        if (result != null) {
          processFiles(
              result.files.map((f) => f.path).whereType<String>().toList());
        }
      } catch (e, s) {
        if (e is PlatformException &&
            e.code == 'read_external_storage_denied' &&
            mounted) {
          displaySnackBar(context,
              message: 'Storage permission denied.', seconds: 1);
        } else {
          logger.error("Error opening files", error: e, stackTrace: s);
        }
      }
    } else if (type == "camera_image") {
      XFile? f = await ImagePicker().pickImage(source: ImageSource.camera);
      if (f != null) processFiles([f.path]);
    } else if (type == "camera_video") {
      XFile? f = await ImagePicker().pickVideo(source: ImageSource.camera);
      if (f != null) processFiles([f.path]);
    } else if (type == "location") {
      Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (_) => const LocationPicker(),
              settings: const RouteSettings(name: "LocationPicker")))
          .then((value) {
        if (value != null) {
          LatLng position = value as LatLng;
          _addItemToDbAndDisplayList("DND|#location", ItemType.location, null,
              {"lat": position.latitude, "lng": position.longitude});
        }
      });
    } else if (type == "contact") {
      Navigator.of(context)
          .push(MaterialPageRoute(
              builder: (_) => const PageContacts(),
              settings: const RouteSettings(name: "ContactPicker")))
          .then((value) {
        if (value != null) {
          Contact contact = value as Contact;
          List<String> phones = contact.phones.map((p) => p.number).toList();
          List<String> emails = contact.emails.map((e) => e.address).toList();
          List<String> addresses =
              contact.addresses.map((a) => a.address).toList();
          _addItemToDbAndDisplayList(
              'DND|#contact|${contact.displayName}|${contact.name.first}|${contact.name.last}|${phones.join("|")}',
              ItemType.contact,
              contact.thumbnail, {
            "name": contact.displayName,
            "first": contact.name.first,
            "last": contact.name.last,
            "phones": phones,
            "emails": emails,
            "addresses": addresses
          });
        }
      });
    }
  }

  void _handleTextInput(String text) {
    text = text.trim();
    if (text.isNotEmpty) {
      _addItemToDbAndDisplayList(
          text, _isCreatingTask ? ItemType.task : ItemType.text, null, null);
      _textController.clear();
      _onInputTextChanged("");
      _textControllerFocus.requestFocus();
    }
  }

  void navigateToPageGroupEdit() {
    if (widget.runningOnDesktop) {
      widget.setShowHidePage!(
          PageType.addEditGroup, true, PageParams(group: noteGroup));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => PageGroupAddEdit(
          runningOnDesktop: widget.runningOnDesktop,
          setShowHidePage: widget.setShowHidePage,
          group: noteGroup,
        ),
        settings: const RouteSettings(name: "EditNoteGroup"),
      ));
    }
  }

  Future<void> setTaskMode() async {
    setState(() => _isCreatingTask = !_isCreatingTask);
    Map<String, dynamic> data = noteGroup!.data ?? {};
    data["task_mode"] = _isCreatingTask ? 1 : 0;
    noteGroup!.data = data;
    await noteGroup!.update(["data"]);
  }

  // ── Popup menu item (same style as home page) ─────────────────────────────
  Widget _menuItem({
    required BuildContext context,
    required int value,
    required IconData icon,
    required String label,
    bool extraTopRadius = false,
    bool extraBottomRadius = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(extraTopRadius ? 12 : 8),
      topRight: Radius.circular(extraTopRadius ? 12 : 8),
      bottomLeft: Radius.circular(extraBottomRadius ? 12 : 8),
      bottomRight: Radius.circular(extraBottomRadius ? 12 : 8),
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.pop(context, value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(extraTopRadius ? 9 : 7),
                        topRight: Radius.circular(7),
                        bottomLeft: Radius.circular(extraBottomRadius ? 9 : 7),
                        bottomRight: Radius.circular(7),
                      ),
                    ),
                    child: Icon(icon, size: 16, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 12),
                  Text(label,
                      style: TextStyle(fontSize: 14, color: cs.onSurface)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAppbarDefaultOptions() {
    return [
      PopupMenuButton<int>(
        padding: EdgeInsets.zero,
        onSelected: (value) {
          if (value == 0) navigateToPageGroupEdit();
          if (value == 1) _openFilterDialog();
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
            width: 0.75,
          ),
        ),
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        elevation: 4,
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 220),
        itemBuilder: (context) => [
          PopupMenuItem<int>(
            value: 0,
            padding: EdgeInsets.zero,
            height: 0,
            child: _menuItem(
                context: context,
                value: 0,
                icon: LucideIcons.edit3,
                label: 'Edit',
                extraTopRadius: true,
                ),
          ),
          PopupMenuItem(
            enabled: false,
            height: 0,
            padding: EdgeInsets.zero,
            child: Divider(
              height: 6,
              thickness: 0.75,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.1),
            ),
          ),
          PopupMenuItem<int>(
            value: 1,
            padding: EdgeInsets.zero,
            height: 0,
            child: _menuItem(
                context: context,
                value: 1,
                icon: LucideIcons.filter,
                label: 'Filters',
                extraBottomRadius: true,
                ),
          ),
        ],
      ),
    ];
  }

  Future<void> replyOnSwipe(ModelItem item) async {
    setState(() => replyOnItem = item);
  }

  Future<void> cancelReplyItem() async {
    setState(() => replyOnItem = null);
  }

  Future<void> showHideScrollToBottomButton(double scrolledHeight) async {
    bool requiresUpdate = false;
    if (scrolledHeight > 100 && !canScrollToBottom) {
      canScrollToBottom = true;
      requiresUpdate = true;
    } else if (scrolledHeight <= 100 && canScrollToBottom) {
      canScrollToBottom = false;
      requiresUpdate = true;
    }
    if (requiresUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (noteGroup != widget.group) {
      noteGroup = widget.group;
      loadGroupSettings(noteGroup!);
      if (showItemId != widget.loadItemIdOnInit) {
        showItemId = widget.loadItemIdOnInit;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        fetchItems(showItemId);
        loadImageDirectoryPath();
        if (widget.sharedContents.isNotEmpty) loadSharedContents();
      });
    }

    final edgeToEdgePadding = MediaQuery.of(context).padding;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.runningOnDesktop,
        actions: _buildAppbarDefaultOptions(),
        title: Text(
          noteGroup == null ? "" : noteGroup!.title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: edgeToEdgePadding.bottom),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification scrollInfo) {
                      showHideScrollToBottomButton(scrollInfo.metrics.pixels);
                      return false;
                    },
                    child: ScrollablePositionedList.builder(
                      itemScrollController: _itemScrollController,
                      itemPositionsListener: _itemPositionsListener,
                      reverse: true,
                      itemCount: _displayItemList.length,
                      itemBuilder: (context, index) {
                        if (index < 0 || index >= _displayItemList.length) {
                          return const SizedBox.shrink();
                        }
                        final ModelItem item = _displayItemList[index];

                        bool showTimePill = false;
                        if (index == _displayItemList.length - 1) {
                          showTimePill = true;
                        } else {
                          final olderItem = _displayItemList[index + 1];
                          if (olderItem.type == ItemType.date) {
                            showTimePill = true;
                          } else {
                            final diff = DateTime.fromMillisecondsSinceEpoch(
                                    item.at!,
                                    isUtc: true)
                                .difference(DateTime.fromMillisecondsSinceEpoch(
                                    olderItem.at!,
                                    isUtc: true));
                            if (diff.abs().inMinutes >= 5) showTimePill = true;
                          }
                        }

                        final bool isAttachment = item.type == ItemType.image ||
                            item.type == ItemType.video ||
                            item.type == ItemType.audio ||
                            item.type == ItemType.document ||
                            item.type == ItemType.location ||
                            item.type == ItemType.contact;

                        Widget mainItem;
                        if (item.type == ItemType.date) {
                          mainItem = showDateTime
                              ? ItemWidgetDate(item: item)
                              : const SizedBox.shrink();
                        } else {
                          Map<String, dynamic>? urlInfo = item.data != null &&
                                  item.data!.containsKey("url_info")
                              ? item.data!["url_info"]
                              : null;

                          mainItem = Dismissible(
                            key: ValueKey(item.id),
                            direction: DismissDirection.startToEnd,
                            confirmDismiss: (direction) async {
                              replyOnSwipe(item);
                              return false;
                            },
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              child: Row(
                                children: [
                                  Icon(LucideIcons.reply,
                                      size: 18, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 8),
                                  Text(
                                    getFormattedTime(item.at!),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant
                                            .withValues(alpha: 0.6)),
                                  ),
                                ],
                              ),
                            ),
                            child: GestureDetector(
                              onLongPress: () => onItemLongPressed(item),
                              onTap: () => onItemTapped(item),
                              child: Container(
                                width: double.infinity,
                                color: _selectedItems.contains(item) ||
                                        (_shouldBlinkItem &&
                                            showItemId != null &&
                                            showItemId == item.id)
                                    ? cs.onSurface.withValues(alpha: 0.1)
                                    : Colors.transparent,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                  margin: EdgeInsets.only(
                                      top: 2,
                                      bottom: 2,
                                      right: 12,
                                      left: isAttachment ? 0 : 12,
                                    ),
                                    child: Material(
                                      shape: RoundedRectangleBorder(
                                       borderRadius: BorderRadius.circular(16),
                                        side: BorderSide(
                                          color:
                                              (showNoteBorder && !isAttachment)
                                                  ? cs.onSurface
                                                      .withValues(alpha: 0.1)
                                                  : Colors.transparent,
                                          width: 0.5,
                                        ),
                                      ),
                                      color: isAttachment
                                          ? Colors.transparent
                                          : cs.onSurface
                                              .withValues(alpha: 0.07),
                                      child: Container(
                                        margin: EdgeInsets.symmetric(
                                            vertical: isAttachment ? 2 : 8,
                                            horizontal: isAttachment ? 0 : 8),
                                        padding: EdgeInsets.all(
                                            isAttachment ? 0 : 6),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (item.replyOn != null)
                                              GestureDetector(
                                                onTap: () => fetchItems(
                                                    item.replyOn!.id),
                                                child: NotePreviewSummary(
                                                  item: item.replyOn!,
                                                  showImagePreview: true,
                                                  expanded: false,
                                                ),
                                              ),
                                            if (urlInfo != null)
                                              GestureDetector(
                                                onTap: () async {
                                                  if (_hasNotesSelected) {
                                                    onItemTapped(item);
                                                  } else {
                                                    final linkUri = Uri.parse(
                                                        urlInfo["url"]);
                                                    if (await canLaunchUrl(
                                                        linkUri)) {
                                                      await launchUrl(linkUri);
                                                    }
                                                  }
                                                },
                                                child: NoteUrlPreview(
                                                  urlInfo: urlInfo,
                                                  imageDirectory: imageDirPath,
                                                  itemId: item.id!,
                                                ),
                                              ),
                                            _buildNoteItem(item),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        if (showTimePill &&
                            showDateTime &&
                            item.type != ItemType.date) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ItemWidgetTimePill(
                                  timeText: getFormattedTime(item.at!)),
                              mainItem,
                            ],
                          );
                        }
                        return mainItem;
                      },
                    ),
                  ),

                  // Scroll-to-bottom FAB
                  if (canScrollToBottom)
                    Positioned(
                      bottom: 10,
                      right: 20,
                      child: FloatingActionButton(
                        heroTag: "scroll_to_bottom",
                        mini: true,
                        onPressed: () {
                          clearSelection();
                          fetchItems(null);
                        },
                        shape: const CircleBorder(),
                        backgroundColor: cs.onSurface.withValues(alpha: 0.06),
                        foregroundColor: cs.onSurface,
                        child: const Icon(LucideIcons.chevronsDown),
                      ),
                    ),

                  // Active filter indicator
                  if (_filtersEnabled)
                    Positioned(
                      right: 0,
                      child: IconButton(
                        tooltip: "Filter notes",
                        onPressed: _openFilterDialog,
                        icon: const Icon(LucideIcons.filter),
                      ),
                    ),
                ],
              ),
            ),
            AnimatedWidgetSwap(
              firstWidget: widgetBottomSection(),
              secondWidget: widgetSelectionOptions(),
              showFirst: !_hasNotesSelected,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteItem(ModelItem item) {
    switch (item.type) {
      case ItemType.text:
        return ItemWidgetText(item: item);
      case ItemType.image:
        return ItemWidgetImage(item: item, onTap: viewImageVideo);
      case ItemType.video:
        return ItemWidgetVideo(item: item, onTap: viewImageVideo);
      case ItemType.audio:
        return ItemWidgetAudio(item: item);
      case ItemType.document:
        return ItemWidgetDocument(item: item, onTap: openDocument);
      case ItemType.location:
        return ItemWidgetLocation(item: item, onTap: openLocation);
      case ItemType.contact:
        return ItemWidgetContact(item: item, onTap: addToContacts);
      case ItemType.completedTask:
      case ItemType.task:
        return ItemWidgetTask(item: item);
      default:
        return const SizedBox.shrink();
    }
  }

  void viewImageVideo(ModelItem item) async {
    if (_hasNotesSelected) {
      onItemTapped(item);
    } else {
      String id = item.id!;
      String groupId = item.groupId;
      int index = await ModelItem.mediaIndexInGroup(groupId, id);
      int count = await ModelItem.mediaCountInGroup(groupId);
      if (mounted) {
        if (widget.runningOnDesktop) {
          widget.setShowHidePage!(
              PageType.mediaViewer,
              true,
              PageParams(
                  group: noteGroup,
                  id: id,
                  mediaIndexInGroup: index,
                  mediaCountInGroup: count));
        } else {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => PageMediaViewer(
              runningOnDesktop: widget.runningOnDesktop,
              id: id,
              groupId: groupId,
              index: index,
              count: count,
            ),
            settings: const RouteSettings(name: "NoteGroupMedia"),
          ));
        }
      }
    }
  }

  void openDocument(ModelItem item) {
    if (_hasNotesSelected) {
      onItemTapped(item);
    } else {
      String filePath = item.data!["path"];
      if (!File(filePath).existsSync()) {
        if (mounted) {
          showAlertMessage(context, "Please wait", "File not available yet");
        }
      } else {
        openMedia(filePath);
      }
    }
  }

  void openLocation(ModelItem item) {
    if (_hasNotesSelected) {
      onItemTapped(item);
    } else {
      openLocationInMap(item.data!["lat"], item.data!["lng"]);
    }
  }

  Widget _buildRecordingSection() {
    final controller = IOS7SiriWaveformController(
      amplitude: 0.5,
      color: Colors.red,
      frequency: 4,
      speed: 0.10,
    );
    return Padding(
      padding: const EdgeInsets.all(5.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TimerWidget(runningState: _recordingState),
          if (_recordingState == 1)
            Flexible(
              child: SiriWaveform.ios7(
                controller: controller,
                options: const IOS7SiriWaveformOptions(height: 40),
              ),
            ),
          IconButton(
            onPressed: _pauseResumeRecording,
            icon: Icon(_recordingState == 1 ? Icons.pause : Icons.play_arrow),
          ),
        ],
      ),
    );
  }

  // ── Selection action bar ──────────────────────────────────────────────────
  Widget widgetSelectionOptions() {
    final cs = Theme.of(context).colorScheme;
    const double iconSize = 20;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        border: Border(
          top: BorderSide(
              color: cs.onSurface.withValues(alpha: 0.08), width: 0.5),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: "Clear selection",
              iconSize: iconSize,
              onPressed: clearSelection,
              icon: const Icon(LucideIcons.x),
            ),
            if (selectionHasOnlyTextOrTaskItem)
              IconButton(
                tooltip: "Copy",
                iconSize: iconSize,
                onPressed: copyToClipboard,
                icon: const Icon(LucideIcons.copy),
              ),
            if (selectionHasOnlyTextOrTaskItem)
              IconButton(
                tooltip: "Toggle task",
                iconSize: iconSize,
                onPressed: updateSelectedItemsTaskType,
                icon: Icon(selectionHasOnlyTaskItems
                    ? LucideIcons.text
                    : LucideIcons.checkCircle),
              ),
            IconButton(
              tooltip: "Share",
              iconSize: iconSize,
              onPressed: shareNotes,
              icon: const Icon(LucideIcons.share2),
            ),
            if (selectionHasOnlyTextOrTaskItem && _selectedItems.length == 1)
              IconButton(
                tooltip: "Edit note",
                iconSize: iconSize,
                onPressed: editNote,
                icon: const Icon(LucideIcons.edit2),
              ),
            IconButton(
              tooltip: "Star/unstar",
              iconSize: iconSize,
              onPressed: updateSelectedItemsStarred,
              icon: Icon(selectionHasStarredItems
                  ? LucideIcons.starOff
                  : LucideIcons.star),
            ),
            IconButton(
              tooltip: "Move to trash",
              iconSize: iconSize,
              onPressed: archiveSelectedItems,
              icon: const Icon(LucideIcons.trash),
            ),
            IconButton(
              tooltip: "Pin/unpin",
              iconSize: iconSize,
              onPressed: updateSelectedItemsPinned,
              icon: Icon(selectionHasPinnedItem
                  ? LucideIcons.pinOff
                  : LucideIcons.pin),
            ),
          ],
        ),
      ),
    );
  }

  // ── Input bar ─────────────────────────────────────────────────────────────
  Widget widgetBottomSection() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Standalone + button (always visible)
            if (!_isRecording)
              Padding(
                padding: const EdgeInsets.only(bottom: 2, right: 6),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    tooltip: "Attach",
                    icon: const Icon(LucideIcons.plus, size: 20),
                    color: cs.onSurfaceVariant,
                    onPressed: _showAttachmentOptions,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            Expanded(
              child: _isRecording
                  ? _buildRecordingSection()
                  : Column(
                      children: [
                        if (replyOnItem != null)
                          Container(
                            padding: const EdgeInsets.all(4),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: NotePreviewSummary(
                                    item: replyOnItem!,
                                    showImagePreview: true,
                                    expanded: true,
                                  ),
                                ),
                                IconButton(
                                  tooltip: "Cancel reply",
                                  icon: const Icon(LucideIcons.x),
                                  onPressed: cancelReplyItem,
                                ),
                              ],
                            ),
                          ),
                        TextField(
                          controller: _textController,
                          focusNode: _textControllerFocus,
                          maxLines: 10,
                          minLines: 1,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: _handleTextInput,
                          style: TextStyle(color: cs.onSurface),
                          decoration: InputDecoration(
                            filled: true,
                            hintText: _isCreatingTask
                                ? "Create a task"
                                : "Add a note...",
                            hintStyle: TextStyle(
                                color:
                                    cs.onSurfaceVariant.withValues(alpha: 0.5),
                                fontWeight: FontWeight.w400),
                            fillColor: cs.onSurface.withValues(alpha: 0.06),
                            hoverColor: Colors.transparent,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide(
                                  color: cs.onSurface.withValues(alpha: 0.15),
                                  width: 0.75),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                          onChanged: _onInputTextChanged,
                          scrollController: ScrollController(),
                          textAlignVertical: TextAlignVertical.top,
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: 6),
            // Send / record button
            GestureDetector(
              onLongPress: () async {
                if (!_isTyping) {
                  _recordtooltipKey.currentState?.ensureTooltipVisible();
                  await Future.delayed(const Duration(seconds: 1), () {
                    if (mounted) Tooltip.dismissAllToolTips();
                  });
                }
                if (!_isTyping && !_isRecording) await _startRecording();
              },
              onTap: () async {
                if (_isRecording) {
                  await _stopRecording();
                } else if (_isTyping) {
                  _handleTextInput(_textController.text);
                } else {
                  if (mounted) {
                    displaySnackBar(context,
                        message: 'Hold to start recording.', seconds: 1);
                  }
                }
              },
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: Tooltip(
                        message: _isTyping ? "Add note" : "Record/stop audio",
                        key: _recordtooltipKey,
                        triggerMode: TooltipTriggerMode.manual,
                        child: Icon(
                          key: ValueKey<String>(_isRecording
                              ? 'stop'
                              : _isTyping
                                  ? _isCreatingTask
                                      ? 'check'
                                      : 'send'
                                  : 'mic'),
                          _isRecording
                              ? Icons.stop
                              : _isTyping
                                  ? _isCreatingTask
                                      ? Icons.check
                                      : Icons.send
                                  : Icons.mic,
                          size: 20,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Attachment bottom sheet ───────────────────────────────────────────────
  void _showAttachmentOptions() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 2-column grid of attachment options
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.9,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    if (Platform.isAndroid || Platform.isIOS)
                      _attachmentGridItem(
                          context, LucideIcons.contact, "Contact", () {
                        Navigator.pop(context);
                        _addMedia('contact');
                      }),
                    _attachmentGridItem(context, LucideIcons.mapPin, "Location",
                        () {
                      Navigator.pop(context);
                      _addMedia('location');
                    }),
                    if (ImagePicker().supportsImageSource(ImageSource.camera))
                      _attachmentGridItem(context, LucideIcons.camera, "Camera",
                          () {
                        Navigator.pop(context);
                        _addMedia("camera_image");
                      }),
                    _attachmentGridItem(context, LucideIcons.file, "Files", () {
                      Navigator.pop(context);
                      _addMedia('files');
                    }),
                    _attachmentGridItem(
                        context, LucideIcons.checkCircle, "Checklist", () {
                      Navigator.pop(context);
                      setTaskMode();
                    }, active: _isCreatingTask),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _attachmentGridItem(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: active
                  ? cs.onSurface.withValues(alpha: 0.12)
                  : cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: active
                  ? Border.all(
                      color: cs.onSurface.withValues(alpha: 0.2), width: 0.75)
                  : null,
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
