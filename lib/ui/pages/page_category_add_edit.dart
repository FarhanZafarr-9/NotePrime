import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
        category = category;
        thumbnail = category!.thumbnail;
        title = category!.title;
        categoryController.text = category!.title;
        colorCode = category!.color;
      });
    } else {
      int positionCount = await ModelCategoryGroup.getCategoriesGroupsCount();
      Color color = getIndexedColor(positionCount);
      setState(() {
        colorCode = colorToHex(color);
      });
    }
  }

  void saveCategory(String text) async {
    title = text.trim();
    if (title!.isEmpty) return;
    if (itemChanged) {
      if (category == null) {
        ModelCategory newCategory = await ModelCategory.fromMap(
            {"title": title, "color": colorCode, "thumbnail": thumbnail});
        await newCategory.insert();
        await signalToUpdateHome(); // update home list widget
      } else {
        category!.thumbnail = thumbnail;
        category!.title = title!;
        category!.color = colorCode ?? category!.color;
        await category!.update(["thumbnail", "title", "color"]);
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

  @override
  void dispose() {
    super.dispose();
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
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: tileColor ?? cs.onSurface.withValues(alpha: 0.06),
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
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel("Title"),
            const SizedBox(height: 8),
            TextField(
              controller: categoryController,
              textCapitalization: TextCapitalization.sentences,
              autofocus: category == null ? false : true,
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
            _sectionLabel("Color"),
            const SizedBox(height: 8),
            _tappableTile(
              context: context,
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
              leading: Icon(
                Icons.workspaces,
                size: 18,
                color: colorFromHex(colorCode ?? "#5dade2"),
              ),
              label: "Change color",
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: "save_new_category",
        onPressed: () => saveCategory(categoryController.text),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        backgroundColor: cs.onSurface.withValues(alpha: 0.1),
        foregroundColor: cs.onSurface,
        elevation: 0,
        child: const Icon(LucideIcons.check),
      ),
    );
  }
}
