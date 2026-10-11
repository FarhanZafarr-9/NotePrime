import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
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

  // ── Monochromatic icon badge ──────────────────────────────────────────────
  Widget _buildIconBadge(IconData icon) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

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
  bool showDate = true;
  bool showTime = true;
  bool showNoteBorder = false;
  bool linkPreview = true;
  bool sortOldestFirst = false;
  // List runs top→bottom oldest→newest when "newest first" is selected.
  bool get _listAsc => !sortOldestFirst;
  // The list is reversed (bottom-anchored), so controller indices are flipped.
  int _toListIndex(int dataIndex) => _displayItemList.length - 1 - dataIndex;
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
    final bool oldSort = sortOldestFirst;

    if (mounted) {
      setState(() {
        if (useGroupSettings && data != null) {
          if (data.containsKey("show_date")) {
            showDate = data["show_date"] == 1;
          }
          if (data.containsKey("show_time")) {
            showTime = data["show_time"] == 1;
          }
          // Compatibility
          if (data.containsKey("date_time")) {
            bool val = data["date_time"] == 1;
            showDate = val;
            showTime = val;
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
          showDate = ModelSetting.get("global_show_date", "yes") == "yes";
          showTime = ModelSetting.get("global_show_time", "yes") == "yes";
          showNoteBorder =
              ModelSetting.get("global_show_note_border", "yes") == "yes";
          linkPreview = ModelSetting.get("global_link_preview", "yes") == "yes";
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
    if (mounted && oldSort != sortOldestFirst && _displayItemList.isNotEmpty) {
      await fetchItems(null);
    }
  }

  Future<void> fetchItems(String? itemId) async {
    List<ModelItem> newItems =
        await ModelItem.getInGroup(noteGroup!.id!, _filters, sortAsc: _listAsc);
    canScrollToBottom = itemId != null;
    _displayItemList.clear();
    await _addItemsToDisplayList(newItems, true);
    if (mounted) {
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
                  _itemScrollController.jumpTo(
                      index: _toListIndex(indexOfItem));
                  triggerItemBlink();
                }
              });
            });
          }
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _displayItemList.isNotEmpty) {
              _itemScrollController.jumpTo(
                  index: _listAsc ? 0 : _displayItemList.length - 1);
            }
          });
        }
      });
    }
    if (newItems.isEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _textControllerFocus.requestFocus());
    }
  }

  Future<void> loadImageDirectoryPath() async {
    String filePath = await getFilePath("image", "dummy.png");
    if (mounted) setState(() => imageDirPath = path.dirname(filePath));
  }

  Future<ModelItem> _makeDatePill(ModelItem item) => ModelItem.fromMap({
        "group_id": noteGroup!.id,
        "text": getReadableDate(getLocalDateFromUtcMilliSeconds(item.at!)),
        "type": 170000,
        "at": _listAsc ? item.at! - 1 : item.at! + 1,
      });

  Future<void> _addItemsToDisplayList(
      List<ModelItem> items, bool addOlder) async {
    if (items.isEmpty) return;

    if (addOlder) {
      DateTime? lastDate;
      for (final item in items) {
        final currentDate = getLocalDateFromUtcMilliSeconds(item.at!);
        if (currentDate != lastDate) {
          _displayItemList.add(await _makeDatePill(item));
        }
        _displayItemList.add(item);
        lastDate = currentDate;
      }
    } else {
      for (final item in items) {
        final currentDate = getLocalDateFromUtcMilliSeconds(item.at!);
        if (_listAsc) {
          final DateTime? lastDisplayDate = _displayItemList.isEmpty
              ? null
              : getLocalDateFromUtcMilliSeconds(_displayItemList.last.at!);
          if (currentDate != lastDisplayDate) {
            _displayItemList.add(await _makeDatePill(item));
          }
          _displayItemList.add(item);
        } else {
          final ModelItem? firstReal =
              _displayItemList.length > 1 ? _displayItemList[1] : null;
          final DateTime? firstDate = firstReal == null
              ? null
              : getLocalDateFromUtcMilliSeconds(firstReal.at!);
          if (currentDate != firstDate) {
            _displayItemList.insert(0, item);
            _displayItemList.insert(0, await _makeDatePill(item));
          } else {
            _displayItemList.insert(1, item);
          }
        }
      }
    }
  }

  void _removeItemsFromDisplayList(List<ModelItem> items) {
    setState(() {
      for (final item in items) {
        int itemIndex = _displayItemList.indexOf(item);
        if (itemIndex == -1) continue;
        if (itemIndex > 0 &&
            _displayItemList[itemIndex - 1].type == ItemType.date) {
          final bool isLastInDateGroup =
              itemIndex == _displayItemList.length - 1 ||
                  _displayItemList[itemIndex + 1].type == ItemType.date;
          if (isLastInDateGroup) {
            _displayItemList.removeAt(itemIndex - 1);
            itemIndex--;
          }
        }
        _displayItemList.removeAt(itemIndex);
      }
    });
  }

  Future<void> _initializePageData() async {
    showProcessing();
    await fetchItems(showItemId);
    await loadImageDirectoryPath();
    if (widget.sharedContents.isNotEmpty) {
      await loadSharedContents();
    }
    hideProcessing();
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
    if (medias.isNotEmpty) {
      Share.shareXFiles(medias, text: texts.join("\n"));
    } else if (texts.isNotEmpty) {
      Share.share(texts.join("\n"));
    }
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

  Future<void> _onPaste() async {
    ClipboardData? data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null) {
      String text = data.text!;
      int start = _textController.selection.start;
      int end = _textController.selection.end;
      String currentText = _textController.text;

      if (start >= 0 && end >= 0) {
        _textController.text = currentText.replaceRange(start, end, text);
        _textController.selection = TextSelection.fromPosition(
            TextPosition(offset: start + text.length));
      } else {
        _textController.text = currentText + text;
      }
      _onInputTextChanged(_textController.text);
    }
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

  Widget _bottomSheetTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? subtitle,
    Color? color,
    BorderRadius? borderRadius,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tileColor = color ?? cs.onSurfaceVariant;
    final radius = borderRadius ?? BorderRadius.circular(12);
    return Material(
      color: cs.onSurface.withValues(alpha: 0.06),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tileColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: tileColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: TextStyle(fontSize: 15, color: cs.onSurface)),
                    if (subtitle != null)
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  cs.onSurfaceVariant.withValues(alpha: 0.6))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void addToContacts(ModelItem item) {
    if (_hasNotesSelected) {
      onItemTapped(item);
      return;
    }

    final cs = Theme.of(context).colorScheme;
    final Map<String, dynamic> contactData = item.data ?? {};
    final String name = contactData["name"] ?? "Contact";
    final List phones = contactData["phones"] ?? [];
    final List emails = contactData["emails"] ?? [];

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final tiles = <({
          IconData icon,
          String label,
          String? subtitle,
          Color? color,
          VoidCallback onTap
        })>[
          if (phones.isNotEmpty)
            (
              icon: LucideIcons.phone,
              label: "Call",
              subtitle: phones.first.toString(),
              color: cs.primary,
              onTap: () {
                Navigator.pop(context);
                launchUrl(Uri.parse("tel:${phones.first}"));
              },
            ),
          if (phones.isNotEmpty)
            (
              icon: LucideIcons.messageSquare,
              label: "Send SMS",
              subtitle: null,
              color: cs.secondary,
              onTap: () {
                Navigator.pop(context);
                launchUrl(Uri.parse("sms:${phones.first}"));
              },
            ),
          if (emails.isNotEmpty)
            (
              icon: LucideIcons.mail,
              label: "Email",
              subtitle: emails.first.toString(),
              color: cs.tertiary,
              onTap: () {
                Navigator.pop(context);
                launchUrl(Uri.parse("mailto:${emails.first}"));
              },
            ),
          (
            icon: LucideIcons.userPlus,
            label: "Add to System Contacts",
            subtitle: null,
            color: null,
            onTap: () async {
              Navigator.pop(context);
              try {
                if (!await fc.FlutterContacts.requestPermission()) {
                  if (!context.mounted) return;
                  displaySnackBar(context,
                      message: "Contacts permission denied", seconds: 2);
                  return;
                }
                final newContact = fc.Contact();
                newContact.name.first = contactData["first"] ?? "";
                newContact.name.last = contactData["last"] ?? "";
                newContact.phones =
                    phones.map((p) => fc.Phone(p.toString())).toList();
                newContact.emails =
                    emails.map((e) => fc.Email(e.toString())).toList();
                await newContact.insert();
                if (!context.mounted) return;
                displaySnackBar(context,
                    message: "Added to contacts", seconds: 1);
              } catch (e) {
                if (!context.mounted) return;
                displaySnackBar(context,
                    message: "Failed to add contact", seconds: 2);
              }
            },
          ),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                for (int i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(height: 3),
                  _bottomSheetTile(
                    context: context,
                    icon: tiles[i].icon,
                    label: tiles[i].label,
                    subtitle: tiles[i].subtitle,
                    color: tiles[i].color,
                    borderRadius: listRowRadius(i, tiles.length),
                    onTap: tiles[i].onTap,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
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

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_itemScrollController.isAttached ||
          _displayItemList.isEmpty) {
        return;
      }
      _itemScrollController.jumpTo(
          index: _listAsc ? 0 : _displayItemList.length - 1);
    });
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
    _scrollToLatest();
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

  Future<void> checkFetchUrlMetadata(ModelItem item,
      {bool force = false}) async {
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
          fc.Contact contact = value as fc.Contact;
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
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: PopupMenuButton<int>(
          icon: _buildIconBadge(LucideIcons.moreVertical),
          padding: EdgeInsets.zero,
          onSelected: (value) {
            if (value == 0) navigateToPageGroupEdit();
            if (value == 1) _openFilterDialog();
          },
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.1),
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
    final bool isAtBottom = _listAsc
        ? scrolledHeight <= 100
        : metrics.maxScrollExtent - scrolledHeight <= 100;

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
        title: Row(
          children: [
            if (noteGroup != null) ...[
              WidgetCategoryGroupAvatar(
                type: "group",
                size: 32,
                color: noteGroup!.color,
                title: noteGroup!.title,
                thumbnail: noteGroup!.thumbnail,
                icon: noteGroup!.icon,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                noteGroup == null ? "" : noteGroup!.title,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),
          ],
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
                      reverse: true,
                      itemScrollController: _itemScrollController,
                      itemPositionsListener: _itemPositionsListener,
                      physics: privacyShield
                          ? const ClampingScrollPhysics()
                          : const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics()),
                      itemCount: _displayItemList.length,
                      itemBuilder: (context, listIndex) {
                        final int index =
                            _displayItemList.length - 1 - listIndex;
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

                        // A time pill marks the START of a group: show it only
                        // when this item begins a fresh group in display order
                        // (nothing above it, a date above it, or a >10 minute
                        // gap from the item above). Keying off the item ABOVE
                        // keeps pills aligned with the bubble seam corners,
                        // instead of landing between connected bubbles.
                        final bool showTimePill = item.type != ItemType.date
                            ? (index == 0 ||
                                _displayItemList[index - 1].type ==
                                    ItemType.date ||
                                !_withinGroupWindow(index - 1, index))
                            : false;

                        final bool isAttachment = item.type == ItemType.image ||
                            item.type == ItemType.video ||
                            item.type == ItemType.audio ||
                            item.type == ItemType.document ||
                            item.type == ItemType.location ||
                            item.type == ItemType.contact;

                        // Dynamic radius: short text → pill (22), long → flat (10).
                        final double bubbleRadius = _bubbleRadius(item);

                        // Connected text bubbles: a message flattens the corner
                        // it shares with a neighbour within the 10-minute
                        // grouping window. Of two joined neighbours the OLDER
                        // message always takes the bottom-right seam and the
                        // NEWER one the top-right seam (display-sort agnostic).
                        final bool isTextItem = item.type == ItemType.text;
                        final bool galleryRow =
                            mediaGallery && _isMediaItem(item);
                        final bool seamable = _canSeam(item);
                        final bool connAbove =
                            seamable && _textConnectsAbove(index);
                        final bool connBelow =
                            seamable && _textConnectsBelow(index);
                        final BorderRadius bubbleBorder = seamable
                            ? BorderRadius.only(
                                topLeft: Radius.circular(bubbleRadius),
                                topRight: Radius.circular(
                                    connAbove ? 5 : bubbleRadius),
                                bottomLeft: Radius.circular(bubbleRadius),
                                bottomRight: Radius.circular(
                                    connBelow ? 5 : bubbleRadius),
                              )
                            : BorderRadius.circular(bubbleRadius);

                        Widget mainItem;
                        if (item.type == ItemType.date) {
                          mainItem = showDate
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
                                          top: item.replyOn != null
                                              ? 0
                                              : (connAbove
                                                  ? 2
                                                  : (isTextItem ? 6 : 2)),
                                          bottom: connBelow ? 0 : 2,
                                          right: 12,
                                          left: 12,
                                        ),
                                        child: PrivacyShield(
                                          isEnabled: privacyShield,
                                          onLongPress: () =>
                                              onItemLongPressed(item),
                                          borderRadius: bubbleBorder,
                                          child: Material(
                                            color: Colors.transparent,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: bubbleBorder,
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
                                                borderRadius: bubbleBorder,
                                                color: isAttachment
                                                    ? Colors.transparent
                                                    : cs.onSurface.withValues(
                                                        alpha: 0.07),
                                              ),
                                              child: Container(
                                                margin: EdgeInsets.only(
                                                    top: !isAttachment
                                                        ? 8
                                                        : (galleryRow ||
                                                                connAbove
                                                            ? 0
                                                            : 2),
                                                    bottom: !isAttachment
                                                        ? 8
                                                        : (galleryRow ||
                                                                connBelow
                                                            ? 0
                                                            : 2),
                                                    left: isAttachment ? 0 : 8,
                                                    right:
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
                                                        index: index,
                                                        borderRadius:
                                                            isAttachment &&
                                                                    seamable
                                                                ? bubbleBorder
                                                                : null),
                                                    if (_hasLinkPreview(item))
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
                                                        child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            const SizedBox(
                                                                height: 8),
                                                            NoteUrlPreview(
                                                              urlInfo: urlInfo,
                                                              urlInfoList: item
                                                                      .data?[
                                                                  "url_info_list"],
                                                              urlMetadataState: item
                                                                          .data?[
                                                                      "url_metadata_state"] ??
                                                                  (urlInfo == null &&
                                                                          item.data?["url_info_list"] ==
                                                                              null &&
                                                                          _linkRegExp
                                                                              .hasMatch(item.text)
                                                                      ? "none"
                                                                      : null),
                                                              imageDirectory:
                                                                  imageDirPath,
                                                              itemId: item.id!,
                                                              onRetry: () =>
                                                                  checkFetchUrlMetadata(
                                                                      item,
                                                                      force:
                                                                          true),
                                                            ),
                                                          ],
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
                            showTime &&
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
                          if (_listAsc && _displayItemList.isNotEmpty) {
                            _itemScrollController.jumpTo(index: 0);
                          } else {
                            fetchItems(null);
                          }
                        },
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        backgroundColor: cs.onSurface,
                        foregroundColor: cs.surface,
                        child: Icon(_listAsc
                            ? LucideIcons.chevronsDown
                            : LucideIcons.chevronsUp),
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
  (int, int) _findMediaRunForIndex(int index) {
    int start = index;
    int end = index;
    // Expand upward (toward index 0 = newer items in DESC order)
    while (start > 0 &&
        _isMediaItem(_displayItemList[start - 1]) &&
        _withinGroupWindow(start - 1, start)) {
      start--;
    }
    // Expand downward (toward older items)
    while (end < _displayItemList.length - 1 &&
        _isMediaItem(_displayItemList[end + 1]) &&
        _withinGroupWindow(end, end + 1)) {
      end++;
    }
    return (start, end);
  }

  // ── Bubble grouping helpers ─────────────────────────────────────────────
  /// Grouping window in minutes: adjacent messages closer than this are drawn
  /// as one connected group.
  static const int bubbleGroupWindowMinutes = 10;

  /// True when the two adjacent items at [a] and [b] fall inside the grouping
  /// window.
  bool _withinGroupWindow(int a, int b) {
    final int? ta = _displayItemList[a].at;
    final int? tb = _displayItemList[b].at;
    if (ta == null || tb == null) return false;
    final diff = DateTime.fromMillisecondsSinceEpoch(ta, isUtc: true)
        .difference(DateTime.fromMillisecondsSinceEpoch(tb, isUtc: true));
    return diff.abs().inMinutes <= bubbleGroupWindowMinutes;
  }

  /// True when the text bubble at [index] visually connects to the text bubble
  /// directly above it: the item above is a text bubble and lies within the
  /// grouping window.
  bool _textConnectsAbove(int index) {
    if (index <= 0) return false;
    if (!_sameSeamFamily(
        _displayItemList[index], _displayItemList[index - 1])) {
      return false;
    }
    return _withinGroupWindow(index - 1, index);
  }

  /// True when the bubble at [index] visually connects to the bubble directly
  /// below it (same seam family, inside the grouping window).
  bool _textConnectsBelow(int index) {
    if (index >= _displayItemList.length - 1) return false;
    if (!_sameSeamFamily(
        _displayItemList[index], _displayItemList[index + 1])) {
      return false;
    }
    return _withinGroupWindow(index, index + 1);
  }

  bool _isAttachmentItem(ModelItem item) =>
      item.type == ItemType.image ||
      item.type == ItemType.video ||
      item.type == ItemType.audio ||
      item.type == ItemType.document ||
      item.type == ItemType.location ||
      item.type == ItemType.contact;

  /// Gallery tiles are a grid with their own gutters, so they never seam.
  bool _canSeam(ModelItem item) =>
      item.type == ItemType.text ||
      (_isAttachmentItem(item) && !(mediaGallery && _isMediaItem(item)));

  /// Text seams with text, attachments with attachments; never across families.
  bool _sameSeamFamily(ModelItem a, ModelItem b) =>
      _canSeam(a) &&
      _canSeam(b) &&
      (a.type == ItemType.text) == (b.type == ItemType.text);

  bool _hasLinkPreview(ModelItem item) {
    if (!linkPreview) return false;
    final d = item.data;
    return (d != null &&
            (d["url_info"] != null ||
                d.containsKey("url_info_list") ||
                d.containsKey("url_metadata_state"))) ||
        _linkRegExp.hasMatch(item.text);
  }

  double _bubbleRadius(ModelItem item) {
    if (_isAttachmentItem(item) || _hasLinkPreview(item)) return 14.0;
    final int len = item.text.length;
    if (len <= 20) return 22.0;
    if (len >= 120) return 10.0;
    return 22.0 - (len - 20) / (120 - 20) * 12.0;
  }

  Widget _buildNoteItem(ModelItem item,
      {int? index, BorderRadius? borderRadius}) {
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
        padding: EdgeInsets.zero,
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
            item: item,
            onTap: viewImageVideo,
            showBorder: showNoteBorder,
            borderRadius: borderRadius);
      case ItemType.video:
        return ItemWidgetVideo(
            item: item,
            onTap: viewImageVideo,
            showBorder: showNoteBorder,
            borderRadius: borderRadius);
      case ItemType.audio:
        return ItemWidgetAudio(
            item: item, showBorder: showNoteBorder, borderRadius: borderRadius);
      case ItemType.document:
        return ItemWidgetDocument(
            item: item,
            onTap: openDocument,
            showBorder: showNoteBorder,
            borderRadius: borderRadius);
      case ItemType.location:
        return ItemWidgetLocation(
            item: item,
            onTap: openLocation,
            showBorder: showNoteBorder,
            borderRadius: borderRadius);
      case ItemType.contact:
        return ItemWidgetContact(
            item: item,
            onTap: addToContacts,
            showBorder: showNoteBorder,
            borderRadius: borderRadius);
      case ItemType.completedTask:
      case ItemType.task:
        return ItemWidgetTask(item: item);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildGalleryCell(ModelItem mediaItem, double width) {
    final bool isVideo = mediaItem.type == ItemType.video;
    final bool isDownloadable = mediaItem.state == SyncState.downloadable.value;
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: width,
      height: width,
      child: PrivacyShield(
        isEnabled: privacyShield,
        onLongPress: () => onItemLongPressed(mediaItem),
        borderRadius: BorderRadius.circular(14),
        child: GestureDetector(
          onTap: () {
            if (_hasNotesSelected) {
              onItemTapped(mediaItem);
            } else {
              viewImageVideo(mediaItem);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: _selectedItems.contains(mediaItem)
                  ? cs.onSurface.withValues(alpha: 0.1)
                  : Colors.transparent,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
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
                            prefixIcon: IconButton(
                              onPressed: _onPaste,
                              icon: const Icon(LucideIcons.clipboard, size: 20),
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                              tooltip: "Paste from clipboard",
                            ),
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
                                      size: 26,
                                      color: cs.onSurfaceVariant
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          onChanged: _onInputTextChanged,
                          contentInsertionConfiguration:
                              ContentInsertionConfiguration(
                            allowedMimeTypes: const <String>[
                              'image/png',
                              'image/jpeg',
                              'image/gif'
                            ],
                            onContentInserted:
                                (KeyboardInsertedContent content) async {
                              if (content.data != null) {
                                final tempDir = await getTemporaryDirectory();
                                final fileName =
                                    'pasted_image_${DateTime.now().millisecondsSinceEpoch}.${content.mimeType.split('/').last}';
                                final file =
                                    File(path.join(tempDir.path, fileName));
                                await file.writeAsBytes(content.data!);
                                processFiles([file.path]);
                              }
                            },
                          ),
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
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        final cs = Theme.of(context).colorScheme;
        final tiles = <({
          IconData icon,
          String label,
          String subtitle,
          Color? color,
          VoidCallback onTap
        })>[
          if (ImagePicker().supportsImageSource(ImageSource.camera))
            (
              icon: LucideIcons.camera,
              label: "Camera",
              subtitle: "Capture a photo or video",
              color: null,
              onTap: () {
                Navigator.pop(context);
                _addMedia("camera_image");
              },
            ),
          (
            icon: LucideIcons.file,
            label: "Files",
            subtitle: "Attach any file from your device",
            color: null,
            onTap: () {
              Navigator.pop(context);
              _addMedia('files');
            },
          ),
          (
            icon: LucideIcons.checkCircle,
            label: "Checklist",
            subtitle: _isCreatingTask
                ? "Checklist mode is on"
                : "Turn your note into a to-do list",
            color: _isCreatingTask ? cs.primary : null,
            onTap: () {
              Navigator.pop(context);
              setTaskMode();
            },
          ),
          (
            icon: LucideIcons.mapPin,
            label: "Location",
            subtitle: "Share a pinned location",
            color: null,
            onTap: () {
              Navigator.pop(context);
              _addMedia('location');
            },
          ),
          if (Platform.isAndroid || Platform.isIOS)
            (
              icon: LucideIcons.contact,
              label: "Contact",
              subtitle: "Share a contact card",
              color: null,
              onTap: () {
                Navigator.pop(context);
                _addMedia('contact');
              },
            ),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(height: 3),
                  _bottomSheetTile(
                    context: context,
                    icon: tiles[i].icon,
                    label: tiles[i].label,
                    subtitle: tiles[i].subtitle,
                    color: tiles[i].color,
                    borderRadius: listRowRadius(i, tiles.length),
                    onTap: tiles[i].onTap,
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
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
