import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ntsapp/ui/common_widgets.dart';
import 'package:ntsapp/models/model_category_group.dart';
import 'package:ntsapp/models/model_item_group.dart';

import '../../utils/common.dart';

class PageArchivedGroups extends StatefulWidget {
  final Function(bool, int) onSelectionChange;
  final Function(VoidCallback) setDeleteCallback;
  final Function(VoidCallback) setRestoreCallback;
  final Function(VoidCallback) setSelectAllCallback;

  const PageArchivedGroups({
    super.key,
    required this.onSelectionChange,
    required this.setDeleteCallback,
    required this.setRestoreCallback,
    required this.setSelectAllCallback,
  });

  @override
  State<PageArchivedGroups> createState() => _PageArchivedGroupsState();
}

class _PageArchivedGroupsState extends State<PageArchivedGroups> {
  final List<ModelGroup> _archivedGroups = [];
  final List<ModelGroup> _selection = [];
  // ignore: unused_field
  bool _isSelecting = false;

  @override
  void initState() {
    super.initState();
    widget.setDeleteCallback(deleteSelectedItems);
    widget.setRestoreCallback(restoreSelectedItems);
    widget.setSelectAllCallback(selectAllItems);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fetchArchivedGroups();
    });
  }

  Future<void> fetchArchivedGroups() async {
    _archivedGroups.clear();
    final groups = await ModelGroup.getArchived();
    _archivedGroups.addAll(groups);
    if (mounted) setState(() {});
  }

  void onItemTapped(ModelGroup item) {
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
      _selection.addAll(_archivedGroups);
      _isSelecting = true;
      widget.onSelectionChange(true, _selection.length);
    });
  }

  Future<void> restoreSelectedItems() async {
    final toRestore = List<ModelGroup>.from(_selection);
    clearSelection();
    for (ModelGroup item in toRestore) {
      item.archivedAt = 0;
      await item.update(["archived_at"]);
    }
    if (mounted) {
      displaySnackBar(context, message: "Restored.", seconds: 1);
    }
    await fetchArchivedGroups();
    await signalToUpdateHome();
  }

  Future<void> deleteSelectedItems() async {
    final toDelete = List<ModelGroup>.from(_selection);
    clearSelection();
    for (ModelGroup group in toDelete) {
      _archivedGroups.remove(group);
      await group.deleteCascade(withServerSync: true);
    }
    if (mounted) {
      displaySnackBar(context, message: "Deleted permanently.", seconds: 1);
    }
    await fetchArchivedGroups();
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

    if (_archivedGroups.isEmpty) {
      return _ArchivedEmptyState(
        icon: LucideIcons.folder,
        message: "No archived groups",
        subtitle: "Groups you archive will appear here",
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _archivedGroups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 3),
      itemBuilder: (context, index) {
        final archivedGroup = _archivedGroups[index];
        final isSelected = _selection.contains(archivedGroup);
        final categoryGroup = ModelCategoryGroup(
          id: archivedGroup.id!,
          type: "group",
          position: archivedGroup.position!,
          color: archivedGroup.color,
          title: archivedGroup.title,
        );
        return GestureDetector(
          onTap: () => onItemTapped(archivedGroup),
          onLongPress: () => onItemTapped(archivedGroup),
          child: Material(
            color: isSelected
                ? cs.onSurface.withValues(alpha: 0.1)
                : cs.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            child: WidgetCategoryGroup(
              categoryGroup: categoryGroup,
              showSummary: false,
              showCategorySign: false,
            ),
          ),
        );
      },
    );
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
