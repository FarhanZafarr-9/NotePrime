import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ntsapp/utils/enums.dart';
import 'package:ntsapp/models/model_category_group.dart';
import 'package:ntsapp/services/service_events.dart';

import '../../utils/common.dart';
import '../common_widgets.dart';
import '../../models/model_category.dart';

class PageCategoryAddEdit extends StatefulWidget {
  final ModelCategory? category;
  final bool runningOnDesktop;
  final Function(PageType, bool, PageParams)? setShowHidePage;

  const PageCategoryAddEdit({
    super.key,
    this.category,
    required this.runningOnDesktop,
    this.setShowHidePage,
  });

  @override
  State<PageCategoryAddEdit> createState() => _PageCategoryAddEditState();
}

class _PageCategoryAddEditState extends State<PageCategoryAddEdit> {
  final TextEditingController categoryController = TextEditingController();

  ModelCategory? category;
  Uint8List? thumbnail;
  String? title;
  String? colorCode;
  String? icon;

  bool processing = false;
  bool itemChanged = false;

  @override
  void initState() {
    super.initState();
    category = widget.category;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      init();
    });
  }

  Future<void> init() async {
    if (category != null) {
      setState(() {
        thumbnail = category!.thumbnail;
        title = category!.title;
        categoryController.text = category!.title;
        colorCode = category!.color;
        icon = category!.icon;
      });
    } else {
      int positionCount = await ModelCategoryGroup.getCategoriesGroupsCount();
      Color color = getIndexedColor(positionCount);
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

  void saveCategory(String text) async {
    title = text.trim();
    if (title!.isEmpty) return;
    if (itemChanged) {
      if (category == null) {
        ModelCategory newCategory = await ModelCategory.fromMap({
          "title": title,
          "color": colorCode,
          "thumbnail": thumbnail,
          "icon": icon,
        });
        await newCategory.insert();
        await signalToUpdateHome();
      } else {
        category!.thumbnail = thumbnail;
        category!.title = title!;
        category!.color = colorCode ?? category!.color;
        category!.icon = icon;
        await category!.update(["thumbnail", "title", "color", "icon"]);
        EventStream().publish(
            AppEvent(type: EventType.changedCategoryId, value: category!.id));
      }
    }
    if (widget.runningOnDesktop) {
      widget.setShowHidePage!(PageType.addEditCategory, false, PageParams());
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

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

  @override
  Widget build(BuildContext context) {
    String task = category == null ? "Add" : "Edit";
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "$task category",
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: widget.runningOnDesktop
            ? BackButton(
                onPressed: () {
                  widget.setShowHidePage!(
                      PageType.addEditCategory, false, PageParams());
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
                  type: "category",
                  size: 80,
                  color: colorCode ?? "#06b6d4",
                  title: title ?? "",
                  thumbnail: thumbnail,
                  icon: icon,
                ),
              ),
              const SizedBox(height: 32),
              _sectionLabel("Title"),
              const SizedBox(height: 8),
              TextField(
                controller: categoryController,
                textCapitalization: TextCapitalization.sentences,
                autofocus: false,
                style: TextStyle(color: cs.onSurface, fontSize: 16),
                textInputAction: TextInputAction.done,
                onSubmitted: saveCategory,
                decoration: InputDecoration(
                  hintText: 'Category title',
                  hintStyle: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w400),
                  filled: true,
                  fillColor: cs.onSurface.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: cs.onSurface.withValues(alpha: 0.15), width: 0.75),
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
                        builder: (context) => ColorPickerDialog(
                          color: colorCode,
                        ),
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
                      color: colorFromHex(colorCode ?? "#5dade2"),
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
                      leading: _buildLeadingIcon(LucideIcons.trash2,
                          color: cs.error),
                      label: "Reset to default icon",
                      labelColor: cs.error,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: "save_new_category",
        onPressed: () => saveCategory(categoryController.text),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 4,
        child: const Icon(LucideIcons.check),
      ),
    );
  }
}
