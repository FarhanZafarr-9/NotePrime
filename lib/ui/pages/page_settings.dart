import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ntsapp/utils/backup_restore.dart';
import 'package:ntsapp/utils/enums.dart';
import 'package:ntsapp/models/model_setting.dart';
import 'package:ntsapp/services/service_events.dart';
import 'package:ntsapp/services/service_logger.dart';
import 'package:ntsapp/storage/storage_secure.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../utils/common.dart';
import '../common_widgets.dart';

class SettingsPage extends StatefulWidget {
  final bool isDarkMode;
  final bool useDynamicColor;
  final bool runningOnDesktop;
  final Function(PageType, bool, PageParams)? setShowHidePage;
  final VoidCallback onThemeToggle;
  final VoidCallback onDynamicColorToggle;
  final bool canShowBackupRestore;
  final Color? accentColor;
  final Function(Color)? onAccentColorChange;

  const SettingsPage(
      {super.key,
      required this.isDarkMode,
      required this.useDynamicColor,
      required this.onThemeToggle,
      required this.onDynamicColorToggle,
      required this.canShowBackupRestore,
      required this.runningOnDesktop,
      required this.setShowHidePage,
      this.accentColor,
      this.onAccentColorChange});

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  final logger = AppLogger(prefixes: ["page_settings"]);
  final LocalAuthentication _auth = LocalAuthentication();
  SecureStorage secureStorage = SecureStorage();
  bool isAuthSupported = false;
  bool isAuthEnabled = false;
  bool loggingEnabled =
      ModelSetting.get(AppString.loggingEnabled.string, "no") == "yes";
  String timeFormat = "H12";

  // Display Overrides
  late bool useGroupSettings;
  late bool globalShowDateTime;
  late bool globalShowNoteBorder;
  late bool globalLinkPreview;
  late bool globalSortOldestFirst;
  late bool globalMediaGallery;
  late bool globalGroupLock;
  late bool privacyShieldEnabled;

  @override
  void initState() {
    super.initState();
    timeFormat = ModelSetting.get(AppString.timeFormat.string, "H12");
    isAuthEnabled = ModelSetting.get("local_auth", "no") == "yes";

    // Initialize display overrides
    useGroupSettings = ModelSetting.get("use_group_settings", "yes") == "yes";
    globalShowDateTime =
        ModelSetting.get("global_show_date_time", "yes") == "yes";
    globalShowNoteBorder =
        ModelSetting.get("global_show_note_border", "yes") == "yes";
    globalLinkPreview =
        ModelSetting.get("global_link_preview", "yes") == "yes";
    globalSortOldestFirst =
        ModelSetting.get("global_sort_order", "newest") == "oldest";
    globalMediaGallery =
        ModelSetting.get("global_media_gallery", "no") == "yes";
    globalGroupLock =
        ModelSetting.get("global_group_lock", "no") == "yes";
    privacyShieldEnabled =
        ModelSetting.get("privacy_shield_enabled", "no") == "yes";
  }

  Future<void> checkDeviceAuth() async {
    isAuthSupported = await _auth.isDeviceSupported();
  }

  Future<void> setAuthSetting() async {
    isAuthEnabled = !isAuthEnabled;
    if (isAuthEnabled) {
      await ModelSetting.set("local_auth", "yes");
    } else {
      await ModelSetting.set("local_auth", "no");
    }
    if (mounted) setState(() {});
  }

  Future<void> _setUseGroupSettings(bool value) async {
    setState(() => useGroupSettings = value);
    await ModelSetting.set("use_group_settings", value ? "yes" : "no");
  }

  Future<void> _setGlobalShowDateTime(bool value) async {
    setState(() => globalShowDateTime = value);
    await ModelSetting.set("global_show_date_time", value ? "yes" : "no");
  }

  Future<void> _setGlobalShowNoteBorder(bool value) async {
    setState(() => globalShowNoteBorder = value);
    await ModelSetting.set("global_show_note_border", value ? "yes" : "no");
  }

  Future<void> _setGlobalLinkPreview(bool value) async {
    setState(() => globalLinkPreview = value);
    await ModelSetting.set("global_link_preview", value ? "yes" : "no");
  }

  Future<void> _setGlobalSortOrder(bool oldestFirst) async {
    setState(() => globalSortOldestFirst = oldestFirst);
    await ModelSetting.set(
        "global_sort_order", oldestFirst ? "oldest" : "newest");
  }

  Future<void> _setGlobalMediaGallery(bool value) async {
    setState(() => globalMediaGallery = value);
    await ModelSetting.set("global_media_gallery", value ? "yes" : "no");
  }

  Future<void> _setGlobalGroupLock(bool value) async {
    setState(() => globalGroupLock = value);
    await ModelSetting.set("global_group_lock", value ? "yes" : "no");
  }

  Future<void> _setPrivacyShield(bool value) async {
    setState(() => privacyShieldEnabled = value);
    await ModelSetting.set("privacy_shield_enabled", value ? "yes" : "no");
  }

  Future<void> _authenticate() async {
    try {
      bool isAuthenticated = await _auth.authenticate(
        localizedReason: 'Please authenticate',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );

      if (isAuthenticated) {
        setAuthSetting();
      }
    } catch (e, s) {
      logger.error("_authenticate", error: e, stackTrace: s);
    }
  }

  Future<void> _setLogging(bool enable) async {
    if (enable) {
      await ModelSetting.set(AppString.loggingEnabled.string, "yes");
    } else {
      await ModelSetting.set(AppString.loggingEnabled.string, "no");
    }
    if (mounted) {
      setState(() {
        loggingEnabled = enable;
      });
    }
  }

  Future<void> updateTimeFormat(String? newFormat) async {
    if (newFormat == null) return;
    await ModelSetting.set(AppString.timeFormat.string, newFormat);
    if (mounted) {
      setState(() {
        timeFormat = newFormat;
      });
    }
  }

  void showProcessing() {
    showProcessingDialog(context);
  }

  void hideProcessing() {
    Navigator.pop(context);
  }

  Future<void> createDownloadBackup() async {
    showProcessing();
    String status = "";
    Directory directory = await getApplicationDocumentsDirectory();
    String dirPath = directory.path;
    String today = getTodayDate();
    String? backupDir = await secureStorage.read(key: "backup_dir");
    String backupFilePath = path.join(dirPath, "${backupDir}_$today.zip");
    File backupFile = File(backupFilePath);
    if (!backupFile.existsSync()) {
      try {
        status = await createBackup(dirPath);
      } catch (e) {
        status = e.toString();
      }
    }
    hideProcessing();
    if (status.isNotEmpty) {
      if (mounted) showAlertMessage(context, "Could not create", status);
    } else {
      try {
        await Share.shareXFiles(
          [XFile(backupFilePath)],
          text: 'Here is the backup file for your app.',
        );
      } catch (e) {
        status = e.toString();
      }
      if (status.isNotEmpty) {
        if (mounted) showAlertMessage(context, "Could not share file", status);
      }
    }
  }

  Future<void> restoreZipBackup() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ["zip"],
    );
    if (result != null) {
      if (result.files.isNotEmpty) {
        Directory directory = await getApplicationDocumentsDirectory();
        String dirPath = directory.path;
        PlatformFile selectedFile = result.files[0];
        String? backupDir = await secureStorage.read(key: "backup_dir");
        String zipFilePath = selectedFile.path!;
        String error = "";
        if (selectedFile.name.startsWith("${backupDir}_")) {
          showProcessing();
          try {
            error = await restoreBackup({"dir": dirPath, "zip": zipFilePath});
          } catch (e) {
            error = e.toString();
          }
          hideProcessing();
          if (error.isNotEmpty) {
            if (mounted) showAlertMessage(context, "Error", error);
          }
        } else if (selectedFile.name.startsWith("NTS")) {
          showProcessing();
          try {
            error =
                await restoreOldBackup({"dir": dirPath, "zip": zipFilePath});
          } catch (e) {
            error = e.toString();
          }
          hideProcessing();
          if (error.isNotEmpty) {
            if (mounted) showAlertMessage(context, "Error", error);
          }
        }
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Monochromatic icon badge — uses the theme's onSurfaceVariant for both
  /// the icon tint and the container background (same as original design).
  Widget _buildLeadingIcon(IconData icon, Color color) {
    final themeColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: themeColor),
    );
  }

  Widget _buildTrailingChevron() {
    return Icon(
      LucideIcons.chevronRight,
      size: 16,
      color:
          Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0, top: 20.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  /// Wraps a list of tiles so that:
  ///   - first tile  → large top corners    (12), small bottom corners (5)
  ///   - last tile   → small top corners    (5),  large bottom corners (12)
  ///   - only tile   → large corners all around (12)
  ///   - middle tiles → small corners all around (5)
  ///
  /// Tiles are separated by a 3 px gap; no borders are drawn on any tile.
  Widget _buildSettingsGroup(List<_SettingsTile> tiles) {
    return Column(
      children: List.generate(tiles.length, (i) {
        final isFirst = i == 0;
        final isLast = i == tiles.length - 1;
        final isOnly = tiles.length == 1;

        const double large = 12;
        const double small = 5;

        final radius = BorderRadius.only(
          topLeft: Radius.circular(isFirst || isOnly ? large : small),
          topRight: Radius.circular(isFirst || isOnly ? large : small),
          bottomLeft: Radius.circular(isLast || isOnly ? large : small),
          bottomRight: Radius.circular(isLast || isOnly ? large : small),
        );

        final tile = tiles[i];

        return Column(
          children: [
            Material(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.06),
              borderRadius: radius,
              child: InkWell(
                borderRadius: radius,
                onTap: tile.enabled ? tile.onTap : null,
                child: Opacity(
                  opacity: tile.enabled ? 1.0 : 0.5,
                  child: ClipRRect(
                    borderRadius: radius,
                    child: ListTile(
                      leading: tile.leading,
                      title: tile.title,
                      subtitle: tile.subtitle,
                      trailing: tile.trailing,
                      enabled: tile.enabled,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!isLast) const SizedBox(height: 3),
          ],
        );
      }),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text("Settings"),
        centerTitle: true,
        backgroundColor: cs.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: widget.runningOnDesktop
            ? BackButton(
                onPressed: () async {
                  EventStream().publish(AppEvent(type: EventType.exitSettings));
                  widget.setShowHidePage!(
                      PageType.settings, false, PageParams());
                },
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        children: <Widget>[
          // ── Appearance ────────────────────────────────────────────────────
          _buildSectionHeader("Appearance"),
          _buildSettingsGroup([
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.sunMoon, cs.secondary),
              title: const Text("Theme"),
              subtitle: Text(widget.isDarkMode ? "Dark Mode" : "Light Mode"),
              trailing: Switch(
                value: widget.isDarkMode,
                onChanged: (_) => widget.onThemeToggle(),
              ),
              onTap: widget.onThemeToggle,
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.palette, cs.primary),
              title: const Text("Dynamic Coloring"),
              subtitle: const Text("Wallpaper colors (Material You)"),
              trailing: Switch(
                value: widget.useDynamicColor,
                onChanged: (_) => widget.onDynamicColorToggle(),
              ),
              onTap: widget.onDynamicColorToggle,
            ),
            if (!widget.useDynamicColor)
              _SettingsTile(
                leading: _buildLeadingIcon(LucideIcons.droplets, cs.primary),
                title: const Text("App Accent Color"),
                subtitle: const Text("Hand-picked custom theme"),
                trailing: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: widget.accentColor ?? const Color(0xFF6750A4),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: cs.onSurface.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                onTap: () async {
                  final currentColor =
                      widget.accentColor ?? const Color(0xFF6750A4);
                  Color? pickedColor = await showDialog<Color>(
                    context: context,
                    builder: (context) =>
                        ColorPickerDialog(color: colorToHex(currentColor)),
                  );
                  if (pickedColor != null) {
                    widget.onAccentColorChange?.call(pickedColor);
                  }
                },
              ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.type, cs.tertiary),
              title: const Text("Font Size"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.minus),
                    iconSize: 18,
                    onPressed: () =>
                        Provider.of<FontSizeController>(context, listen: false)
                            .decreaseFontSize(),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.plus),
                    iconSize: 18,
                    onPressed: () =>
                        Provider.of<FontSizeController>(context, listen: false)
                            .increaseFontSize(),
                  ),
                ],
              ),
            ),
          ]),

          // ── Interface ─────────────────────────────────────────────────────
          _buildSectionHeader("Interface"),
          _buildSettingsGroup([
            _SettingsTile(
              leading:
                  _buildLeadingIcon(LucideIcons.settings2, cs.onSurfaceVariant),
              title: const Text("Individual Group Settings"),
              subtitle: const Text("Use unique settings for each group"),
              trailing: Switch(
                value: useGroupSettings,
                onChanged: _setUseGroupSettings,
              ),
              onTap: () => _setUseGroupSettings(!useGroupSettings),
            ),
            _SettingsTile(
              enabled: !useGroupSettings,
              leading: _buildLeadingIcon(LucideIcons.clock9, cs.onSurfaceVariant),
              title: const Text("Show Date & Time"),
              subtitle: const Text("Display timestamp on messages"),
              trailing: Switch(
                value: globalShowDateTime,
                onChanged: !useGroupSettings ? _setGlobalShowDateTime : null,
              ),
              onTap: !useGroupSettings
                  ? () => _setGlobalShowDateTime(!globalShowDateTime)
                  : null,
            ),
            _SettingsTile(
              enabled: !useGroupSettings,
              leading: _buildLeadingIcon(
                  LucideIcons.rectangleHorizontal, cs.onSurfaceVariant),
              title: const Text("Show Note Borders"),
              subtitle: const Text("Display bubble outlines"),
              trailing: Switch(
                value: globalShowNoteBorder,
                onChanged: !useGroupSettings ? _setGlobalShowNoteBorder : null,
              ),
              onTap: !useGroupSettings
                  ? () => _setGlobalShowNoteBorder(!globalShowNoteBorder)
                  : null,
            ),
            _SettingsTile(
              enabled: !useGroupSettings,
              leading:
                  _buildLeadingIcon(LucideIcons.link, cs.onSurfaceVariant),
              title: const Text("Link Previews"),
              subtitle: const Text("Auto-fetch URL metadata"),
              trailing: Switch(
                value: globalLinkPreview,
                onChanged: !useGroupSettings ? _setGlobalLinkPreview : null,
              ),
              onTap: !useGroupSettings
                  ? () => _setGlobalLinkPreview(!globalLinkPreview)
                  : null,
            ),
            _SettingsTile(
              enabled: !useGroupSettings,
              leading: _buildLeadingIcon(
                  LucideIcons.arrowUpDown, cs.onSurfaceVariant),
              title: const Text("Sort Order"),
              subtitle: Text(globalSortOldestFirst
                  ? "Oldest first"
                  : "Newest first"),
              trailing: Switch(
                value: globalSortOldestFirst,
                onChanged: !useGroupSettings ? _setGlobalSortOrder : null,
              ),
              onTap: !useGroupSettings
                  ? () => _setGlobalSortOrder(!globalSortOldestFirst)
                  : null,
            ),
            _SettingsTile(
              enabled: !useGroupSettings,
              leading: _buildLeadingIcon(
                  LucideIcons.layoutGrid, cs.onSurfaceVariant),
              title: const Text("Media Gallery"),
              subtitle: const Text("Group consecutive images"),
              trailing: Switch(
                value: globalMediaGallery,
                onChanged: !useGroupSettings ? _setGlobalMediaGallery : null,
              ),
              onTap: !useGroupSettings
                  ? () => _setGlobalMediaGallery(!globalMediaGallery)
                  : null,
            ),
            _SettingsTile(
              enabled: !useGroupSettings,
              leading:
                  _buildLeadingIcon(LucideIcons.lock, cs.onSurfaceVariant),
              title: const Text("Lock All Groups"),
              subtitle: const Text("Require auth to open any group"),
              trailing: Switch(
                value: globalGroupLock,
                onChanged: !useGroupSettings ? _setGlobalGroupLock : null,
              ),
              onTap: !useGroupSettings
                  ? () => _setGlobalGroupLock(!globalGroupLock)
                  : null,
            ),
            _SettingsTile(
              enabled: !useGroupSettings,
              leading: _buildLeadingIcon(LucideIcons.eyeOff, cs.onSurfaceVariant),
              title: const Text("Privacy Shield"),
              subtitle: const Text("Gradiant blur until tapped"),
              trailing: Switch(
                value: privacyShieldEnabled,
                onChanged: !useGroupSettings ? _setPrivacyShield : null,
              ),
              onTap: !useGroupSettings
                  ? () => _setPrivacyShield(!privacyShieldEnabled)
                  : null,
            ),
          ]),

          // ── General ───────────────────────────────────────────────────────
          _buildSectionHeader("General"),
          _buildSettingsGroup([
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.timer, cs.primary),
              title: const Text('Time Format'),
              trailing: DropdownButton<String>(
                value: timeFormat,
                underline: const SizedBox(),
                icon: _buildTrailingChevron(),
                items: const [
                  DropdownMenuItem(value: "H12", child: Text('H12')),
                  DropdownMenuItem(value: "H24", child: Text('H24')),
                ],
                onChanged: (format) => updateTimeFormat(format),
              ),
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.shieldCheck, cs.error),
              title: const Text("App Lock"),
              subtitle: const Text("Biometric or pattern lock"),
              trailing: Switch(
                value: isAuthEnabled,
                onChanged: (_) => _authenticate(),
              ),
              onTap: _authenticate,
            ),
          ]),

          // ── Storage ───────────────────────────────────────────────────────
          if (widget.canShowBackupRestore) ...[
            _buildSectionHeader("Storage"),
            _buildSettingsGroup([
              _SettingsTile(
                leading: _buildLeadingIcon(
                    LucideIcons.databaseBackup, cs.secondary),
                title: const Text('Backup Data'),
                subtitle: const Text("Export your notes as zip"),
                trailing: _buildTrailingChevron(),
                onTap: createDownloadBackup,
              ),
              _SettingsTile(
                leading: _buildLeadingIcon(LucideIcons.rotateCcw, cs.primary),
                title: const Text('Restore Data'),
                subtitle: const Text("Import from backup zip"),
                trailing: _buildTrailingChevron(),
                onTap: restoreZipBackup,
              ),
            ]),
          ],

          // ── About ──────────────────────────────────────────────────────────
          _buildSectionHeader("About"),
          _buildSettingsGroup([
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.gitFork, cs.secondary),
              title: const Text('Fork Repository'),
              subtitle: const Text('Modern evolution with Material You'),
              trailing: _buildTrailingChevron(),
              onTap: _openForkRepo,
            ),
            _SettingsTile(
              leading:
                  _buildLeadingIcon(LucideIcons.github, cs.onSurfaceVariant),
              title: const Text('Original Repository'),
              subtitle: const Text('By jeerovan'),
              trailing: _buildTrailingChevron(),
              onTap: _openOriginalRepo,
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.bookOpen, cs.primary),
              title: const Text("What's New in This Fork"),
              trailing: _buildTrailingChevron(),
              onTap: _showChangelog,
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.star, cs.tertiary),
              title: const Text('Original App (Play Store)'),
              trailing: _buildTrailingChevron(),
              onTap: _redirectToOriginalPlayStore,
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.list, cs.primary),
              title: const Text("Developer Logging"),
              trailing: Switch(
                value: loggingEnabled,
                onChanged: _setLogging,
              ),
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.info, Colors.grey),
              title: const Text('App Version'),
              trailing: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final version = snapshot.data?.version ?? '...';
                  return Text(
                    version,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _openForkRepo() {
    const url = "https://github.com/FarhanZafarr-9/ntsapp";
    openURL(url);
  }

  void _openOriginalRepo() {
    const url = "https://github.com/jeerovan/ntsapp";
    openURL(url);
  }

  void _redirectToOriginalPlayStore() {
    const url =
        'https://play.google.com/store/apps/details?id=com.makenotetoself';
    openURL(url);
  }

  void _showChangelog() {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(LucideIcons.sparkles, size: 20, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Text(
              "What's New",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This fork brings modern improvements to the original app:',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              _changelogItem(
                cs,
                '✨ Material You Support',
                'Dynamic color theming based on your wallpaper',
              ),
              _changelogItem(
                cs,
                '🎨 Modern UI Design',
                'Refined interface with monochromatic icons and consistent theming',
              ),
              _changelogItem(
                cs,
                '🧩 Smarter Components',
                'Enhanced reply system, better message layouts, and improved interactions',
              ),
              _changelogItem(
                cs,
                '⚡ Performance & Polish',
                'Optimized rendering and smoother animations throughout',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: cs.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _changelogItem(ColorScheme cs, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 8, right: 10),
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

/// Lightweight data holder so _buildSettingsGroup can inspect each tile's
/// properties without needing to unwrap a fully-built widget.
class _SettingsTile {
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const _SettingsTile({
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });
}
