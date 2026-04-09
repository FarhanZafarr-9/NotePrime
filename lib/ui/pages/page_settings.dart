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
          biometricOnly: false, // Use only biometric
          stickyAuth: true, // Keeps the authentication open
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
        // Use Share package to trigger download or share intent
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

  Widget _buildLeadingIcon(IconData icon, Color color) {
    final themeColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        size: 20,
        color: themeColor,
      ),
    );
  }

  Widget _buildTrailingChevron() {
    return Icon(
      LucideIcons.chevronRight,
      size: 16,
      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text("Settings"),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
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
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: <Widget>[
          _buildSectionHeader("Appearance"),
          Card(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.09),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                width: 0.75,
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: _buildLeadingIcon(LucideIcons.sunMoon, Colors.orange),
                  title: const Text("Theme"),
                  subtitle: Text(widget.isDarkMode ? "Dark Mode" : "Light Mode"),
                  onTap: widget.onThemeToggle,
                  trailing: Switch(
                    value: widget.isDarkMode,
                    onChanged: (bool value) => widget.onThemeToggle(),
                  ),
                ),
                Divider(height: 1, indent: 56, endIndent: 16, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ListTile(
                  leading: _buildLeadingIcon(LucideIcons.palette, Colors.blue),
                  title: const Text("Dynamic Coloring"),
                  subtitle: const Text("Wallpaper colors (Material You)"),
                  trailing: Switch(
                    value: widget.useDynamicColor,
                    onChanged: (bool value) => widget.onDynamicColorToggle(),
                  ),
                ),
                Divider(height: 1, indent: 56, endIndent: 16, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ListTile(
                  leading: _buildLeadingIcon(LucideIcons.type, Colors.green),
                  title: const Text("Font Size"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.minus),
                        iconSize: 18,
                        onPressed: () => Provider.of<FontSizeController>(context, listen: false).decreaseFontSize(),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.plus),
                        iconSize: 18,
                        onPressed: () => Provider.of<FontSizeController>(context, listen: false).increaseFontSize(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader("General"),
          Card(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.09),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                width: 0.75,
              ),
            ),
            child: Column(
              children: [
                ListTile(
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
                Divider(height: 1, indent: 56, endIndent: 16, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ListTile(
                  leading: _buildLeadingIcon(LucideIcons.shieldCheck, Colors.red),
                  title: const Text("App Lock"),
                  subtitle: const Text("Biometric or pattern lock"),
                  trailing: Switch(
                    value: isAuthEnabled,
                    onChanged: (bool value) => _authenticate(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader("Storage"),
          Card(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.09),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                width: 0.75,
              ),
            ),
            child: Column(
              children: [
                if (widget.canShowBackupRestore)
                  ListTile(
                    leading: _buildLeadingIcon(LucideIcons.databaseBackup, Colors.purple),
                    title: const Text('Backup Data'),
                    subtitle: const Text("Export your notes as zip"),
                    trailing: _buildTrailingChevron(),
                    onTap: createDownloadBackup,
                  ),
                if (widget.canShowBackupRestore)
                  Divider(height: 1, indent: 56, endIndent: 16, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
                if (widget.canShowBackupRestore)
                  ListTile(
                    leading: _buildLeadingIcon(LucideIcons.rotateCcw, Colors.blue),
                    title: const Text('Restore Data'),
                    subtitle: const Text("Import from backup zip"),
                    trailing: _buildTrailingChevron(),
                    onTap: restoreZipBackup,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader("About & Feedback"),
          Card(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.09),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                width: 0.75,
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: _buildLeadingIcon(LucideIcons.star, Colors.orange),
                  title: const Text('Leave a Review'),
                  trailing: _buildTrailingChevron(),
                  onTap: _redirectToFeedback,
                ),
                Divider(height: 1, indent: 56, endIndent: 16, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ListTile(
                  leading: _buildLeadingIcon(LucideIcons.share2, Colors.blue),
                  title: const Text('Share App'),
                  trailing: _buildTrailingChevron(),
                  onTap: _share,
                ),
                Divider(height: 1, indent: 56, endIndent: 16, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
                if (Platform.isAndroid || Platform.isIOS)
                  ListTile(
                    leading: _buildLeadingIcon(LucideIcons.monitor, Colors.grey),
                    title: const Text('Desktop Version'),
                    trailing: _buildTrailingChevron(),
                    onTap: _redirectToDesktopApp,
                  ),
                Divider(height: 1, indent: 56, endIndent: 16, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ListTile(
                  leading: _buildLeadingIcon(LucideIcons.list, Colors.blueGrey),
                  title: const Text("Developer Logging"),
                  trailing: Switch(
                    value: loggingEnabled,
                    onChanged: _setLogging,
                  ),
                ),
                Divider(height: 1, indent: 56, endIndent: 16, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final version = snapshot.data?.version ?? 'Loading...';
                    return ListTile(
                      leading: _buildLeadingIcon(LucideIcons.info, Colors.grey),
                      title: const Text('App Version'),
                      trailing: Text(version, style: const TextStyle(fontSize: 12)),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _redirectToDesktopApp() {
    const url = "https://github.com/jeerovan/ntsapp/releases";
    openURL(url);
  }

  void _redirectToFeedback() {
    const url =
        'https://play.google.com/store/apps/details?id=com.makenotetoself';
    // Use your package name
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
