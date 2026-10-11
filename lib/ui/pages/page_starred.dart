import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ntsapp/utils/common.dart';
import 'package:ntsapp/ui/common_widgets.dart';
import 'package:ntsapp/utils/enums.dart';

import '../../models/model_item.dart';
import '../../models/model_item_group.dart';
import 'page_items.dart';
import '../widgets_item.dart';

class PageStarredItems extends StatefulWidget {
  final bool runningOnDesktop;
  final Function(PageType, bool, PageParams)? setShowHidePage;
  const PageStarredItems({
    super.key,
    required this.runningOnDesktop,
    required this.setShowHidePage,
  });

  @override
  State<PageStarredItems> createState() => _PageStarredItemsState();
}

class _PageStarredItemsState extends State<PageStarredItems> {
  final List<ModelItem> _items = [];
  final List<ModelItem> _selection = [];
  bool _isSelecting = false;
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _limit = 20;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fetchStarredItemsOnInit();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> fetchStarredItemsOnInit() async {
    _items.clear();
    setState(() {
      _isLoading = true;
    });
    final topItems = await ModelItem.getStarred(0, _limit);
    if (topItems.length == _limit) {
      _offset += _limit;
    } else {
      _hasMore = false;
    }
    setState(() {
      _items.addAll(topItems);
      _isLoading = false;
    });
  }

  Future<void> fetchStarredOnScroll() async {
    if (_isLoading || !_hasMore) return;
    if (_offset == 0) _items.clear();
    setState(() => _isLoading = true);

    final newItems = await ModelItem.getStarred(_offset, _limit);
    setState(() {
      _items.addAll(newItems);
      if (newItems.length == _limit) {
        _offset += _limit;
      } else {
        _hasMore = false;
      }
      _isLoading = false;
    });
  }

  void onItemLongPressed(ModelItem item) {
    setState(() {
      if (_selection.contains(item)) {
        _selection.remove(item);
        if (_selection.isEmpty) {
          _isSelecting = false;
        }
      } else {
        _selection.add(item);
        if (!_isSelecting) _isSelecting = true;
      }
    });
  }

  Future<void> onItemTapped(ModelItem item) async {
    ModelGroup? group = await ModelGroup.get(item.groupId);
    if (_isSelecting) {
      setState(() {
        if (_selection.contains(item)) {
          _selection.remove(item);
          if (_selection.isEmpty) {
            _isSelecting = false;
          }
        } else {
          _selection.add(item);
        }
      });
    } else {
      if (!mounted || group == null) return;
      if (widget.runningOnDesktop) {
        widget.setShowHidePage!(
            PageType.items, true, PageParams(group: group, id: item.id));
      } else {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => PageItems(
            runningOnDesktop: widget.runningOnDesktop,
            setShowHidePage: widget.setShowHidePage,
            group: group,
            sharedContents: const [],
            loadItemIdOnInit: item.id,
          ),
          settings: const RouteSettings(name: "Notes"),
        ));
      }
    }
  }

  Future<void> archiveSelectedItems() async {
    for (ModelItem item in _selection) {
      item.archivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
      await item.update(["archived_at"]);
    }
    if (mounted) {
      displaySnackBar(context, message: "Moved to trash", seconds: 1);
    }
    clearSelection();
    fetchStarredItemsOnInit();
  }

  Future<void> markSelectedUnStarred() async {
    for (ModelItem item in _selection) {
      item.starred = 0;
      item.update(["starred"]);
    }
    clearSelection();
    fetchStarredItemsOnInit();
  }

  void clearSelection() {
    setState(() {
      _selection.clear();
      _isSelecting = false;
    });
  }

  // ── Bubble grouping helpers (shared language with the messages page) ─────
  static const int bubbleGroupWindowMinutes = 10;

  bool _withinGroupWindow(int a, int b) {
    final int? ta = _items[a].at;
    final int? tb = _items[b].at;
    if (ta == null || tb == null) return false;
    final diff = DateTime.fromMillisecondsSinceEpoch(ta, isUtc: true)
        .difference(DateTime.fromMillisecondsSinceEpoch(tb, isUtc: true));
    return diff.abs().inMinutes <= bubbleGroupWindowMinutes;
  }

  bool _isTaskItem(ModelItem item) =>
      item.type == ItemType.task || item.type == ItemType.completedTask;

  bool _isAttachmentItem(ModelItem item) =>
      item.type == ItemType.image ||
      item.type == ItemType.video ||
      item.type == ItemType.audio ||
      item.type == ItemType.document ||
      item.type == ItemType.location ||
      item.type == ItemType.contact;

  bool _canSeam(ModelItem item) =>
      item.type == ItemType.text ||
      _isTaskItem(item) ||
      _isAttachmentItem(item);

  int _seamFamilyId(ModelItem item) {
    if (item.type == ItemType.text) return 0;
    if (_isTaskItem(item)) return 1;
    return 2;
  }

  /// Only seam bubbles from the same conversation: the starred list mixes
  /// items across many groups, so messages from different chats must never
  /// visually connect no matter how close in time they are.
  bool _sameSeamFamily(ModelItem a, ModelItem b) =>
      a.groupId == b.groupId &&
      _canSeam(a) &&
      _canSeam(b) &&
      _seamFamilyId(a) == _seamFamilyId(b);

  bool _textConnectsAbove(int index) {
    if (index <= 0) return false;
    if (!_sameSeamFamily(_items[index], _items[index - 1])) return false;
    return _withinGroupWindow(index - 1, index);
  }

  bool _textConnectsBelow(int index) {
    if (index >= _items.length - 1) return false;
    if (!_sameSeamFamily(_items[index], _items[index + 1])) return false;
    return _withinGroupWindow(index, index + 1);
  }

  double _bubbleRadius(ModelItem item) {
    if (_isAttachmentItem(item)) return 14.0;
    if (item.type != ItemType.text &&
        item.type != ItemType.task &&
        item.type != ItemType.completedTask) {
      return 12.0;
    }
    final int len = item.text.length;
    if (len <= 20) return 22.0;
    if (len >= 120) return 10.0;
    return 22.0 - (len - 20) / (120 - 20) * 12.0;
  }

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

  Widget _buildSelectionOptions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          tooltip: "Unstar selected",
          onPressed: () {
            markSelectedUnStarred();
          },
          icon: _buildIconBadge(LucideIcons.starOff),
        ),
        const SizedBox(
          width: 4,
        ),
        IconButton(
          tooltip: "Move selection to trash",
          onPressed: () {
            archiveSelectedItems();
          },
          icon: _buildIconBadge(LucideIcons.trash),
        ),
        const SizedBox(
          width: 8,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelecting
            ? _buildSelectionOptions()
            : const Text("Starred notes"),
        leading: widget.runningOnDesktop
            ? BackButton(
                onPressed: () {
                  widget.setShowHidePage!(
                      PageType.starred, false, PageParams());
                },
              )
            : null,
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          if (scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent) {
            fetchStarredOnScroll();
          }
          return false;
        },
        child: ListView.builder(
          itemCount: _items.length, // Additional item for the loading indicator
          itemBuilder: (context, index) {
            final item = _items[index];
            final cs = Theme.of(context).colorScheme;

            // Same connected-stack language as the messages page: a bubble
            // flattens the corner shared with an adjacent bubble of the same
            // family within the grouping window, and gaps shrink accordingly.
            final bool isTextItem =
                item.type == ItemType.text || _isTaskItem(item);
            final bool seamable = _canSeam(item);
            final bool connAbove = seamable && _textConnectsAbove(index);
            final bool connBelow = seamable && _textConnectsBelow(index);
            final double bubbleRadius = _bubbleRadius(item);
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

            return GestureDetector(
              onLongPress: () {
                onItemLongPressed(item);
              },
              onTap: () {
                onItemTapped(item);
              },
              child: Container(
                width: double.infinity,
                color: _selection.contains(item)
                    ? Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.1)
                    : Colors.transparent,
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: connAbove ? 2 : (isTextItem ? 6 : 2),
                  bottom: connBelow ? 0 : 2,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.06),
                      borderRadius: bubbleBorder,
                    ),
                    child: _buildItem(item),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // Widget for displaying different item types
  Widget _buildItem(ModelItem item) {
    switch (item.type) {
      case ItemType.text:
        return ItemWidgetText(
          item: item,
        );
      case ItemType.task:
        return ItemWidgetTask(
          item: item,
        );
      case ItemType.completedTask:
        return ItemWidgetTask(
          item: item,
        );
      case ItemType.image:
        return ItemWidgetImage(
          item: item,
          onTap: onItemTapped,
        );
      case ItemType.video:
        return ItemWidgetVideo(
          item: item,
          onTap: onItemTapped,
        );
      case ItemType.audio:
        return ItemWidgetAudio(
          item: item,
        );
      case ItemType.document:
        return ItemWidgetDocument(
          item: item,
          onTap: onItemTapped,
        );
      case ItemType.location:
        return ItemWidgetLocation(
          item: item,
          onTap: onItemTapped,
        );
      case ItemType.contact:
        return ItemWidgetContact(
          item: item,
          onTap: onItemTapped,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
