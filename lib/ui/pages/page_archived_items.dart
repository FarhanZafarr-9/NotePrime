import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ntsapp/ui/common_widgets.dart';
import 'package:ntsapp/utils/enums.dart';
import 'package:ntsapp/services/service_events.dart';

import '../../models/model_item.dart';
import '../widgets_item.dart';

class PageArchivedItems extends StatefulWidget {
  final Function(bool, int) onSelectionChange;
  final Function(VoidCallback) setDeleteCallback;
  final Function(VoidCallback) setRestoreCallback;
  final Function(VoidCallback) setSelectAllCallback;

  const PageArchivedItems({
    super.key,
    required this.onSelectionChange,
    required this.setDeleteCallback,
    required this.setRestoreCallback,
    required this.setSelectAllCallback,
  });

  @override
  State<PageArchivedItems> createState() => _PageArchivedItemsState();
}

class _PageArchivedItemsState extends State<PageArchivedItems> {
  final List<ModelItem> _items = [];
  final List<ModelItem> _selection = [];
  // ignore: unused_field
  bool _isSelecting = false;

  @override
  void initState() {
    super.initState();
    widget.setDeleteCallback(deleteSelectedItems);
    widget.setRestoreCallback(restoreSelectedItems);
    widget.setSelectAllCallback(selectAllItems);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fetchArchivedItems();
    });
  }

  Future<void> fetchArchivedItems() async {
    _items.clear();
    final topItems = await ModelItem.getArchived();
    _items.addAll(topItems);
    if (mounted) setState(() {});
  }

  void onItemTapped(ModelItem item) {
    setState(() {
      if (_selection.contains(item)) {
        _selection.remove(item);
        if (_selection.isEmpty) {
          _isSelecting = false;
          widget.onSelectionChange(false, 0);
        } else {
          widget.onSelectionChange(true, _selection.length);
        }
      } else {
        _selection.add(item);
        _isSelecting = true;
        widget.onSelectionChange(true, _selection.length);
      }
    });
  }

  void selectAllItems() {
    setState(() {
      _selection.clear();
      _selection.addAll(_items);
      _isSelecting = true;
      widget.onSelectionChange(true, _selection.length);
    });
  }

  Future<void> restoreSelectedItems() async {
    final toRestore = List<ModelItem>.from(_selection);
    clearSelection();
    for (ModelItem item in toRestore) {
      item.archivedAt = 0;
      await item.update(["archived_at"]);
      EventStream()
          .publish(AppEvent(type: EventType.changedItemId, value: item.id));
    }
    if (mounted) {
      displaySnackBar(context, message: "Restored.", seconds: 1);
    }
    await fetchArchivedItems();
  }

  Future<void> deleteSelectedItems() async {
    final toDelete = List<ModelItem>.from(_selection);
    clearSelection();
    for (ModelItem item in toDelete) {
      _items.remove(item);
      await item.delete(withServerSync: true);
    }
    if (mounted) {
      displaySnackBar(context, message: "Deleted permanently.", seconds: 1);
    }
    await fetchArchivedItems();
  }

  void clearSelection() {
    setState(() {
      _selection.clear();
      _isSelecting = false;
    });
    widget.onSelectionChange(false, 0);
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

  bool _canSeam(ModelItem item) =>
      item.type == ItemType.text ||
      _isTaskItem(item) ||
      item.type == ItemType.image ||
      item.type == ItemType.video ||
      item.type == ItemType.audio ||
      item.type == ItemType.document ||
      item.type == ItemType.location ||
      item.type == ItemType.contact;

  int _seamFamilyId(ModelItem item) {
    if (item.type == ItemType.text) return 0;
    if (_isTaskItem(item)) return 1;
    return 2;
  }

  /// Only seam bubbles from the same conversation: this list mixes items across
  /// many groups, so messages from different chats must never visually connect
  /// no matter how close in time they are.
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
    if (_canSeam(item) && _seamFamilyId(item) == 2) return 14.0;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_items.isEmpty) {
      return _ArchivedEmptyState(
        icon: LucideIcons.fileText,
        message: "No archived notes",
        subtitle: "Notes you archive will appear here",
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final isSelected = _selection.contains(item);
        final bool isAttachment = item.type == ItemType.image ||
            item.type == ItemType.video ||
            item.type == ItemType.audio ||
            item.type == ItemType.document ||
            item.type == ItemType.location ||
            item.type == ItemType.contact;

        // Only media (image/video) bleeds to the screen edge; content bubbles
        // like voice notes stretch to fill their row and must stay inset.
        final bool isFullBleed =
            item.type == ItemType.image || item.type == ItemType.video;

        // Same connected-stack language as the messages page: a bubble
        // flattens the corner shared with an adjacent bubble of the same
        // family (and same group) within the grouping window, and gaps shrink
        // accordingly.
        final bool isTextItem =
            item.type == ItemType.text || _isTaskItem(item);
        final bool seamable = _canSeam(item);
        final bool connAbove = seamable && _textConnectsAbove(index);
        final bool connBelow = seamable && _textConnectsBelow(index);
        final double bubbleRadius = _bubbleRadius(item);
        final BorderRadius bubbleBorder = seamable
            ? BorderRadius.only(
                topLeft: Radius.circular(bubbleRadius),
                topRight: Radius.circular(connAbove ? 5 : bubbleRadius),
                bottomLeft: Radius.circular(bubbleRadius),
                bottomRight: Radius.circular(connBelow ? 5 : bubbleRadius),
              )
            : BorderRadius.circular(bubbleRadius);

        return GestureDetector(
          onTap: () => onItemTapped(item),
          onLongPress: () => onItemTapped(item),
          child: Container(
            width: double.infinity,
            color: isSelected
                ? cs.onSurface.withValues(alpha: 0.1)
                : Colors.transparent,
            padding: EdgeInsets.only(
              right: 12,
              left: isFullBleed ? 0 : 12,
              top: connAbove ? 2 : (isTextItem ? 6 : 2),
              bottom: connBelow ? 0 : 2,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Material(
                shape: RoundedRectangleBorder(
                  borderRadius: bubbleBorder,
                  side: BorderSide(
                    color: isAttachment
                        ? Colors.transparent
                        : cs.onSurface.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                color: isAttachment
                    ? Colors.transparent
                    : cs.onSurface.withValues(alpha: 0.07),
                child: Container(
                  margin: EdgeInsets.symmetric(
                    vertical: isAttachment ? 2 : 8,
                    horizontal: isAttachment ? 0 : 8,
                  ),
                  padding: EdgeInsets.all(isAttachment ? 0 : 6),
                  child: _buildItem(item),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildItem(ModelItem item) {
    switch (item.type) {
      case ItemType.task:
      case ItemType.completedTask:
        return ItemWidgetTask(item: item);
      case ItemType.text:
        return ItemWidgetText(item: item);
      case ItemType.image:
        return ItemWidgetImage(item: item, onTap: (_) {});
      case ItemType.video:
        return ItemWidgetVideo(item: item, onTap: (_) {});
      case ItemType.audio:
        return ItemWidgetAudio(item: item);
      case ItemType.document:
        return ItemWidgetDocument(item: item, onTap: (_) {});
      case ItemType.location:
        return ItemWidgetLocation(item: item, onTap: (_) {});
      case ItemType.contact:
        return ItemWidgetContact(item: item, onTap: (_) {});
      default:
        return const SizedBox.shrink();
    }
  }
}

class _ArchivedEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String subtitle;

  const _ArchivedEmptyState({
    required this.icon,
    required this.message,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 28, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
