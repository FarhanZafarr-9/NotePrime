import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import '../../models/model_setting.dart';

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
  bool linkPreview = true;
  bool sortOldestFirst = false;
  bool mediaGallery = false;
  bool privacyShield = false;

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

  final Set<String> _fetchingItemIds = {};
  final RegExp _linkRegExp = RegExp(r'(https?://[^\s]+)');


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
      case EventType.exitSettings:
        if (mounted && noteGroup != null) loadGroupSettings(noteGroup!);
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
    bool useGroupSettings =
        ModelSetting.get("use_group_settings", "yes") == "yes";
    Map<String, dynamic>? data = group.data;

    if (mounted) {
      setState(() {
        if (useGroupSettings && data != null) {
          if (data.containsKey("date_time")) {
            showDateTime = data["date_time"] == 1;
          }
          if (data.containsKey("note_border")) {
            showNoteBorder = data["note_border"] == 1;
          }
          if (data.containsKey("link_preview")) {
            linkPreview = data["link_preview"] == 1;
          } else {
            linkPreview = true; // default on
          }
          if (data.containsKey("sort_order")) {
            sortOldestFirst = data["sort_order"] == 1;
          } else {
            sortOldestFirst = false; // default newest first
          }
          if (data.containsKey("media_gallery")) {
            mediaGallery = data["media_gallery"] == 1;
          } else {
            mediaGallery = false; // default off
          }
          if (data.containsKey("privacy_shield")) {
            privacyShield = data["privacy_shield"] == 1;
          } else {
            privacyShield =
                ModelSetting.get("privacy_shield_enabled", "no") == "yes";
          }
        } else {
          showDateTime =
              ModelSetting.get("global_show_date_time", "yes") == "yes";
          showNoteBorder =
              ModelSetting.get("global_show_note_border", "yes") == "yes";
          linkPreview =
              ModelSetting.get("global_link_preview", "yes") == "yes";
          sortOldestFirst =
              ModelSetting.get("global_sort_order", "newest") == "oldest";
          mediaGallery =
              ModelSetting.get("global_media_gallery", "no") == "yes";
          privacyShield =
              ModelSetting.get("privacy_shield_enabled", "no") == "yes";
        }

        // task_mode is always group-specific as per user feedback
        if (data != null && data.containsKey("task_mode")) {
          _isCreatingTask = data["task_mode"] == 1;
        }
      });
    }
  }

  Future<void> fetchItems(String? itemId) async {
    List<ModelItem> newItems = await ModelItem.getInGroup(
        noteGroup!.id!, _filters,
        sortAsc: sortOldestFirst);
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
          FocusManager.instance.primaryFocus?.unfocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future.delayed(const Duration(milliseconds: 80), () {
              if (mounted) {
                _itemScrollController.jumpTo(index: indexOfItem);
                triggerItemBlink();
              }
            });
          });
        }
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _displayItemList.isNotEmpty) {
            _itemScrollController.jumpTo(index: 0);
          }
        });
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
    if (items.isEmpty) return;

    if (addOlder) {
      // Initial load or loading more (cleared list)
      DateTime? lastDate;
      for (var item in items) {
        final currentDate = getLocalDateFromUtcMilliSeconds(item.at!);

        if (sortOldestFirst) {
          // [Date1, Msg1, Date2, Msg2...]
          if (currentDate != lastDate) {
            final dateItem = await ModelItem.fromMap({
              "group_id": noteGroup!.id,
              "text": getReadableDate(currentDate),
              "type": 170000,
              "at": item.at! - 1
            });
            _displayItemList.add(dateItem);
          }
          _displayItemList.add(item);
        } else {
          // [MsgN, MsgN-1, DateN, MsgN-2...] - Reversed view
          _displayItemList.add(item);
          final nextIndex = items.indexOf(item) + 1;
          final nextItemDate = nextIndex < items.length
              ? getLocalDateFromUtcMilliSeconds(items[nextIndex].at!)
              : null;

          if (currentDate != nextItemDate) {
            final dateItem = await ModelItem.fromMap({
              "group_id": noteGroup!.id,
              "text": getReadableDate(currentDate),
              "type": 170000,
              "at": item.at! - 1
            });
            _displayItemList.add(dateItem);
          }
        }
        lastDate = currentDate;
      }
    } else {
      // Adding a single new item (e.g. from input bar)
      for (var item in items) {
        final currentDate = getLocalDateFromUtcMilliSeconds(item.at!);

        if (sortOldestFirst) {
          // Add to END. Check if we need a new date pill.
          DateTime? lastDisplayDate = _displayItemList.isEmpty
              ? null
              : getLocalDateFromUtcMilliSeconds(_displayItemList.last.at!);

          if (currentDate != lastDisplayDate) {
            final dateItem = await ModelItem.fromMap({
              "group_id": noteGroup!.id,
              "text": getReadableDate(currentDate),
              "type": 170000,
              "at": item.at! - 1
            });
            _displayItemList.add(dateItem);
          }
          _displayItemList.add(item);
        } else {
          // Add to START (Index 0). Check if we need a new date pill below it.
          DateTime? firstDisplayDate = _displayItemList.isEmpty
              ? null
              : getLocalDateFromUtcMilliSeconds(_displayItemList.first.at!);

          if (currentDate != firstDisplayDate) {
            final dateItem = await ModelItem.fromMap({
              "group_id": noteGroup!.id,
              "text": getReadableDate(currentDate),
              "type": 170000,
              "at": item.at! - 1
            });
            _displayItemList.insert(0, dateItem);
          }
          _displayItemList.insert(0, item);
        }
      }
    }
  }

  void _removeItemsFromDisplayList(List<ModelItem> items) {
    setState(() {
      for (ModelItem item in items) {
        int itemIndex = _displayItemList.indexOf(item);
        if (itemIndex == -1) continue;

        // Try to clean up dangling date pills
        if (sortOldestFirst) {
          // Date pill is ABOVE item
          if (itemIndex > 0 && _displayItemList[itemIndex - 1].type == ItemType.date) {
            bool isLastInDateGroup = (itemIndex == _displayItemList.length - 1) ||
                (_displayItemList[itemIndex + 1].type == ItemType.date);
            if (isLastInDateGroup) {
              _displayItemList.removeAt(itemIndex - 1);
              itemIndex--;
            }
          }
        } else {
          // Date pill is BELOW item (in reversed list)
          if (itemIndex < _displayItemList.length - 1 &&
              _displayItemList[itemIndex + 1].type == ItemType.date) {
            bool isLastInDateGroup = (itemIndex == 0) ||
                (_displayItemList[itemIndex - 1].type == ItemType.date);
            if (isLastInDateGroup) {
              _displayItemList.removeAt(itemIndex + 1);
            }
          }
        }
        _displayItemList.removeAt(itemIndex);
      }
    });
  }

  Future<void> _initializePageData() async {
    await fetchItems(showItemId);
    await loadImageDirectoryPath();
    if (widget.sharedContents.isNotEmpty) {
      await loadSharedContents();
    }
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
    await processFiles(sharedFiles);
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

  // ── Filter dialog — icon grid with chip-style toggle ─────────────────────
  void _openFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter dialogSetState) {
            final cs = Theme.of(context).colorScheme;

            Widget filterChip(String key, IconData icon, String label) {
              final active = _filters[key]!;
              return GestureDetector(
                onTap: () {
                  dialogSetState(() => _filters[key] = !active);
                  setState(() {});
                  _applyFilters();
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

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    await _audioRecorder.cancel();
    setState(() {
      _isRecording = false;
      _recordingState = 0;
    });
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

  Future<void> checkFetchUrlMetadata(ModelItem item, {bool force = false}) async {
    if (!linkPreview) return;
    if (item.id == null) return;
    if (_fetchingItemIds.contains(item.id)) return;

    final matches = _linkRegExp.allMatches(item.text);
    final List<String> links = matches
        .map((m) => item.text.substring(m.start, m.end))
        .toSet()
        .toList(); // Unique links

    if (links.isNotEmpty) {
      _fetchingItemIds.add(item.id!);
      try {
        // Set loading state locally first for instant UI response
        item.data = {...?item.data, "url_metadata_state": "loading"};
        if (mounted) setState(() {});

        // Then update DB (this will also trigger events now)
        await item.update(["data"], pushToSync: false);

        List<Map<String, dynamic>> urlInfoList = [];
        int successCount = 0;

        // Process up to 3 links to avoid overloading
        for (int i = 0; i < links.length && i < 3; i++) {
          final String link = links[i];
          Map<String, dynamic>? metaData;
          int portrait = 1;

          // 1. Optimization: Try to find existing message with this URL metadata
          if (!force) {
            final oldItem = await ModelItem.findByUrl(link, excludeId: item.id);
            if (oldItem != null && oldItem.data != null) {
              final List<dynamic>? oldList = oldItem.data!["url_info_list"];
              final Map<String, dynamic>? oldSingle = oldItem.data!["url_info"];

              Map<String, dynamic>? foundInfo;
              int oldIndex = 0;

              if (oldList != null) {
                for (int j = 0; j < oldList.length; j++) {
                  if (oldList[j]["url"] == link) {
                    foundInfo = Map<String, dynamic>.from(oldList[j]);
                    oldIndex = j;
                    break;
                  }
                }
              } else if (oldSingle != null && oldSingle["url"] == link) {
                foundInfo = Map<String, dynamic>.from(oldSingle);
                oldIndex = 0;
              }

              if (foundInfo != null) {
                metaData = foundInfo;
                portrait = foundInfo["portrait"] ?? 1;

                // Copy the image file if it exists
                final String oldImageId =
                    oldIndex == 0 ? oldItem.id! : "${oldItem.id}-$oldIndex";
                final String newImageId = i == 0 ? item.id! : "${item.id}-$i";

                final oldFile =
                    await getFile("image", "$oldImageId-urlimage.png");
                if (oldFile != null && oldFile.existsSync()) {
                  final newPath =
                      await getFilePath("image", "$newImageId-urlimage.png");
                  await checkAndCreateDirectory(newPath);
                  await oldFile.copy(newPath);
                } else if (foundInfo["image"] != null) {
                  // If image file is missing but we have the URL, re-download it
                  final String imageId = i == 0 ? item.id! : "${item.id}-$i";
                  portrait = await checkDownloadNetworkImage(
                      imageId, foundInfo["image"]);
                }
              }
            }
          }

          // 2. If not found or forced, fetch from internet
          if (metaData == null) {
            try {
              final Metadata? fetchResult = await MetadataFetch.extract(link)
                  .timeout(const Duration(seconds: 15));
              if (fetchResult != null) {
                metaData = {
                  "url": link,
                  "title": fetchResult.title,
                  "desc": fetchResult.description,
                  "image": fetchResult.image,
                };

                if (fetchResult.image != null) {
                  final String imageId = i == 0 ? item.id! : "${item.id}-$i";
                  portrait = await checkDownloadNetworkImage(
                      imageId, fetchResult.image!);
                }
              }
            } catch (e) {
              logger.error("error fetching metadata for $link", error: e);
            }
          }

          if (metaData != null) {
            urlInfoList.add({
              ...metaData,
              "portrait": portrait,
            });
            successCount++;
          }
        }

        if (successCount > 0) {
          item.data = {
            ...?item.data,
            "url_info_list": urlInfoList,
            "url_metadata_state": null // Success
          };
          item.data!["url_info"] = urlInfoList.first;
        } else {
          item.data = {...?item.data, "url_metadata_state": "error"};
        }

        await item.update(["data"]);
        if (mounted) setState(() {});
      } catch (e) {
        logger.error("error in checkFetchUrlMetadata", error: e);
        item.data = {...?item.data, "url_metadata_state": "error"};
        await item.update(["data"]);
        if (mounted) setState(() {});
      } finally {
        _fetchingItemIds.remove(item.id);
      }
    } else {
      // No links, clear existing info
      Map<String, dynamic>? data = item.data;
      if (data != null &&
          (data.containsKey("url_info") || data.containsKey("url_info_list"))) {
        data.remove("url_info");
        data.remove("url_info_list");
        data.remove("url_metadata_state");
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

  // ── Reply thread overlay ──────────────────────────────────────────────────
  void _showReplyThreadOverlay(BuildContext context, ModelItem item) {
    // Build the chain: walk back through replyOn references
    final List<ModelItem> chain = [];
    ModelItem? cursor = item;
    while (cursor != null) {
      chain.insert(0, cursor);
      cursor = cursor.replyOn;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Reply thread',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, animation, _, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, _) {
        final cs = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Material(
              color: Colors.transparent,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text(
                            'Thread',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: cs.onSurface.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                LucideIcons.x,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Thread bubbles
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: chain.length,
                        itemBuilder: (context, index) {
                          final chainItem = chain[index];
                          final isLast = index == chain.length - 1;
                          return _ThreadBubble(
                            item: chainItem,
                            isLast: isLast,
                            onTap: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              Navigator.of(context).pop();
                              fetchItems(chainItem.id);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ), // SafeArea
            ), // Material
          ),
        );
      },
    );
  }

  Future<void> showHideScrollToBottomButton(ScrollMetrics metrics) async {
    bool requiresUpdate = false;
    final double scrolledHeight = metrics.pixels;
    final bool isAtBottom = sortOldestFirst
        ? metrics.maxScrollExtent - scrolledHeight <= 100
        : scrolledHeight <= 100;

    if (!isAtBottom && !canScrollToBottom) {
      canScrollToBottom = true;
      requiresUpdate = true;
    } else if (isAtBottom && canScrollToBottom) {
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
        _initializePageData();
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
                      showHideScrollToBottomButton(scrollInfo.metrics);
                      return false;
                    },
                    child: ScrollablePositionedList.builder(
                      itemScrollController: _itemScrollController,
                      itemPositionsListener: _itemPositionsListener,
                      physics: privacyShield
                          ? const ClampingScrollPhysics()
                          : const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics()),
                      reverse: !sortOldestFirst,
                      itemCount: _displayItemList.length,
                      itemBuilder: (context, index) {
                        if (index < 0 || index >= _displayItemList.length) {
                          return const SizedBox.shrink();
                        }
                        final ModelItem item = _displayItemList[index];

                        if (mediaGallery && _isMediaItem(item)) {
                          final (start, _) = _findMediaRunForIndex(index);
                          if ((index - start) % 2 != 0) {
                            return const SizedBox.shrink();
                          }
                        }

                        bool showTimePill = false;
                        int lastIndexInGroup = index;
                        if (mediaGallery && _isMediaItem(item)) {
                          final (_, runEnd) = _findMediaRunForIndex(index);
                          lastIndexInGroup = math.min(index + 1, runEnd);
                        }

                        if (lastIndexInGroup == _displayItemList.length - 1) {
                          showTimePill = true;
                        } else {
                          final olderItem = _displayItemList[lastIndexInGroup + 1];
                          if (olderItem.type == ItemType.date) {
                            showTimePill = true;
                          } else {
                            final diff = DateTime.fromMillisecondsSinceEpoch(
                                    _displayItemList[lastIndexInGroup].at!,
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

                        // Dynamic radius: short text → pill (22), long → flat (10).
                        final double bubbleRadius = () {
                          if (isAttachment) return 14.0;
                          final int len = item.text.length;
                          if (len <= 20) return 22.0;
                          if (len >= 120) return 10.0;
                          return 22.0 - (len - 20) / (120 - 20) * 12.0;
                        }();

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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    // ── Reply quote bubble ──────────────────
                                    if (item.replyOn != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            left: 12, right: 12, top: 2),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: PrivacyShield(
                                            isEnabled: privacyShield,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: ReplyQuoteBubble(
                                              replyOn: item.replyOn!,
                                              showBorder: showNoteBorder,
                                              onTap: () =>
                                                  _showReplyThreadOverlay(
                                                      context, item),
                                            ),
                                          ),
                                        ),
                                      ),
                                    // ── Main bubble ────────────────────────
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Container(
                                        margin: EdgeInsets.only(
                                          top: item.replyOn != null ? 0 : 2,
                                          bottom: 2,
                                          right: 12,
                                          left: 12,
                                        ),
                                        child: PrivacyShield(
                                          isEnabled: privacyShield,
                                          borderRadius: BorderRadius.circular(
                                              bubbleRadius),
                                          child: Material(
                                            color: Colors.transparent,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      bubbleRadius),
                                              side: (!isAttachment &&
                                                      showNoteBorder)
                                                  ? BorderSide(
                                                      color: cs.onSurface
                                                          .withValues(
                                                              alpha: 0.1),
                                                      width: 0.5,
                                                    )
                                                  : BorderSide.none,
                                            ),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        bubbleRadius),
                                                color: isAttachment
                                                    ? Colors.transparent
                                                    : cs.onSurface.withValues(
                                                        alpha: 0.07),
                                              ),
                                              child: Container(
                                                margin: EdgeInsets.symmetric(
                                                    vertical:
                                                        isAttachment ? 2 : 8,
                                                    horizontal:
                                                        isAttachment ? 0 : 8),
                                                padding: EdgeInsets.symmetric(
                                                  vertical:
                                                      isAttachment ? 0 : 2,
                                                  horizontal:
                                                      isAttachment ? 0 : 6,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    _buildNoteItem(item,
                                                        index: index),
                                                    if (linkPreview &&
                                                        (urlInfo != null ||
                                                            (item.data != null &&
                                                                (item.data!.containsKey(
                                                                        "url_info_list") ||
                                                                    item.data!.containsKey(
                                                                        "url_metadata_state"))) ||
                                                            _linkRegExp
                                                                .hasMatch(
                                                                    item.text)))
                                                      GestureDetector(
                                                        onTap: () async {
                                                          if (_hasNotesSelected) {
                                                            onItemTapped(item);
                                                          } else if (urlInfo !=
                                                              null) {
                                                            final linkUri =
                                                                Uri.parse(
                                                                    urlInfo[
                                                                        "url"]);
                                                            if (await canLaunchUrl(
                                                                linkUri)) {
                                                              await launchUrl(
                                                                  linkUri);
                                                            }
                                                          }
                                                        },
                                                        child: NoteUrlPreview(
                                                          urlInfo: urlInfo,
                                                          urlInfoList:
                                                              item.data?[
                                                                  "url_info_list"],
                                                          urlMetadataState:
                                                              item.data?[
                                                                      "url_metadata_state"] ??
                                                                  (urlInfo ==
                                                                              null &&
                                                                          item.data?[
                                                                                  "url_info_list"] ==
                                                                              null &&
                                                                          _linkRegExp.hasMatch(
                                                                              item.text)
                                                                      ? "none"
                                                                      : null),
                                                          imageDirectory:
                                                              imageDirPath,
                                                          itemId: item.id!,
                                                          onRetry: () =>
                                                              checkFetchUrlMetadata(
                                                                  item,
                                                                  force: true),
                                                        ),
                                                      ),
                                                  ],
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
                          if (sortOldestFirst && _displayItemList.isNotEmpty) {
                            _itemScrollController.jumpTo(
                                index: _displayItemList.length - 1);
                          } else {
                            fetchItems(null);
                          }
                        },
                        shape: const CircleBorder(),
                        backgroundColor: cs.onSurface,
                        foregroundColor: cs.surface,
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

  /// Returns true if the item is an image or video type.
  bool _isMediaItem(ModelItem item) {
    return item.type == ItemType.image || item.type == ItemType.video;
  }

  /// Finds the consecutive run of image/video items around [index].
  /// Returns (startIndex, endIndex) inclusive in the _displayItemList.
  /// The list is ordered DESC (newest first at index 0) when reverse=true.
  (int, int) _findMediaRunForIndex(int index) {
    int start = index;
    int end = index;
    // Expand upward (toward index 0 = newer items in DESC order)
    while (start > 0 && _isMediaItem(_displayItemList[start - 1])) {
      start--;
    }
    // Expand downward (toward older items)
    while (end < _displayItemList.length - 1 &&
        _isMediaItem(_displayItemList[end + 1])) {
      end++;
    }
    return (start, end);
  }

  Widget _buildNoteItem(ModelItem item, {int? index}) {
    // ── Media gallery grouping ───────────────────────────────────────────
    if (mediaGallery && index != null && _isMediaItem(item)) {
      final (runStart, runEnd) = _findMediaRunForIndex(index);
      final int relativeIndex = index - runStart;

      // Group into rows of 2. Only the first item in each row renders the row.
      if (relativeIndex % 2 != 0) {
        return const SizedBox.shrink();
      }

      // Items in this row: index and potentially index + 1
      final List<ModelItem> rowItems = [];
      rowItems.add(_displayItemList[index]);
      if (index + 1 <= runEnd) {
        rowItems.add(_displayItemList[index + 1]);
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: WrapAlignment.end,
          children: rowItems.map((mediaItem) {
            // Calculate width to fit 2 columns in the message bubble space
            // Subtracting bubble margins and internal padding
            final double cellWidth =
                (MediaQuery.of(context).size.width - 60) / 2;
            return _buildGalleryCell(mediaItem, cellWidth);
          }).toList(),
        ),
      );
    }

    // ── Normal single-item rendering ─────────────────────────────────────
    switch (item.type) {
      case ItemType.text:
        return ItemWidgetText(item: item);
      case ItemType.image:
        return ItemWidgetImage(
            item: item, onTap: viewImageVideo, showBorder: showNoteBorder);
      case ItemType.video:
        return ItemWidgetVideo(
            item: item, onTap: viewImageVideo, showBorder: showNoteBorder);
      case ItemType.audio:
        return ItemWidgetAudio(item: item, showBorder: showNoteBorder);
      case ItemType.document:
        return ItemWidgetDocument(
            item: item, onTap: openDocument, showBorder: showNoteBorder);
      case ItemType.location:
        return ItemWidgetLocation(
            item: item, onTap: openLocation, showBorder: showNoteBorder);
      case ItemType.contact:
        return ItemWidgetContact(
            item: item, onTap: addToContacts, showBorder: showNoteBorder);
      case ItemType.completedTask:
      case ItemType.task:
        return ItemWidgetTask(item: item);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildGalleryCell(ModelItem mediaItem, double width) {
    final bool isVideo = mediaItem.type == ItemType.video;
    final bool isDownloadable =
        mediaItem.state == SyncState.downloadable.value;
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: width,
      height: width,
      child: GestureDetector(
        onLongPress: () => onItemLongPressed(mediaItem),
        onTap: () {
          if (_hasNotesSelected) {
            onItemTapped(mediaItem);
          } else {
            viewImageVideo(mediaItem);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: _selectedItems.contains(mediaItem)
                ? cs.onSurface.withValues(alpha: 0.1)
                : Colors.transparent,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (mediaItem.thumbnail != null)
                  Image.memory(
                    mediaItem.thumbnail!,
                    fit: BoxFit.cover,
                    height: width,
                    width: width,
                  )
                else
                  Container(
                    height: width,
                    width: width,
                    color: cs.onSurface.withValues(alpha: 0.05),
                    child: Icon(
                      isVideo ? LucideIcons.video : LucideIcons.image,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                  ),
                // Overlay for video or downloadable state
                if (isVideo || isDownloadable)
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isDownloadable
                          ? LucideIcons.arrowDown
                          : LucideIcons.play,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                // Corner video icon always present if it's a video
                if (isVideo)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        LucideIcons.video,
                        color: Colors.white,
                        size: 10,
                      ),
                    ),
                  ),
                // Selection overlay
                if (_selectedItems.contains(mediaItem))
                  Container(
                    color: cs.primary.withValues(alpha: 0.2),
                    child: const Center(
                      child: Icon(Icons.check_circle, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
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
    final cs = Theme.of(context).colorScheme;
    final controller = IOS7SiriWaveformController(
      amplitude: 0.5,
      color: cs.primary,
      frequency: 4,
      speed: 0.10,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _cancelRecording,
            icon: Icon(LucideIcons.trash2,
                size: 20, color: cs.error.withValues(alpha: 0.7)),
            tooltip: "Cancel",
          ),
          const SizedBox(width: 4),
          TimerWidget(runningState: _recordingState),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 40,
              child: _recordingState == 1
                  ? SiriWaveform.ios7(
                      controller: controller,
                      options: const IOS7SiriWaveformOptions(height: 40),
                    )
                  : Center(
                      child: Container(
                        height: 2,
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        color: cs.onSurface.withValues(alpha: 0.1),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _pauseResumeRecording,
            icon: Icon(
              _recordingState == 1 ? Icons.pause : Icons.play_arrow,
              color: cs.primary,
            ),
            tooltip: _recordingState == 1 ? "Pause" : "Resume",
          ),
          IconButton(
            onPressed: _stopRecording,
            icon: Icon(LucideIcons.send, color: cs.primary),
            tooltip: "Send",
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
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        border: Border(
          top: BorderSide(
              color: cs.onSurface.withValues(alpha: 0.08), width: 0.5),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
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
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          top: BorderSide(
              color: cs.onSurface.withValues(alpha: 0.08), width: 0.5),
        ),
      ),
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
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: cs.onSurface.withValues(alpha: 0.1),
                                width: 0.75,
                              ),
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                children: [
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8, horizontal: 4),
                                      child: NotePreviewSummary(
                                        item: replyOnItem!,
                                        showImagePreview: true,
                                        expanded: true,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: "Cancel reply",
                                    icon: const Icon(LucideIcons.x, size: 16),
                                    color: cs.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                    onPressed: cancelReplyItem,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        TextField(
                          controller: _textController,
                          focusNode: _textControllerFocus,
                          maxLines: 10,
                          minLines: 1,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          textAlignVertical: TextAlignVertical.center,
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
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            suffixIcon: GestureDetector(
                              onLongPress: () async {
                                if (!_isTyping) {
                                  _recordtooltipKey.currentState
                                      ?.ensureTooltipVisible();
                                  await Future.delayed(
                                      const Duration(seconds: 1), () {
                                    if (mounted) Tooltip.dismissAllToolTips();
                                  });
                                }
                                if (!_isTyping && !_isRecording) {
                                  await _startRecording();
                                }
                              },
                              onTap: () async {
                                if (_isRecording) {
                                  await _stopRecording();
                                } else if (_isTyping) {
                                  _handleTextInput(_textController.text);
                                } else {
                                  if (mounted) {
                                    displaySnackBar(context,
                                        message: 'Hold to start recording.',
                                        seconds: 1);
                                  }
                                }
                              },
                              child: Tooltip(
                                message:
                                    _isTyping ? "Add note" : "Record audio",
                                key: _recordtooltipKey,
                                triggerMode: TooltipTriggerMode.manual,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    transitionBuilder: (child, animation) =>
                                        ScaleTransition(
                                            scale: animation, child: child),
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
                                      color: cs.onSurfaceVariant
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          onChanged: _onInputTextChanged,
                          scrollController: ScrollController(),
                        ),
                      ],
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
                GridView.count(
                  crossAxisCount: 5,
                  shrinkWrap: true,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.9,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
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
                    _attachmentGridItem(context, LucideIcons.mapPin, "Location",
                        () {
                      Navigator.pop(context);
                      _addMedia('location');
                    }),
                    if (Platform.isAndroid || Platform.isIOS)
                      _attachmentGridItem(
                          context, LucideIcons.contact, "Contact", () {
                        Navigator.pop(context);
                        _addMedia('contact');
                      }),
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

// ── Thread connector painter ──────────────────────────────────────────────────
class _ThreadConnectorPainter extends CustomPainter {
  final bool alignLeft;
  final Color color;

  const _ThreadConnectorPainter({required this.alignLeft, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Straight vertical connector centred under whichever side the bubble is on
    const double xOffset = 20.0;
    final double x = alignLeft ? xOffset : size.width - xOffset;

    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(_ThreadConnectorPainter old) =>
      old.alignLeft != alignLeft || old.color != color;
}

class _ThreadBubble extends StatelessWidget {
  final ModelItem item;
  final bool isLast;
  final VoidCallback onTap;

  const _ThreadBubble({
    required this.item,
    required this.isLast,
    required this.onTap,
  });

  bool get _thumbnailOnly =>
      item.thumbnail != null &&
      (item.type == ItemType.image ||
          item.type == ItemType.video ||
          item.type == ItemType.contact);

  String get _label {
    switch (item.type) {
      case ItemType.text:
      case ItemType.task:
      case ItemType.completedTask:
        return item.text;
      case ItemType.audio:
        return '🎵 ${item.data?["name"] ?? "Audio"}';
      case ItemType.document:
        return '📄 ${item.data?["title"] ?? item.data?["name"] ?? "Document"}';
      case ItemType.location:
        return '📍 Location';
      default:
        return '';
    }
  }

  double get _radius {
    final isText = item.type == ItemType.text ||
        item.type == ItemType.task ||
        item.type == ItemType.completedTask;
    if (!isText) return 14.0;
    final len = item.text.length;
    if (len <= 20) return 20.0;
    if (len >= 120) return 10.0;
    return 20.0 - (len - 20) / (120 - 20) * 10.0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final alignLeft = !isLast;
    final double r = _radius;

    Widget bubble;
    if (_thumbnailOnly) {
      bubble = ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Image.memory(
          item.thumbnail!,
          width: 120,
          height: 120,
          fit: BoxFit.cover,
        ),
      );
    } else {
      bubble = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: alignLeft
              ? cs.onSurface.withValues(alpha: 0.05)
              : cs.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(r),
          border: Border.all(
            color: cs.onSurface.withValues(alpha: alignLeft ? 0.1 : 0.12),
            width: 0.75,
          ),
        ),
        child: Text(
          _label,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: cs.onSurface.withValues(alpha: 0.85),
            decoration: TextDecoration.none,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment:
          alignLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            margin: EdgeInsets.only(
              left: alignLeft ? 0 : 40,
              right: alignLeft ? 40 : 0,
            ),
            child: bubble,
          ),
        ),
        if (!isLast)
          SizedBox(
            height: 20,
            child: CustomPaint(
              painter: _ThreadConnectorPainter(
                alignLeft: alignLeft,
                color: cs.onSurface.withValues(alpha: 0.25),
              ),
            ),
          ),
      ],
    );
  }
}
