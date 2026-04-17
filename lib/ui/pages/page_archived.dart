import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ntsapp/utils/common.dart';
import 'package:ntsapp/utils/enums.dart';
import 'package:ntsapp/ui/pages/page_archived_category.dart';

import 'page_archived_groups.dart';
import 'page_archived_items.dart';

class PageArchived extends StatefulWidget {
  final bool runningOnDesktop;
  final Function(PageType, bool, PageParams)? setShowHidePage;
  const PageArchived(
      {super.key,
      required this.runningOnDesktop,
      required this.setShowHidePage});

  @override
  State<PageArchived> createState() => _PageArchivedState();
}

class _PageArchivedState extends State<PageArchived>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<bool> _isAnyItemSelected = ValueNotifier(false);
  final ValueNotifier<int> _selectionCount = ValueNotifier(0);

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

  VoidCallback? _onDelete;
  VoidCallback? _onRestore;
  VoidCallback? _onSelectAll;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _isAnyItemSelected.value = false;
        _selectionCount.value = 0;
        _onDelete = null;
        _onRestore = null;
        _onSelectAll = null;
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _isAnyItemSelected.dispose();
    _selectionCount.dispose();
    super.dispose();
  }

  void _deleteSelectedItems() {
    _onDelete?.call();
    _isAnyItemSelected.value = false;
    _selectionCount.value = 0;
  }

  void _restoreSelectedItems() {
    _onRestore?.call();
    _isAnyItemSelected.value = false;
    _selectionCount.value = 0;
  }

  void _selectAllItems() {
    _onSelectAll?.call();
  }

  Future<void> _showDeleteConfirmation(BuildContext context) async {
    final count = _selectionCount.value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete permanently?"),
        content: Text(
          "This will permanently delete $count item${count == 1 ? '' : 's'}. This cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirmed == true) _deleteSelectedItems();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Trash"),
        leading: widget.runningOnDesktop
            ? BackButton(
                onPressed: () {
                  widget.setShowHidePage!(
                      PageType.archive, false, PageParams());
                },
              )
            : null,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _isAnyItemSelected,
            builder: (context, isSelected, child) {
              if (!isSelected) return const SizedBox.shrink();
              return Row(
                children: [
                  TextButton(
                    onPressed: _selectAllItems,
                    child: Text("All", style: TextStyle(color: cs.primary)),
                  ),
                  IconButton(
                    icon: _buildIconBadge(LucideIcons.archiveRestore),
                    tooltip: "Restore",
                    onPressed: _restoreSelectedItems,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: _buildIconBadge(LucideIcons.trash2),
                    tooltip: "Delete permanently",
                    onPressed: () => _showDeleteConfirmation(context),
                  ),
                  const SizedBox(width: 8),
                ],
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Notes"),
            Tab(text: "Groups"),
            Tab(text: "Categories"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          PageArchivedItems(
            onSelectionChange: (isSelected, count) {
              _isAnyItemSelected.value = isSelected;
              _selectionCount.value = count;
            },
            setDeleteCallback: (cb) => _onDelete = cb,
            setRestoreCallback: (cb) => _onRestore = cb,
            setSelectAllCallback: (cb) => _onSelectAll = cb,
          ),
          PageArchivedGroups(
            onSelectionChange: (isSelected, count) {
              _isAnyItemSelected.value = isSelected;
              _selectionCount.value = count;
            },
            setDeleteCallback: (cb) => _onDelete = cb,
            setRestoreCallback: (cb) => _onRestore = cb,
            setSelectAllCallback: (cb) => _onSelectAll = cb,
          ),
          PageArchivedCategories(
            onSelectionChange: (isSelected, count) {
              _isAnyItemSelected.value = isSelected;
              _selectionCount.value = count;
            },
            setDeleteCallback: (cb) => _onDelete = cb,
            setRestoreCallback: (cb) => _onRestore = cb,
            setSelectAllCallback: (cb) => _onSelectAll = cb,
          ),
        ],
      ),
    );
  }
}
