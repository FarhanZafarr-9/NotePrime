import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ntsapp/utils/common.dart';
import 'package:ntsapp/models/model_category_group.dart';
import 'package:ntsapp/models/model_item_group.dart';
import 'package:ntsapp/utils/auth_guard.dart';
import 'package:ntsapp/services/service_logger.dart';

import '../common_widgets.dart';
import '../widgets_shimmer.dart';
import '../../utils/enums.dart';
import '../../models/model_category.dart';
import '../../models/model_item.dart';
import '../../models/model_setting.dart';
import 'page_category_add_edit.dart';
import 'page_group_add_edit.dart';
import 'page_items.dart';
import '../../services/service_events.dart';

class PageCategoryGroups extends StatefulWidget {
  final bool runningOnDesktop;
  final Function(PageType, bool, PageParams)? setShowHidePage;
  final ModelCategory category;
  final List<String> sharedContents;
  final Function() onSharedContentsLoaded;
  final ModelGroup? selectedGroup;

  const PageCategoryGroups(
      {super.key,
      required this.category,
      required this.sharedContents,
      required this.onSharedContentsLoaded,
      required this.runningOnDesktop,
      required this.setShowHidePage,
      this.selectedGroup});

  @override
  State<PageCategoryGroups> createState() => _PageCategoryGroupsState();
}

class _PageCategoryGroupsState extends State<PageCategoryGroups> {
  final AppLogger logger = AppLogger(prefixes: ["CategoryGroups"]);
  final LocalAuthentication _auth = LocalAuthentication();

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

  List<ModelGroup> categoryGroupsDisplayList = [];
  late ModelCategory category;
  ModelGroup? selectedGroup;
  bool loadedSharedContents = false;
  bool _isReordering = false;
  bool _isLoading = true;
  Timer? _debounceTimer;

  late StreamSubscription categoryStream;
  late StreamSubscription groupStream;
  late StreamSubscription itemStream;

  @override
  void initState() {
    super.initState();
    category = widget.category;
    selectedGroup = widget.selectedGroup;
    EventStream().notifier.addListener(_handleAppEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadGroups();
    });
  }

  @override
  void dispose() {
    EventStream().notifier.removeListener(_handleAppEvent);
    super.dispose();
  }

  void _handleAppEvent() {
    final AppEvent? event = EventStream().notifier.value;
    if (event == null) return;

    switch (event.type) {
      case EventType.changedCategoryId:
        if (mounted) changedCategory(event.value);
        break;
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

  Future<void> changedCategory(String? id) async {
    if (id == null || id != category.id) return;
    ModelCategory? currentCategory = await ModelCategory.get(id);
    if (currentCategory != null) {
      if (mounted) {
        setState(() {
          category = currentCategory;
        });
      }
    } else if (!widget.runningOnDesktop && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> changedGroup(String? id) async {
    if (id == null) return;
    ModelGroup? group = await ModelGroup.get(id);
    if (group != null) {
      if (group.categoryId == category.id) {
        updateDisplayGroup(group);
      } else {
        _loadGroups();
      }
    } else {
      _loadGroups();
    }
  }

  Future<void> changedItem(String? id) async {
    if (id == null) return;
    ModelItem? item = await ModelItem.get(id);
    if (item != null) {
      String groupId = item.groupId;
      ModelGroup? group = await ModelGroup.get(groupId);
      if (group != null && group.categoryId == category.id) {
        updateDisplayGroup(group);
      }
    }
  }

  void updateDisplayGroup(ModelGroup group) {
    bool updated = false;
    for (ModelGroup categoryGroup in categoryGroupsDisplayList) {
      if (categoryGroup.id == group.id) {
        if (categoryGroup.position == group.position && group.archivedAt == 0) {
          int groupIndex = categoryGroupsDisplayList.indexOf(categoryGroup);
          setState(() {
            categoryGroupsDisplayList[groupIndex] = group;
          });
          updated = true;
        }
        break;
      }
    }
    if (!updated) {
      _loadGroups();
    }
  }

  void _loadGroups() {
    _debounceTimer?.cancel(); // Cancel any ongoing debounce
    _debounceTimer = Timer(Duration(seconds: 1), () {
      loadGroups();
    });
  }

  Future<void> loadGroups() async {
    List<ModelGroup> groups = await ModelGroup.inCategory(category.id!);
    setState(() {
      categoryGroupsDisplayList = groups;
      _isLoading = false;
    });
  }

  Future<void> reloadCategory() async {
    ModelCategory? updatedCategory = await ModelCategory.get(category.id!);
    if (updatedCategory != null) {
      setState(() {
        category = updatedCategory;
      });
    }
  }

  Future<void> updateGroupInDisplayList(String groupId) async {
    ModelGroup? group = await ModelGroup.get(groupId);
    if (group != null) {
      int index =
          categoryGroupsDisplayList.indexWhere((group) => group.id == groupId);
      if (index != -1) {
        categoryGroupsDisplayList[index] = group;
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  Future<void> navigateToNotes(ModelGroup group, bool updateGroupList) async {
    // ── Group lock check ──────────────────────────────────────────────────
    bool isGroupLocked = false;
    bool useGroupSettings =
        ModelSetting.get("use_group_settings", "yes") == "yes";
    if (useGroupSettings) {
      Map<String, dynamic>? data = group.data;
      if (data != null && data.containsKey("group_lock")) {
        isGroupLocked = data["group_lock"] == 1;
      }
    } else {
      isGroupLocked =
          ModelSetting.get("global_group_lock", "no") == "yes";
    }

    if (isGroupLocked) {
      try {
        AuthGuard.isAuthenticating = true;
        bool authenticated = await _auth.authenticate(
          localizedReason: 'Authenticate to open this group',
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: true,
          ),
        );
        if (!authenticated) {
          if (mounted) {
            displaySnackBar(context,
                message: "Authentication required", seconds: 1);
          }
          return;
        }
      } catch (e) {
        logger.error("Group lock auth failed", error: e);
        if (mounted) {
          displaySnackBar(context,
              message: "Authentication failed", seconds: 1);
        }
        return;
      } finally {
        AuthGuard.isAuthenticating = false;
        AuthGuard.lastActiveAt = DateTime.now();
      }
    }

    if (!mounted) return;

    // ── Navigate ──────────────────────────────────────────────────────────
    List<String> sharedContents =
        loadedSharedContents || widget.sharedContents.isEmpty
            ? []
            : widget.sharedContents;
    widget.onSharedContentsLoaded();
    loadedSharedContents = true;
    if (widget.runningOnDesktop) {
      setState(() {
        selectedGroup = group;
      });
      widget.setShowHidePage!(PageType.items, true, PageParams(group: group));
    } else {
      Navigator.of(context)
          .push(AnimatedPageRoute(
              child: PageItems(
        group: group,
        sharedContents: sharedContents,
        runningOnDesktop: widget.runningOnDesktop,
        setShowHidePage: widget.setShowHidePage,
      )))
          .then((value) {
        if (value != false) {
          if (updateGroupList) {
            loadGroups();
          } else {
            updateGroupInDisplayList(group.id!);
          }
        }
      });
    }
  }

  Future<void> archiveGroup(ModelGroup group) async {
    group.archivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    await group.update(["archived_at"]);
    categoryGroupsDisplayList.remove(group);
    if (mounted) {
      displaySnackBar(context, message: "Moved to trash", seconds: 1);
    }
    await signalToUpdateHome();
  }

  Future<void> _saveGroupPositions() async {
    for (ModelGroup group in categoryGroupsDisplayList) {
      int position = categoryGroupsDisplayList.indexOf(group);
      group.position = position;
      await group.update(["position"]);
    }
  }

  Future<void> onNoteGroupDeleted() async {
    loadGroups();
    if (mounted) {
      displaySnackBar(context, message: "Moved to trash", seconds: 1);
    }
  }

  void navigateToGroupAddEdit(ModelGroup? group, ModelCategory category) {
    if (widget.runningOnDesktop) {
      widget.setShowHidePage!(
          PageType.addEditGroup, true, PageParams(group: group));
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute(
        builder: (context) => PageGroupAddEdit(
          category: category,
          group: group,
          runningOnDesktop: widget.runningOnDesktop,
          setShowHidePage: widget.setShowHidePage,
        ),
        settings: const RouteSettings(name: "AddEditCategoryGroup"),
      ))
          .then((value) {
        if (value is ModelGroup) {
          navigateToNotes(value, true);
        }
      });
    }
  }

  void navigateToCategoryAddEdit() {
    if (widget.runningOnDesktop) {
      widget.setShowHidePage!(
          PageType.addEditCategory, true, PageParams(category: category));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => PageCategoryAddEdit(
          category: category,
          runningOnDesktop: widget.runningOnDesktop,
          setShowHidePage: widget.setShowHidePage,
        ),
        settings: const RouteSettings(name: "EditCategory"),
      ));
    }
  }

  void _showOptions(BuildContext context, ModelGroup group) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _bottomSheetTile(
                  context: context,
                  icon: Icons.reorder,
                  label: 'Reorder',
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _isReordering = true;
                    });
                  },
                ),
                const SizedBox(height: 8),
                _bottomSheetTile(
                  context: context,
                  icon: LucideIcons.edit3,
                  label: 'Edit',
                  onTap: () {
                    Navigator.pop(context);
                    navigateToGroupAddEdit(group, category);
                  },
                ),
                const SizedBox(height: 8),
                _bottomSheetTile(
                  context: context,
                  icon: group.pinned == 1 ? LucideIcons.pinOff : LucideIcons.pin,
                  label: group.pinned == 1
                      ? 'Unpin from Shortcut'
                      : 'Pin to Shortcut',
                  onTap: () async {
                    Navigator.pop(context);
                    group.pinned = group.pinned == 1 ? 0 : 1;
                    await group.update(["pinned"]);
                  },
                ),
                const SizedBox(height: 8),
                _bottomSheetTile(
                  context: context,
                  icon: LucideIcons.trash,
                  label: 'Delete',
                  isDanger: true,
                  onTap: () {
                    Navigator.pop(context);
                    archiveGroup(group);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bottomSheetTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = isDanger ? cs.error : cs.onSurfaceVariant;
    return Material(
      color: cs.onSurface.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 14),
              Text(label,
                  style: TextStyle(
                      fontSize: 15, color: isDanger ? cs.error : cs.onSurface)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isReordering,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          setState(() {
            _isReordering = false;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              if (!_isReordering && (loadedSharedContents || widget.sharedContents.isEmpty)) ...[
                WidgetCategoryGroupAvatar(
                  type: "category",
                  size: 32,
                  color: category.color,
                  title: category.title,
                  thumbnail: category.thumbnail,
                  icon: category.icon,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  _isReordering
                      ? "Reordering"
                      : loadedSharedContents || widget.sharedContents.isEmpty
                          ? category.title
                          : "Select...",
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: "Edit Category",
                onPressed: navigateToCategoryAddEdit,
                icon: _buildIconBadge(LucideIcons.edit2),
              ),
            )
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: _isReordering
              // Lines 491-537: Replace the ReorderableListView.builder with this:

              ? ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: categoryGroupsDisplayList.length,
                  itemBuilder: (context, index) {
                    final cs = Theme.of(context).colorScheme;
                    final ModelGroup group = categoryGroupsDisplayList[index];
                    final ModelCategoryGroup categoryGroup = ModelCategoryGroup(
                        id: group.id!,
                        type: "group",
                        group: group,
                        position: group.position!,
                        thumbnail: group.thumbnail,
                        color: group.color,
                        title: group.title);
                    return Container(
                      key: ValueKey(group.id),
                      margin: const EdgeInsets.only(bottom: 3),
                      child: Material(
                        color: cs.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          String dragTitle = "Drag handle to re-order";
                          if (Platform.isAndroid || Platform.isIOS) {
                            dragTitle = "Hold and drag to re-order";
                          }
                          displaySnackBar(context,
                              message: dragTitle, seconds: 1);
                        },
                        child: WidgetCategoryGroup(
                          categoryGroup: categoryGroup,
                          showSummary: true,
                          showCategorySign: false,
                        ),
                      ),
                    )
                  );
                  },
                  onReorder: (int oldIndex, int newIndex) {
                    setState(() {
                      // Adjust newIndex if dragging an item down
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }

                      // Remove the item from the old position
                      final item = categoryGroupsDisplayList.removeAt(oldIndex);

                      // Insert the item at the new position
                      categoryGroupsDisplayList.insert(newIndex, item);

                      // Print positions after reordering
                      _saveGroupPositions();
                    });
                  },
                )
              : _isLoading
                  ? const ShimmerList()
                  : categoryGroupsDisplayList.isNotEmpty
                      ? RefreshIndicator(
                          onRefresh: () async => loadGroups(),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: categoryGroupsDisplayList.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 3),
                            itemBuilder: (context, index) {
                              final cs = Theme.of(context).colorScheme;
                              final ModelGroup group = categoryGroupsDisplayList[index];
                              final ModelCategoryGroup categoryGroup = ModelCategoryGroup(
                                  id: group.id!,
                                  type: "group",
                                  group: group,
                                  position: group.position!,
                                  thumbnail: group.thumbnail,
                                  color: group.color,
                                  title: group.title);
                              final bool isSelected = selectedGroup != null && selectedGroup!.id == group.id;

                              return Material(
                                color: isSelected
                                    ? cs.onSurface.withValues(alpha: 0.1)
                                    : cs.onSurface.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    navigateToNotes(group, false);
                                  },
                                  onLongPress: () {
                                    _showOptions(context, group);
                                  },
                                  child: WidgetCategoryGroup(
                                    categoryGroup: categoryGroup,
                                    showSummary: true,
                                    showCategorySign: false,
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                      : const SizedBox.shrink(),
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: "add_category_group_or_mark_reordering_complete",
          onPressed: () {
            if (_isReordering) {
              setState(() {
                _isReordering = false;
              });
            } else {
              navigateToGroupAddEdit(null, category);
            }
          },
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: Icon(_isReordering ? LucideIcons.check : LucideIcons.plus),
        ),
      ),
    );
  }
}
