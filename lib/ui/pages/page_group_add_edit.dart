import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ntsapp/utils/enums.dart';
import 'package:ntsapp/models/model_category.dart';
import 'package:ntsapp/models/model_category_group.dart';
import 'package:ntsapp/ui/pages/page_add_select_category.dart';
import 'package:ntsapp/services/service_events.dart';

import '../../utils/common.dart';
import '../common_widgets.dart';
import '../../models/model_item_group.dart';
import '../../models/model_setting.dart';


class PageGroupAddEdit extends StatefulWidget {
  final bool runningOnDesktop;
  final Function(PageType, bool, PageParams)? setShowHidePage;
  final ModelGroup? group;
  final ModelCategory? category;

  const PageGroupAddEdit({
    super.key,
    this.group,
    this.category,
    required this.runningOnDesktop,
    required this.setShowHidePage,
  });

  @override
  PageGroupAddEditState createState() => PageGroupAddEditState();
}

class PageGroupAddEditState extends State<PageGroupAddEdit> {
  final TextEditingController titleController = TextEditingController();

  bool processing = false;
  bool itemChanged = false;

  bool showDate = true;
  bool showTime = true;
  bool showNoteBorder = false;
  bool linkPreview = true;
  bool sortOldestFirst = false;
  bool mediaGallery = false;
  bool groupLock = false;
  bool privacyShield = false;

  String title = "";
  Uint8List? thumbnail;
  String? colorCode;
  String? icon;
  ModelCategory? category;
  String dateTitle = getNoteGroupDateTitle();
  Map<String, dynamic>? groupData;

  ModelCategory? previousCategory;

  @override
  void initState() {
    super.initState();
    init();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> init() async {
    if (widget.group == null) {
      itemChanged = true;
      await setColorCode();
    } else {
      category = await ModelCategory.get(widget.group!.categoryId);
      previousCategory = category;
      colorCode = widget.group!.color;
      groupData = widget.group!.data;
      icon = widget.group!.icon;
      if (groupData != null) {
        if (groupData!.containsKey("show_date")) {
          showDate = groupData!["show_date"] == 1;
        }
        if (groupData!.containsKey("show_time")) {
          showTime = groupData!["show_time"] == 1;
        }
        // Compatibility for old "date_time" key
        if (groupData!.containsKey("date_time")) {
          bool val = groupData!["date_time"] == 1;
          showDate = val;
          showTime = val;
        }
        if (groupData!.containsKey("note_border")) {
          int noteBorderInt = groupData!["note_border"];
          showNoteBorder = noteBorderInt == 1;
        }
        if (groupData!.containsKey("link_preview")) {
          linkPreview = groupData!["link_preview"] == 1;
        }
        if (groupData!.containsKey("sort_order")) {
          sortOldestFirst = groupData!["sort_order"] == 1;
        }
        if (groupData!.containsKey("media_gallery")) {
          mediaGallery = groupData!["media_gallery"] == 1;
        }
        if (groupData!.containsKey("group_lock")) {
          groupLock = groupData!["group_lock"] == 1;
        }
        if (groupData!.containsKey("privacy_shield")) {
          privacyShield = groupData!["privacy_shield"] == 1;
        }
      }
    }

    if (mounted) {
      setState(() {
        title = widget.group == null ? dateTitle : widget.group!.title;
        titleController.text = title;
        thumbnail = widget.group?.thumbnail;
      });
    }
  }

  Future<void> setColorCode() async {
    itemChanged = true;
    int positionCount = await ModelCategoryGroup.getCategoriesGroupsCount();
    if (widget.category == null) {
      category = await ModelCategory.getDND();
    } else {
      category = widget.category;
      positionCount = await ModelGroup.getCountInCategory(category!.id!);
    }
    previousCategory = category;
    Color color = getIndexedColor(positionCount);

    if (mounted) {
      setState(() {
        colorCode = colorToHex(color);
      });
    }
  }

  Future<void> pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
      maxHeight: 400,
    );

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        thumbnail = bytes;
        icon = null; // Clear emoji if picture is picked
        itemChanged = true;
      });
    }
  }

  Future<void> pickEmoji() async {
    String? pickedEmoji = await showDialog<String>(
      context: context,
      builder: (context) => const WidgetEmojiPicker(),
    );

    if (pickedEmoji != null) {
      setState(() {
        icon = pickedEmoji;
        thumbnail = null; // Clear picture if emoji is picked
        itemChanged = true;
      });
    }
  }

  Future<void> saveGroup(String text) async {
    title = text.trim();
    if (title.isEmpty) return;
    if (category == null) return;
    String categoryId = category!.id!;
    ModelGroup? newGroup;
    if (itemChanged && title.isNotEmpty) {
      if (widget.group == null) {
        newGroup = await ModelGroup.fromMap({
          "category_id": categoryId,
          "thumbnail": thumbnail,
          "title": title,
          "data": groupData,
          "color": colorCode,
          "icon": icon,
        });
        await newGroup.insert();

        EventStream().publish(
            AppEvent(type: EventType.changedGroupId, value: newGroup.id));
        if (widget.runningOnDesktop) {
          widget.setShowHidePage!(
              PageType.items, true, PageParams(group: newGroup));
        }
      } else {
        bool shouldUpdateHome = widget.group!.categoryId != categoryId;
        widget.group!.thumbnail = thumbnail;
        widget.group!.title = title;
        widget.group!.categoryId = categoryId;
        widget.group!.color = colorCode ?? widget.group!.color;
        widget.group!.data = groupData;
        widget.group!.icon = icon;
        await widget.group!
            .update(["thumbnail", "title", "category_id", "color", "data", "icon"]);

        EventStream().publish(
            AppEvent(type: EventType.changedGroupId, value: widget.group!.id));
        if (shouldUpdateHome) {
          await signalToUpdateHome();
        }
      }
      if (widget.runningOnDesktop) {
        widget.setShowHidePage!(PageType.addEditGroup, false, PageParams());
      }
    }
    if (!widget.runningOnDesktop && mounted) {
      Navigator.of(context).pop(newGroup);
    }
  }

  void addToCategory() {
    if (widget.runningOnDesktop) {
      widget.setShowHidePage!(PageType.categories, true, PageParams());
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute(
        builder: (context) => PageAddSelectCategory(
          runningOnDesktop: widget.runningOnDesktop,
          setShowHidePage: widget.setShowHidePage,
        ),
        settings: const RouteSettings(name: "SelectGroupCategory"),
      ))
          .then((value) async {
        String? categoryId = value;
        if (categoryId != null) {
          category = await ModelCategory.get(categoryId);
          itemChanged = true;
          if (mounted) setState(() {});
        }
      });
    }
  }

  Future<void> removeCategory() async {
    category = await ModelCategory.getDND();
    if (mounted) {
      setState(() {
        itemChanged = true;
      });
    }
  }

  Future<void> archiveGroup(ModelGroup group) async {
    group.archivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    await group.update(["archived_at"]);
    EventStream()
        .publish(AppEvent(type: EventType.changedGroupId, value: group.id));
    if (widget.runningOnDesktop) {
      widget.setShowHidePage!(PageType.addEditGroup, false, PageParams());
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> setShowDate(bool show) async {
    itemChanged = true;
    setState(() {
      showDate = show;
    });
    int val = showDate ? 1 : 0;
    if (groupData != null) {
      groupData!["show_date"] = val;
    } else {
      groupData = {"show_date": val};
    }
  }

  Future<void> setShowTime(bool show) async {
    itemChanged = true;
    setState(() {
      showTime = show;
    });
    int val = showTime ? 1 : 0;
    if (groupData != null) {
      groupData!["show_time"] = val;
    } else {
      groupData = {"show_time": val};
    }
  }

  Future<void> setShowNoteBorder(bool show) async {
    itemChanged = true;
    setState(() {
      showNoteBorder = show;
    });
    int showBorder = showNoteBorder ? 1 : 0;
    if (groupData != null) {
      groupData!["note_border"] = showBorder;
    } else {
      groupData = {"note_border": showBorder};
    }
  }

  Future<void> setLinkPreview(bool value) async {
    itemChanged = true;
    setState(() => linkPreview = value);
    int v = linkPreview ? 1 : 0;
    if (groupData != null) {
      groupData!["link_preview"] = v;
    } else {
      groupData = {"link_preview": v};
    }
  }

  Future<void> setSortOrder(bool oldestFirst) async {
    itemChanged = true;
    setState(() => sortOldestFirst = oldestFirst);
    int v = sortOldestFirst ? 1 : 0;
    if (groupData != null) {
      groupData!["sort_order"] = v;
    } else {
      groupData = {"sort_order": v};
    }
  }

  Future<void> setMediaGallery(bool value) async {
    itemChanged = true;
    setState(() => mediaGallery = value);
    int v = mediaGallery ? 1 : 0;
    if (groupData != null) {
      groupData!["media_gallery"] = v;
    } else {
      groupData = {"media_gallery": v};
    }
  }

  Future<void> setGroupLock(bool value) async {
    itemChanged = true;
    setState(() => groupLock = value);
    int v = groupLock ? 1 : 0;
    if (groupData != null) {
      groupData!["group_lock"] = v;
    } else {
      groupData = {"group_lock": v};
    }
  }

  Future<void> setPrivacyShield(bool value) async {
    itemChanged = true;
    setState(() => privacyShield = value);
    int v = privacyShield ? 1 : 0;
    if (groupData != null) {
      groupData!["privacy_shield"] = v;
    } else {
      groupData = {"privacy_shield": v};
    }
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _tappableTile({
    required BuildContext context,
    required VoidCallback onTap,
    required Widget leading,
    required String label,
    Widget? trailing,
    Color? labelColor,
    Color? tileColor,
    bool useTransparent = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: useTransparent
          ? Colors.transparent
          : tileColor ?? cs.onSurface.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                      fontSize: 14, color: labelColor ?? cs.onSurface),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsToggleTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool value,
    required Function(bool) onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 14, color: cs.onSurface)),
            ),
            Transform.scale(
                scale: 0.8, child: Switch(value: value, onChanged: onChanged)),
          ],
        ),
      ),
    );
  }

  Widget _buildLeadingIcon(IconData icon, {Color? color}) {
    final cs = Theme.of(context).colorScheme;
    final themeColor = color ?? cs.onSurfaceVariant;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: themeColor),
    );
  }

  Widget _collapsibleSection({
    required BuildContext context,
    required String label,
    required IconData icon,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16), side: BorderSide.none),
          collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16), side: BorderSide.none),
          visualDensity: VisualDensity.compact,
          initiallyExpanded: false,
          leading: Icon(icon, size: 18, color: cs.primary),
          title: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: children,
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.category != null &&
        widget.category != previousCategory &&
        category != widget.category) {
      setColorCode();
    }
    String pageTitle = widget.group == null ? "Add group" : "Edit group";
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          pageTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: widget.runningOnDesktop
            ? BackButton(
                onPressed: () {
                  widget.setShowHidePage!(
                      PageType.addEditGroup, false, PageParams());
                },
              )
            : null,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: WidgetCategoryGroupAvatar(
                  type: "group",
                  size: 80,
                  color: colorCode ?? "#06b6d4",
                  title: title,
                  thumbnail: thumbnail,
                  icon: icon,
                ),
              ),
              const SizedBox(height: 32),
              _sectionLabel("Title"),
              const SizedBox(height: 8),
              TextField(
                controller: titleController,
                textCapitalization: TextCapitalization.sentences,
                autofocus: false,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                textInputAction: TextInputAction.done,
                onSubmitted: saveGroup,
                decoration: InputDecoration(
                  hintText: 'Group title',
                  hintStyle: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.5),
                      fontWeight: FontWeight.w400),
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.15),
                        width: 0.75),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onChanged: (value) {
                  title = value.trim();
                  itemChanged = true;
                },
              ),
              const SizedBox(height: 24),
              _collapsibleSection(
                context: context,
                label: "Identity",
                icon: LucideIcons.fingerprint,
                children: [
                  _tappableTile(
                    context: context,
                    useTransparent: true,
                    onTap: () async {
                      Color? pickedColor = await showDialog<Color>(
                        context: context,
                        builder: (context) =>
                            ColorPickerDialog(color: colorCode),
                      );
                      if (pickedColor != null) {
                        setState(() {
                          itemChanged = true;
                          colorCode = colorToHex(pickedColor);
                        });
                      }
                    },
                    leading: _buildLeadingIcon(
                      LucideIcons.palette,
                      color: colorFromHex(colorCode ?? "#00BCD4"),
                    ),
                    label: "Change theme color",
                    trailing: (thumbnail == null && icon == null)
                        ? Icon(LucideIcons.checkCircle2,
                            size: 18, color: cs.primary)
                        : null,
                  ),
                  _tappableTile(
                    context: context,
                    useTransparent: true,
                    onTap: pickEmoji,
                    leading: _buildLeadingIcon(LucideIcons.smile),
                    label: "Pick an emoji",
                    trailing: icon != null
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(icon!,
                                  style: const TextStyle(fontSize: 16)),
                              const SizedBox(width: 8),
                              Icon(LucideIcons.checkCircle2,
                                  size: 18, color: cs.primary),
                            ],
                          )
                        : null,
                  ),
                  _tappableTile(
                    context: context,
                    useTransparent: true,
                    onTap: pickImage,
                    leading: _buildLeadingIcon(LucideIcons.image),
                    label: "Upload a picture",
                    trailing: thumbnail != null
                        ? Icon(LucideIcons.checkCircle2,
                            size: 18, color: cs.primary)
                        : null,
                  ),
                  if (thumbnail != null || icon != null)
                    _tappableTile(
                      context: context,
                      useTransparent: true,
                      onTap: () {
                        setState(() {
                          thumbnail = null;
                          icon = null;
                          itemChanged = true;
                        });
                      },
                      leading: _buildLeadingIcon(LucideIcons.trash2, color: cs.error),
                      label: "Reset to default icon",
                      labelColor: cs.error,
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _sectionLabel("Category"),
              const SizedBox(height: 8),
              _tappableTile(
                context: context,
                onTap: addToCategory,
                leading: Icon(
                  LucideIcons.folder,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                label: (category == null || category!.title == "DND")
                    ? "Select category"
                    : category!.title,
                trailing: (category != null && category!.title != "DND")
                    ? GestureDetector(
                        onTap: removeCategory,
                        child: Icon(
                          LucideIcons.x,
                          size: 16,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.6),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 24),
              _sectionLabel("Group Settings"),
              const SizedBox(height: 12),
              _collapsibleSection(
                context: context,
                label: "Appearance",
                icon: LucideIcons.palette,
                children: [
                  _settingsToggleTile(
                    context: context,
                    icon: LucideIcons.calendar,
                    label: 'Show Dates',
                    value: showDate,
                    onChanged:
                        ModelSetting.get("use_group_settings", "yes") == "yes"
                            ? setShowDate
                            : (v) {},
                  ),
                  _settingsToggleTile(
                    context: context,
                    icon: LucideIcons.clock,
                    label: 'Show Time Pills',
                    value: showTime,
                    onChanged:
                        ModelSetting.get("use_group_settings", "yes") == "yes"
                            ? setShowTime
                            : (v) {},
                  ),
                  _settingsToggleTile(
                    context: context,
                    icon: LucideIcons.rectangleHorizontal,
                    label: 'Note border',
                    value: showNoteBorder,
                    onChanged:
                        ModelSetting.get("use_group_settings", "yes") == "yes"
                            ? setShowNoteBorder
                            : (v) {},
                  ),
                  _settingsToggleTile(
                    context: context,
                    icon: LucideIcons.link,
                    label: 'Link previews',
                    value: linkPreview,
                    onChanged:
                        ModelSetting.get("use_group_settings", "yes") == "yes"
                            ? setLinkPreview
                            : (v) {},
                  ),
                ],
              ),
              _collapsibleSection(
                context: context,
                label: "Layout & Preferences",
                icon: LucideIcons.layers,
                children: [
                  _settingsToggleTile(
                    context: context,
                    icon: LucideIcons.arrowUpDown,
                    label: 'Oldest first',
                    value: sortOldestFirst,
                    onChanged:
                        ModelSetting.get("use_group_settings", "yes") == "yes"
                            ? setSortOrder
                            : (v) {},
                  ),
                  _settingsToggleTile(
                    context: context,
                    icon: LucideIcons.layoutGrid,
                    label: 'Media gallery',
                    value: mediaGallery,
                    onChanged:
                        ModelSetting.get("use_group_settings", "yes") == "yes"
                            ? setMediaGallery
                            : (v) {},
                  ),
                ],
              ),
              _collapsibleSection(
                context: context,
                label: "Security & Privacy",
                icon: LucideIcons.shieldCheck,
                children: [
                  _settingsToggleTile(
                    context: context,
                    icon: LucideIcons.lock,
                    label: 'Group lock',
                    value: groupLock,
                    onChanged:
                        ModelSetting.get("use_group_settings", "yes") == "yes"
                            ? setGroupLock
                            : (v) {},
                  ),
                  _settingsToggleTile(
                    context: context,
                    icon: LucideIcons.eyeOff,
                    label: 'Privacy shield',
                    value: privacyShield,
                    onChanged:
                        ModelSetting.get("use_group_settings", "yes") == "yes"
                            ? setPrivacyShield
                            : (v) {},
                  ),
                ],
              ),
              if (ModelSetting.get("use_group_settings", "yes") != "yes") ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    "These settings are currently controlled globally from Settings.",
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (widget.group != null)
                _tappableTile(
                  context: context,
                  onTap: () => archiveGroup(widget.group!),
                  leading: Icon(
                    LucideIcons.trash,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  label: 'Delete group',
                  labelColor: Theme.of(context).colorScheme.error,
                  tileColor:
                      Theme.of(context).colorScheme.error.withValues(alpha: 0.06),
                ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: "save_new_group",
        onPressed: () async => saveGroup(titleController.text),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 4,
        child: Icon(widget.group == null ? Icons.arrow_forward : Icons.check),
      ),
    );
  }
}
