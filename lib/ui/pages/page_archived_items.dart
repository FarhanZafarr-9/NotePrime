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

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 3),
      itemBuilder: (context, index) {
        final item = _items[index];
        final isSelected = _selection.contains(item);
        final bool isAttachment = item.type == ItemType.image ||
            item.type == ItemType.video ||
            item.type == ItemType.audio ||
            item.type == ItemType.document ||
            item.type == ItemType.location ||
            item.type == ItemType.contact;

        return GestureDetector(
          onTap: () => onItemTapped(item),
          onLongPress: () => onItemTapped(item),
          child: Container(
            width: double.infinity,
            color: isSelected
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
