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

class SettingsPage extends StatefulWidget {
  final bool isDarkMode;
  final bool useDynamicColor;
  final bool runningOnDesktop;
  final Function(PageType, bool, PageParams)? setShowHidePage;
  final VoidCallback onThemeToggle;
  final VoidCallback onDynamicColorToggle;
  final bool canShowBackupRestore;

  const SettingsPage(
      {super.key,
      required this.isDarkMode,
      required this.useDynamicColor,
      required this.onThemeToggle,
      required this.onDynamicColorToggle,
      required this.canShowBackupRestore,
      required this.runningOnDesktop,
      required this.setShowHidePage});

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

  @override
  void initState() {
    super.initState();
    timeFormat = ModelSetting.get(AppString.timeFormat.string, "H12");
    isAuthEnabled = ModelSetting.get("local_auth", "no") == "yes";
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
                onTap: tile.onTap,
                child: ClipRRect(
                  borderRadius: radius,
                  child: ListTile(
                    leading: tile.leading,
                    title: tile.title,
                    subtitle: tile.subtitle,
                    trailing: tile.trailing,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
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
              leading: _buildLeadingIcon(LucideIcons.sunMoon, Colors.orange),
              title: const Text("Theme"),
              subtitle: Text(widget.isDarkMode ? "Dark Mode" : "Light Mode"),
              trailing: Switch(
                value: widget.isDarkMode,
                onChanged: (_) => widget.onThemeToggle(),
              ),
              onTap: widget.onThemeToggle,
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.palette, Colors.blue),
              title: const Text("Dynamic Coloring"),
              subtitle: const Text("Wallpaper colors (Material You)"),
              trailing: Switch(
                value: widget.useDynamicColor,
                onChanged: (_) => widget.onDynamicColorToggle(),
              ),
              onTap: widget.onDynamicColorToggle,
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.type, Colors.green),
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

          // ── General ───────────────────────────────────────────────────────
          _buildSectionHeader("General"),
          _buildSettingsGroup([
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.timer, Colors.amber),
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
              leading: _buildLeadingIcon(LucideIcons.shieldCheck, Colors.red),
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
                    LucideIcons.databaseBackup, Colors.purple),
                title: const Text('Backup Data'),
                subtitle: const Text("Export your notes as zip"),
                trailing: _buildTrailingChevron(),
                onTap: createDownloadBackup,
              ),
              _SettingsTile(
                leading: _buildLeadingIcon(LucideIcons.rotateCcw, Colors.blue),
                title: const Text('Restore Data'),
                subtitle: const Text("Import from backup zip"),
                trailing: _buildTrailingChevron(),
                onTap: restoreZipBackup,
              ),
            ]),
          ],

          // ── About & Feedback ──────────────────────────────────────────────
          _buildSectionHeader("About & Feedback"),
          _buildSettingsGroup([
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.star, Colors.orange),
              title: const Text('Leave a Review'),
              trailing: _buildTrailingChevron(),
              onTap: _redirectToFeedback,
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.share2, Colors.blue),
              title: const Text('Share App'),
              trailing: _buildTrailingChevron(),
              onTap: _share,
            ),
            if (Platform.isAndroid || Platform.isIOS)
              _SettingsTile(
                leading:
                    _buildLeadingIcon(LucideIcons.monitor, Colors.blueGrey),
                title: const Text('Desktop Version'),
                trailing: _buildTrailingChevron(),
                onTap: _redirectToDesktopApp,
              ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.list, Colors.blueGrey),
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

  void _redirectToDesktopApp() {
    const url = "https://github.com/jeerovan/ntsapp/releases";
    openURL(url);
  }

  void _redirectToFeedback() {
    const url =
        'https://play.google.com/store/apps/details?id=com.makenotetoself';
    openURL(url);
  }

  Future<void> _share() async {
    String? appName = await secureStorage.read(key: AppString.appName.string);
    appName = appName ?? "";
    const String appLink =
        'https://play.google.com/store/apps/details?id=com.makenotetoself';
    Share.share("Make a $appName: $appLink");
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

/// Lightweight data holder so _buildSettingsGroup can inspect each tile's
/// properties without needing to unwrap a fully-built widget.
class _SettingsTile {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
}
