// ignore_for_file: unused_element, unused_field

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ntsapp/ui/common_widgets.dart';
import 'package:ntsapp/utils/auth_guard.dart';
import 'package:ntsapp/utils/enums.dart';
import 'package:ntsapp/models/model_preferences.dart';
import 'package:ntsapp/ui/pages/page_desktop_category_groups.dart';
import 'package:ntsapp/ui/pages/page_dummy.dart';
import 'package:ntsapp/ui/pages/page_group_add_edit.dart';
import 'package:ntsapp/ui/pages/page_logs.dart';
import 'package:ntsapp/ui/pages/page_plan_status.dart';
import 'package:ntsapp/ui/pages/page_sqlite.dart';
import 'package:ntsapp/ui/pages/page_starred.dart';
import 'package:ntsapp/services/service_events.dart';
import 'package:ntsapp/services/service_logger.dart';
import 'package:ntsapp/storage/storage_secure.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../utils/common.dart';
import '../../models/model_category.dart';
import '../../models/model_category_group.dart';
import '../../models/model_item.dart';
import '../../models/model_item_group.dart';
import '../../models/model_setting.dart';
import 'page_archived.dart';
import 'page_category_add_edit.dart';
import 'page_category_groups.dart';
import 'page_items.dart';
import 'page_search.dart';
import 'page_settings.dart';
import 'page_user_task.dart';
import '../../utils/utils_sync.dart';
import '../widgets_shimmer.dart';

class PageCategoriesGroups extends StatefulWidget {
  final List<String> sharedContents;
  final bool isDarkMode;
  final VoidCallback onThemeToggle;
  final bool useDynamicColor;
  final VoidCallback onDynamicColorToggle;
  final bool runningOnDesktop;
  final Function(PageType, bool, PageParams)? setShowHidePage;
  final ModelGroup? selectedGroup;
  final Color? accentColor;
  final Function(Color)? onAccentColorChange;

  const PageCategoriesGroups(
      {super.key,
      required this.sharedContents,
      required this.isDarkMode,
      required this.onThemeToggle,
      required this.useDynamicColor,
      required this.onDynamicColorToggle,
      required this.runningOnDesktop,
      required this.setShowHidePage,
      this.selectedGroup,
      this.accentColor,
      this.onAccentColorChange});

  @override
  State<PageCategoriesGroups> createState() => _PageCategoriesGroupsState();
}

class _PageCategoriesGroupsState extends State<PageCategoriesGroups> {
  final logger = AppLogger(prefixes: ["CategoriesGroups"]);
  final LocalAuthentication _auth = LocalAuthentication();
  SecureStorage secureStorage = SecureStorage();

  bool requiresAuthentication = false;
  bool isAuthenticated = false;
  bool isAuthenticating = false;

  ModelCategory? category;
  ModelGroup? selectedGroup;
  String? appName = "";
  List<ModelCategoryGroup> _categoriesGroupsDisplayList = [];
  bool _isFetchingFromServer = false;
  bool _hasInitiated = false;
  bool _isLoading = true;
  bool _isReordering = false;
  bool _canSync = false;
  bool loadedSharedContents = false;
  Timer? _debounceTimer;

  bool hasValidPlan = false;
  bool loggingEnabled = false;

  @override
  void initState() {
    super.initState();
    selectedGroup = widget.selectedGroup;
    loggingEnabled =
        ModelSetting.get(AppString.loggingEnabled.string, "no") == "yes";
    EventStream().notifier.addListener(_handleAppEvent);
    logger.info("Monitoring changes");
    checkAuthAndLoad();
  }

  @override
  void dispose() {
    EventStream().notifier.removeListener(_handleAppEvent);
    super.dispose();
  }

  void _handleAppEvent() {
    final AppEvent? event = EventStream().notifier.value;
    logger.debug("App Event in Home: ${event?.type}");
    if (event == null) return;

    switch (event.type) {
      case EventType.authorise:
        if (requiresAuthentication) {
          checkAuthAndLoad();
        }
        break;
      case EventType.changedCategoryId:
        if (!requiresAuthentication || isAuthenticated) {
          if (mounted) changedCategory(event.value);
        }
        break;
      case EventType.changedGroupId:
        if (!requiresAuthentication || isAuthenticated) {
          if (mounted) changedGroup(event.value);
        }
        break;
      case EventType.changedItemId:
        if (!requiresAuthentication || isAuthenticated) {
          if (mounted) changedItem(event.value);
        }
        break;
      case EventType.exitSettings:
        onExitSettings();
        break;
      case EventType.serverFirstFetchStarts:
        if (mounted) {
          setState(() {
            _isFetchingFromServer = true;
          });
        }
        break;
      case EventType.serverFirstFetchEnds:
        if (mounted) {
          setState(() {
            _isFetchingFromServer = false;
          });
        }
        break;
      case EventType.checkPlanStatus:
        checkUpdateStateVariables();
        break;
      case EventType.navigateToGroup:
        _handleDeepLinkNavigation(event.value);
        break;
    }
  }

  Future<void> _handleDeepLinkNavigation(dynamic value) async {
    if (value == 'new') {
      createNoteGroup();
    } else if (value is String) {
      final group = await ModelGroup.get(value);
      if (group != null && mounted) {
        navigateToNotes(group, []);
      }
    }
  }

  Future<void> changedCategory(String? id) async {
    if (id == null) return;
    bool updated = false;
    ModelCategory? category = await ModelCategory.get(id);
    if (category != null) {
      for (ModelCategoryGroup categoryGroup in _categoriesGroupsDisplayList) {
        if (categoryGroup.type == "category" &&
            categoryGroup.id == category.id) {
          if (categoryGroup.position == category.position) {
            int categoryIndex =
                _categoriesGroupsDisplayList.indexOf(categoryGroup);
            setState(() {
              _categoriesGroupsDisplayList[categoryIndex].title =
                  category.title;
              _categoriesGroupsDisplayList[categoryIndex].color =
                  category.color;
              _categoriesGroupsDisplayList[categoryIndex].thumbnail =
                  category.thumbnail;
            });
            updated = true;
          }
          break;
        }
      }
    }
    if (!updated) {
      _loadCategoriesGroups();
    }
  }

  Future<void> changedGroup(String? id) async {
    if (id == null) return;
    bool updated = false;
    ModelGroup? group = await ModelGroup.get(id);
    if (group != null) {
      for (ModelCategoryGroup categoryGroup in _categoriesGroupsDisplayList) {
        if (categoryGroup.type == "group" && categoryGroup.id == group.id) {
          if (categoryGroup.position == group.position &&
              group.archivedAt == 0) {
            int groupIndex =
                _categoriesGroupsDisplayList.indexOf(categoryGroup);
            setState(() {
              _categoriesGroupsDisplayList[groupIndex].title = group.title;
              _categoriesGroupsDisplayList[groupIndex].color = group.color;
              _categoriesGroupsDisplayList[groupIndex].thumbnail =
                  group.thumbnail;
            });
            updated = true;
          }
          break;
        }
      }
    }
    if (!updated) {
      _loadCategoriesGroups();
    }
  }

  Future<void> changedItem(String? id) async {
    if (id == null) return;
    bool updated = false;
    ModelItem? item = await ModelItem.get(id);
    if (item != null) {
      String groupId = item.groupId;
      ModelGroup? group = await ModelGroup.get(groupId);
      if (group != null) {
        for (ModelCategoryGroup categoryGroup in _categoriesGroupsDisplayList) {
          if (categoryGroup.type == "group" && categoryGroup.id == groupId) {
            int groupIndex =
                _categoriesGroupsDisplayList.indexOf(categoryGroup);
            setState(() {
              _categoriesGroupsDisplayList[groupIndex].group = group;
            });
            updated = true;
            break;
          }
        }
      }
    }
    if (!updated) {
      _loadCategoriesGroups();
    }
  }

  Future<void> checkUpdateStateVariables() async {
    _canSync = await SyncUtils.canSync();
    hasValidPlan = await ModelPreferences.get(AppString.hasValidPlan.string,
            defaultValue: "yes") ==
        "yes";
    loggingEnabled =
        ModelSetting.get(AppString.loggingEnabled.string, "no") == "yes";
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> checkAuthAndLoad() async {
    if (isAuthenticating) return;
    isAuthenticating = true;
    appName = await secureStorage.read(key: AppString.appName.string);
    await checkUpdateStateVariables();
    setState(() {});
    try {
      if (ModelSetting.get("local_auth", "no") == "no") {
        isAuthenticated = true;
        AuthGuard.isLocked.value = false;
        await loadCategoriesGroups();
      } else {
        logger.info("Requires authentication");
        requiresAuthentication = true;
        AuthGuard.isLocked.value = true;
        await _authenticateOnStart();
      }
    } catch (e, s) {
      logger.error("checkAuthAndLoad", error: e, stackTrace: s);
    } finally {
      isAuthenticating = false;
    }
  }

  void _loadCategoriesGroups() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(seconds: 1), () {
      loadCategoriesGroups();
    });
  }

  Future<void> loadCategoriesGroups() async {
    checkUpdateStateVariables();
    setState(() {
      _hasInitiated = true;
    });
    try {
      final categoriesGroups = await ModelCategoryGroup.all();
      setState(() {
        _categoriesGroupsDisplayList = categoriesGroups;
        _isLoading = false;
      });
      logger.info("Loaded categoriesGroups");
    } catch (e, s) {
      logger.error("loadCategoriesGroups", error: e, stackTrace: s);
      setState(() {
        _isLoading = false;
      });
    }
    if (_categoriesGroupsDisplayList.isEmpty && widget.runningOnDesktop) {
      widget.setShowHidePage!(PageType.items, false, PageParams());
    }
  }

  Future<void> _authenticateOnStart() async {
    try {
      AuthGuard.isAuthenticating = true;
      if (Platform.isIOS) await Future.delayed(Duration(milliseconds: 100));
      isAuthenticated = await _auth.authenticate(
        localizedReason: 'Please authenticate',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );

      if (isAuthenticated) {
        AuthGuard.isLocked.value = false;
        loadCategoriesGroups();
      }
    } catch (e, s) {
      logger.error("_authenticateOnStart", error: e, stackTrace: s);
    } finally {
      AuthGuard.isAuthenticating = false;
      AuthGuard.lastActiveAt = DateTime.now();
    }
  }

  void createNoteGroup() {
    if (widget.runningOnDesktop) {
      widget.setShowHidePage!(PageType.addEditGroup, true, PageParams());
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute(
        builder: (context) => PageGroupAddEdit(
          runningOnDesktop: widget.runningOnDesktop,
          setShowHidePage: widget.setShowHidePage,
        ),
        settings: const RouteSettings(name: "CreateNoteGroup"),
      ))
          .then((value) {
        if (value is ModelGroup) {
          navigateToNotes(value, []);
        }
      });
    }
  }

  void navigateToNotesOrGroups(ModelCategoryGroup categoryGroup) {
    List<String> sharedContents =
        loadedSharedContents || widget.sharedContents.isEmpty
            ? []
            : widget.sharedContents;

    if (categoryGroup.type == "group") {
      loadedSharedContents = true;
      navigateToNotes(categoryGroup.group!, sharedContents);
    } else {
      navigateToGroups(categoryGroup.category!, sharedContents);
    }
  }

  Future<void> updateGroupInDisplayList(String groupId) async {
    ModelGroup? group = await ModelGroup.get(groupId);
    if (group != null) {
      int index = _categoriesGroupsDisplayList.indexWhere((categoryGroup) =>
          categoryGroup.type == "group" && categoryGroup.id == groupId);
      if (index != -1) {
        setState(() {
          _categoriesGroupsDisplayList[index].group = group;
        });
      }
    }
  }

  void navigateToGroups(ModelCategory category, List<String> sharedContents) {
    if (widget.runningOnDesktop) {
      Navigator.of(context).push(AnimatedPageRoute(
        child: PageCategoryGroupsPane(
            sharedContents: sharedContents, category: category),
      ));
    } else {
      Navigator.of(context).push(AnimatedPageRoute(
        child: PageCategoryGroups(
            onSharedContentsLoaded: () {
              setState(() {
                loadedSharedContents = true;
              });
            },
            runningOnDesktop: false,
            setShowHidePage: null,
            sharedContents: sharedContents,
            category: category),
      ));
    }
  }

  Future<void> navigateToNotes(
      ModelGroup group, List<String> sharedContents) async {
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
      }
    }

    if (!mounted) return;

    // ── Navigate ──────────────────────────────────────────────────────────
    if (widget.runningOnDesktop) {
      setState(() {
        selectedGroup = group;
      });
      widget.setShowHidePage!(PageType.items, true, PageParams(group: group));
    } else {
      Navigator.of(context)
          .push(AnimatedPageRoute(
        child: PageItems(
          runningOnDesktop: widget.runningOnDesktop,
          setShowHidePage: widget.setShowHidePage,
          group: group,
          sharedContents: sharedContents,
        ),
      ))
          .then((value) {
        if (value != false) {
          setState(() {
            updateGroupInDisplayList(group.id!);
          });
        }
        checkShowReviewDialog();
      });
    }
  }

  Future<void> archiveCategoryGroup(ModelCategoryGroup categoryGroup) async {
    if (categoryGroup.type == "group") {
      categoryGroup.group!.archivedAt =
          DateTime.now().toUtc().millisecondsSinceEpoch;
      await categoryGroup.group!.update(["archived_at"]);
      if (widget.runningOnDesktop) {
        widget.setShowHidePage!(
            PageType.items, false, PageParams(group: categoryGroup.group));
      }
    } else {
      categoryGroup.category!.archivedAt =
          DateTime.now().toUtc().millisecondsSinceEpoch;
      await categoryGroup.category!.update(["archived_at"]);
    }
    _categoriesGroupsDisplayList.remove(categoryGroup);
    if (mounted) {
      setState(() {});
      if (mounted) {
        displaySnackBar(context, message: "Moved to trash", seconds: 1);
      }
    }
  }

  Future<void> editCategoryGroup(ModelCategoryGroup categoryGroup) async {
    if (categoryGroup.type == "group") {
      ModelGroup group = categoryGroup.group!;
      if (widget.runningOnDesktop) {
        widget.setShowHidePage!(
            PageType.addEditGroup, true, PageParams(group: group));
      } else {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => PageGroupAddEdit(
            runningOnDesktop: widget.runningOnDesktop,
            setShowHidePage: widget.setShowHidePage,
            group: group,
          ),
          settings: const RouteSettings(name: "EditNoteGroup"),
        ));
      }
    } else {
      ModelCategory category = categoryGroup.category!;
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
  }

  Future<void> _saveGroupPositions() async {
    for (ModelCategoryGroup categoryGroup in _categoriesGroupsDisplayList) {
      int position = _categoriesGroupsDisplayList.indexOf(categoryGroup);
      categoryGroup.position = position;
      if (categoryGroup.type == "group") {
        final ModelGroup group = categoryGroup.group!;
        group.position = position;
        await group.update(["position"]);
      } else {
        final ModelCategory category = categoryGroup.category!;
        category.position = position;
        await category.update(["position"]);
      }
    }
  }

  Future<void> checkShowReviewDialog() async {
    if (ModelSetting.get(AppString.reviewDialogShown.string, "no") == "no") {
      int now = DateTime.now().toUtc().millisecondsSinceEpoch;
      int installedAt = int.parse(
          ModelSetting.get(AppString.installedAt.string, "0").toString());
      int timeSpent = 10 * 60 * 1000;
      if (isDebugEnabled) {
        timeSpent = 1 * 60 * 1000;
      }
      if (now - installedAt > timeSpent) {
        await ModelSetting.set(AppString.reviewDialogShown.string, "yes");
        _showForkInfoDialog();
      }
    }
  }

  // ── Shared icon badge (monochromatic, matches settings page) ──────────────
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

  // ── Popup menu item (monochromatic icon, consistent across both pages) ────
  Widget _menuItem({
    required BuildContext context,
    required int value,
    required IconData icon,
    required String label,
    bool isDanger = false,
    bool extraTopRadius = false,
    bool extraBottomRadius = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = isDanger ? cs.error : cs.onSurfaceVariant;
    final textColor = isDanger ? cs.error : cs.onSurface;
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
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(extraTopRadius ? 9 : 7),
                        topRight: Radius.circular(7),
                        bottomLeft: Radius.circular(extraBottomRadius ? 9 : 7),
                        bottomRight: Radius.circular(7),
                      ),
                    ),
                    child: Icon(icon, size: 16, color: iconColor),
                  ),
                  const SizedBox(width: 12),
                  Text(label, style: TextStyle(fontSize: 14, color: textColor)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showForkInfoDialog() {
    if (mounted) {
      final cs = Theme.of(context).colorScheme;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            backgroundColor: cs.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(LucideIcons.gitFork, size: 20, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'About This App',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: "Close",
                  icon:
                      Icon(LucideIcons.x, size: 18, color: cs.onSurfaceVariant),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fork notice
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.2),
                        width: 0.75,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.info, size: 16, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This is a modern fork with Material You support',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Original app credit
                  Text(
                    'Based on the original app by jeerovan',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Improvements
                  Text(
                    'What\'s New:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _forkFeature(cs, '✨', 'Material You theming'),
                  _forkFeature(cs, '🎨', 'Refined modern UI'),
                  _forkFeature(cs, '🧩', 'Enhanced components'),
                  _forkFeature(cs, '⚡', 'Better performance'),
                  const SizedBox(height: 12),
                  // Privacy note
                  Text(
                    '$appName is completely private. No data collection, no ads.',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: cs.onSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  const url = 'https://github.com/jeerovan/ntsapp';
                  openURL(url);
                },
                child: const Text('Original'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: cs.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  const url = 'https://github.com/FarhanZafarr-9/ntsapp';
                  openURL(url);
                },
                child: const Text('View Fork'),
              ),
            ],
          );
        },
      );
    }
  }

  Widget _forkFeature(ColorScheme cs, String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> navigateToOnboardCheck() async {
    if (widget.runningOnDesktop) {
      widget.setShowHidePage!(
          PageType.userTask, true, PageParams(appTask: AppTask.checkCloudSync));
    } else {
      Navigator.of(context).push(
        AnimatedPageRoute(
          child: PageUserTask(
            runningOnDesktop: widget.runningOnDesktop,
            setShowHidePage: widget.setShowHidePage,
            task: AppTask.checkCloudSync,
          ),
        ),
      );
    }
  }

  Future<void> navigateToPlanStatus() async {
    if (widget.runningOnDesktop) {
      widget.setShowHidePage!(PageType.planStatus, true, PageParams());
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PagePlanStatus(
            runningOnDesktop: widget.runningOnDesktop,
            setShowHidePage: widget.setShowHidePage,
          ),
        ),
      );
    }
  }

  Future<void> onExitSettings() async {
    String todayDate = getTodayDate();
    Directory baseDir = await getApplicationDocumentsDirectory();
    String? backupDir = await secureStorage.read(key: "backup_dir");
    final String zipFilePath =
        path.join(baseDir.path, '${backupDir}_$todayDate.zip');
    File backupFile = File(zipFilePath);
    try {
      if (backupFile.existsSync()) backupFile.deleteSync();
    } catch (e, s) {
      logger.error("DeleteBackupOnExitSettings", error: e, stackTrace: s);
    }
    if (ModelSetting.get("local_auth", "no") == "no") {
      requiresAuthentication = false;
      await loadCategoriesGroups();
    } else if (!requiresAuthentication || isAuthenticated) {
      await loadCategoriesGroups();
    }
    if (mounted) {
      setState(() {
        loggingEnabled =
            ModelSetting.get(AppString.loggingEnabled.string, "no") == "yes";
      });
    }
  }

  Future<void> hideSyncButton() async {
    await ModelSetting.set(AppString.hideSyncButton.string, "yes");
    setState(() {});
  }

  List<Widget> _buildDefaultActions() {
    final cs = Theme.of(context).colorScheme;
    bool supabaseInitialized =
        ModelSetting.get(AppString.supabaseInitialized.string, "no") == "yes";
    bool showSync =
        ModelSetting.get(AppString.hideSyncButton.string, "no") == "no";
    return [
      if (supabaseInitialized &&
          (!requiresAuthentication || isAuthenticated) &&
          !_canSync &&
          showSync)
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: TextButton(
            style: TextButton.styleFrom(
              backgroundColor: cs.onSurface.withValues(alpha: 0.06),
              foregroundColor: cs.onSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
              textStyle: const TextStyle(fontSize: 13),
            ),
            onPressed: navigateToOnboardCheck,
            onLongPress: hideSyncButton,
            child: const Text("Sync"),
          ),
        ),
      if (!requiresAuthentication || isAuthenticated)
        IconButton(
          tooltip: "Search notes",
          icon: _buildIconBadge(LucideIcons.search),
          onPressed: () {
            if (widget.runningOnDesktop) {
              widget.setShowHidePage!(PageType.search, true, PageParams());
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => SearchPage(
                  runningOnDesktop: widget.runningOnDesktop,
                  setShowHidePage: widget.setShowHidePage,
                ),
                settings: const RouteSettings(name: "SearchNotes"),
              ));
            }
          },
        ),
      IconButton(
        tooltip: "About this fork",
        icon: _buildIconBadge(LucideIcons.gitFork),
        onPressed: _showForkInfoDialog,
      ),
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: PopupMenuButton<int>(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 240),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: cs.onSurface.withValues(alpha: 0.1),
              width: 0.75,
            ),
          ),
          color: cs.surfaceContainerLowest,
          elevation: 4,
          icon: Stack(
            children: [
              _buildIconBadge(LucideIcons.moreVertical),
              if (!hasValidPlan)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: cs.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          onSelected: (value) {
            switch (value) {
              case 0:
                if (widget.runningOnDesktop) {
                  widget.setShowHidePage!(
                      PageType.settings,
                      true,
                      PageParams(
                          isAuthenticated:
                              !requiresAuthentication || isAuthenticated));
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsPage(
                        runningOnDesktop: widget.runningOnDesktop,
                        setShowHidePage: widget.setShowHidePage,
                        isDarkMode: widget.isDarkMode,
                        onThemeToggle: widget.onThemeToggle,
                        useDynamicColor: widget.useDynamicColor,
                        onDynamicColorToggle: widget.onDynamicColorToggle,
                        accentColor: widget.accentColor,
                        onAccentColorChange: widget.onAccentColorChange,
                        canShowBackupRestore:
                            !requiresAuthentication || isAuthenticated,
                      ),
                      settings: const RouteSettings(name: "Settings"),
                    ),
                  ).then((_) {
                    onExitSettings();
                  });
                }
                break;
              case 1:
                if (widget.runningOnDesktop) {
                  widget.setShowHidePage!(PageType.starred, true, PageParams());
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PageStarredItems(
                        runningOnDesktop: widget.runningOnDesktop,
                        setShowHidePage: widget.setShowHidePage,
                      ),
                      settings: const RouteSettings(name: "StarredNotes"),
                    ),
                  );
                }
                break;
              case 2:
                if (widget.runningOnDesktop) {
                  widget.setShowHidePage!(PageType.archive, true, PageParams());
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PageArchived(
                        runningOnDesktop: widget.runningOnDesktop,
                        setShowHidePage: widget.setShowHidePage,
                      ),
                      settings: const RouteSettings(name: "Trash"),
                    ),
                  );
                }
                break;
              case 3:
                if (_canSync) {
                  SyncUtils.waitAndSyncChanges(manualSync: true);
                } else {
                  navigateToOnboardCheck();
                }
                break;
              case 4:
                navigateToPlanStatus();
                break;
              case 11:
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => PageDummy(),
                  settings: const RouteSettings(name: "DummyPage"),
                ));
                break;
              case 12:
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => PageSqlite(),
                  settings: const RouteSettings(name: "SqlitePage"),
                ));
                break;
              case 14:
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => PageLogs(),
                  settings: const RouteSettings(name: "PageLogs"),
                ));
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<int>(
              value: 3,
              padding: EdgeInsets.zero,
              height: 0,
              child: _menuItem(
                context: context,
                value: 3,
                icon: LucideIcons.refreshCcw,
                label: "Sync",
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
            if (!requiresAuthentication || isAuthenticated)
              PopupMenuItem<int>(
                value: 2,
                padding: EdgeInsets.zero,
                height: 0,
                child: _menuItem(
                    context: context,
                    value: 2,
                    icon: LucideIcons.archiveRestore,
                    label: "Trash"),
              ),
            if (!requiresAuthentication || isAuthenticated)
              PopupMenuItem<int>(
                value: 1,
                padding: EdgeInsets.zero,
                height: 0,
                child: _menuItem(
                    context: context,
                    value: 1,
                    icon: LucideIcons.star,
                    label: "Starred notes"),
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
              value: 0,
              padding: EdgeInsets.zero,
              height: 0,
              child: _menuItem(
                  context: context,
                  value: 0,
                  icon: LucideIcons.settings,
                  label: "Settings"),
            ),
            if (SyncUtils.getSignedInUserId() != null)
              PopupMenuItem<int>(
                value: 4,
                padding: EdgeInsets.zero,
                height: 0,
                child: _menuItem(
                  context: context,
                  value: 4,
                  icon: hasValidPlan
                      ? LucideIcons.shield
                      : LucideIcons.alertTriangle,
                  label: "Account",
                  isDanger: !hasValidPlan,
                ),
              ),
            if (isDebugEnabled)
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
            if (isDebugEnabled)
              PopupMenuItem<int>(
                value: 11,
                padding: EdgeInsets.zero,
                height: 0,
                child: _menuItem(
                    context: context,
                    value: 11,
                    icon: LucideIcons.file,
                    label: "Page"),
              ),
            if (isDebugEnabled)
              PopupMenuItem<int>(
                value: 12,
                padding: EdgeInsets.zero,
                height: 0,
                child: _menuItem(
                  context: context,
                  value: 12,
                  icon: LucideIcons.database,
                  label: "Sqlite",
                  extraBottomRadius: !loggingEnabled,
                ),
              ),
            if (loggingEnabled)
              PopupMenuItem<int>(
                value: 14,
                padding: EdgeInsets.zero,
                height: 0,
                child: _menuItem(
                  context: context,
                  value: 14,
                  icon: LucideIcons.list,
                  label: "Logs",
                  extraBottomRadius: true,
                ),
              ),
          ],
        ),
      ),
    ];
  }

  // ── Bottom sheet for long-press options ───────────────────────────────────
  void _showOptions(BuildContext context, ModelCategoryGroup categoryGroup) {
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
                _bottomSheetTile(
                  context: context,
                  icon: Icons.reorder,
                  label: 'Reorder',
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _isReordering = true);
                  },
                ),
                const SizedBox(height: 3),
                _bottomSheetTile(
                  context: context,
                  icon: LucideIcons.edit3,
                  label: 'Edit',
                  onTap: () {
                    Navigator.pop(context);
                    editCategoryGroup(categoryGroup);
                  },
                ),
                const SizedBox(height: 3),
                if (categoryGroup.type == "group")
                  _bottomSheetTile(
                    context: context,
                    icon: categoryGroup.group!.pinned == 1
                        ? LucideIcons.pinOff
                        : LucideIcons.pin,
                    label: categoryGroup.group!.pinned == 1
                        ? 'Unpin from Shortcut'
                        : 'Pin to Shortcut',
                    onTap: () async {
                      Navigator.pop(context);
                      categoryGroup.group!.pinned =
                          categoryGroup.group!.pinned == 1 ? 0 : 1;
                      await categoryGroup.group!.update(["pinned"]);
                    },
                  ),
                if (categoryGroup.type == "group") const SizedBox(height: 3),
                _bottomSheetTile(
                  context: context,
                  icon: LucideIcons.trash,
                  label: 'Delete',
                  isDanger: true,
                  onTap: () {
                    Navigator.pop(context);
                    archiveCategoryGroup(categoryGroup);
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

  /// Single tile used inside bottom sheets — same monochromatic icon style.
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
      color: cs.onSurface.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
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

  void _showExitDialog() {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(LucideIcons.logOut, size: 22, color: cs.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Leaving already?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to exit? Your notes are secure and ready for your return.',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              // Concise Fork Info Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.15),
                    width: 0.75,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.sparkles, size: 16, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Better by Design. This fork brings modern Material 3 and a refined aesthetic to your private space.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: const Text('Stay'),
            ),
            ElevatedButton(
              onPressed: () =>
                  SystemChannels.platform.invokeMethod('SystemNavigator.pop'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Exit'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (selectedGroup != widget.selectedGroup) {
      selectedGroup = widget.selectedGroup;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (_isReordering) {
          setState(() => _isReordering = false);
        } else {
          _showExitDialog();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isReordering
                ? "Reordering"
                : loadedSharedContents || widget.sharedContents.isEmpty
                    ? appName!
                    : "Select...",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          actions: _buildDefaultActions(),
        ),
        body: _isReordering
            ? ReorderableListView.builder(
                itemCount: _categoriesGroupsDisplayList.length,
                itemBuilder: (context, index) {
                  final item = _categoriesGroupsDisplayList[index];
                  return GestureDetector(
                    key: ValueKey(item.id),
                    onTap: () {
                      String dragTitle = "Drag handle to re-order";
                      if (Platform.isAndroid || Platform.isIOS) {
                        dragTitle = "Hold and drag to re-order";
                      }
                      displaySnackBar(context, message: dragTitle, seconds: 1);
                    },
                    child: WidgetCategoryGroup(
                      categoryGroup: item,
                      showSummary: true,
                      showCategorySign: false,
                    ),
                  );
                },
                onReorder: (int oldIndex, int newIndex) {
                  setState(() {
                    if (oldIndex < newIndex) newIndex -= 1;
                    final item =
                        _categoriesGroupsDisplayList.removeAt(oldIndex);
                    _categoriesGroupsDisplayList.insert(newIndex, item);
                    _saveGroupPositions();
                  });
                },
              )
            : _isLoading
                ? const ShimmerList()
                : _isFetchingFromServer
                    ? const Center(child: CircularProgressIndicator())
                    : _categoriesGroupsDisplayList.isNotEmpty
                        ? RefreshIndicator(
                            onRefresh: () async => loadCategoriesGroups(),
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              itemCount: _categoriesGroupsDisplayList.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 3),
                              itemBuilder: (context, index) {
                                final ModelCategoryGroup item =
                                    _categoriesGroupsDisplayList[index];
                                final bool isSelected = item.type == "group" &&
                                    selectedGroup != null &&
                                    selectedGroup!.id == item.group!.id;

                                return Material(
                                  color: isSelected
                                      ? cs.onSurface.withValues(alpha: 0.1)
                                      : cs.onSurface.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => navigateToNotesOrGroups(item),
                                    onLongPress: () =>
                                        _showOptions(context, item),
                                    child: WidgetCategoryGroup(
                                      categoryGroup: item,
                                      showSummary: true,
                                      showCategorySign: true,
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color:
                                          cs.onSurface.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      LucideIcons.edit3,
                                      size: 28,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    "Nothing here yet",
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Tap + to create your first note group.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
        floatingActionButton: !requiresAuthentication || isAuthenticated
            ? FloatingActionButton(
                heroTag: "add_group_or_mark_reordering_complete",
                onPressed: () {
                  if (_isReordering) {
                    setState(() => _isReordering = false);
                  } else {
                    createNoteGroup();
                  }
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child:
                    Icon(_isReordering ? LucideIcons.check : LucideIcons.plus),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
