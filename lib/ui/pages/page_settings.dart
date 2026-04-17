import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ntsapp/utils/backup_restore.dart';
import 'package:ntsapp/utils/enums.dart';
import 'package:ntsapp/models/model_setting.dart';
import 'package:ntsapp/utils/auth_guard.dart';
import 'package:ntsapp/services/service_events.dart';
import 'package:ntsapp/services/service_logger.dart';
import 'package:ntsapp/storage/storage_secure.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';

import '../../models/model_item.dart';
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
  late bool immersiveMode;
  late bool screenshotProtection;
  late int biometricGracePeriod;
  late String fontFamily;
  late bool autoDownloadMedia;
  late String mediaNetworkType;
  String _cacheSize = "0 B";
  String _appVersion = "1.0.0";

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
    immersiveMode = ModelSetting.get("immersive_mode", "no") == "yes";
    screenshotProtection = ModelSetting.get("screenshot_protection", "no") == "yes";
    biometricGracePeriod = int.parse(ModelSetting.get("biometric_grace_period", "0").toString());
    fontFamily = ModelSetting.get("font_family", "Inter");
    autoDownloadMedia = ModelSetting.get("auto_download_media", "yes") == "yes";
    mediaNetworkType = ModelSetting.get("media_network_type", "wifi");
    _loadVersion();
    _calculateCacheSize();
  }

  Future<void> _calculateCacheSize() async {
    int totalSize = 0;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final cacheDir = await getTemporaryDirectory();
      
      String? mediaDirName = await secureStorage.read(key: "media_dir");
      if (mediaDirName != null) {
        final mediaDir = Directory(path.join(docDir.path, mediaDirName));
        if (await mediaDir.exists()) {
          totalSize += await _getDirSize(mediaDir);
        }
      }
      
      if (await cacheDir.exists()) {
        totalSize += await _getDirSize(cacheDir);
      }
      
      setState(() {
        _cacheSize = readableFileSizeFromBytes(totalSize);
      });
    } catch (e) {
      logger.error("Error calculating cache size", error: e);
    }
  }

  Future<int> _getDirSize(Directory dir) async {
    int size = 0;
    try {
      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          size += await entity.length();
        }
      }
    } catch (e) {
      // Ignore errors for specific files
    }
    return size;
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = packageInfo.version;
        });
      }
    } catch (e) {
      logger.error("Error loading version", error: e);
    }
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

  Future<void> _setImmersiveMode(bool value) async {
    setState(() => immersiveMode = value);
    await ModelSetting.set("immersive_mode", value ? "yes" : "no");
    if (value) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _toggleScreenshotProtection(bool value) async {
    setState(() => screenshotProtection = value);
    await ModelSetting.set("screenshot_protection", value ? "yes" : "no");
    if (Platform.isAndroid) {
      if (value) {
        await FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
      } else {
        await FlutterWindowManagerPlus.clearFlags(FlutterWindowManagerPlus.FLAG_SECURE);
      }
    }
  }

  Future<void> _setBiometricGracePeriod(int minutes) async {
    setState(() => biometricGracePeriod = minutes);
    await ModelSetting.set("biometric_grace_period", minutes);
  }

  Future<void> _setFontFamily(String font) async {
    setState(() => fontFamily = font);
    await ModelSetting.set("font_family", font);
    EventStream().publish(AppEvent(type: EventType.themeChanged));
  }

  Future<void> _setAutoDownloadMedia(bool value) async {
    setState(() => autoDownloadMedia = value);
    await ModelSetting.set("auto_download_media", value ? "yes" : "no");
  }

  Future<void> _setMediaNetworkType(String type) async {
    setState(() => mediaNetworkType = type);
    await ModelSetting.set("media_network_type", type);
  }

  Future<void> _showForkInfoDialog() async {
    if (mounted) {
      final cs = Theme.of(context).colorScheme;
      await showDialog(
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
                            'This is an Android-specific fork with Material You support. Support for other devices will be considered in the future.',
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
                    'NotePrime is completely private. No data collection, no ads.',
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
                  const url = 'https://github.com/jeerovan/ntsapp'; // baseline
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

  Future<void> _showClearCacheDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear Cache?"),
        content: const Text("This will delete all locally cached media and link previews. Files on the cloud will not be affected."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Clear")
          ),
        ],
      ),
    );

    if (confirmed == true) {
      showProcessing();
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final cacheDir = await getTemporaryDirectory();
        
        String? mediaDirName = await secureStorage.read(key: "media_dir");
        if (mediaDirName != null) {
          final mediaDir = Directory(path.join(docDir.path, mediaDirName));
          if (await mediaDir.exists()) {
            await mediaDir.delete(recursive: true);
            await mediaDir.create();
          }
        }
        
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
          await cacheDir.create();
        }
        
        await _calculateCacheSize();
      } catch (e) {
        logger.error("Error clearing cache", error: e);
      }
      hideProcessing();
    }
  }

  void _showFontPicker() {
    final List<String> fonts = ["Inter", "Roboto Mono", "Lora", "Open Sans"];
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: fonts.map((f) => ListTile(
          title: Text(f, style: GoogleFonts.getFont(f)),
          trailing: fontFamily == f ? Icon(LucideIcons.check, color: Theme.of(context).colorScheme.primary) : null,
          onTap: () {
            _setFontFamily(f);
            Navigator.pop(context);
          },
        )).toList(),
      ),
    );
  }

  void _showGracePeriodPicker() {
    final cs = Theme.of(context).colorScheme;
    final List<int> periods = [0, 1, 5, 10, 30];

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Biometric Grace Period",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                "How long before re-locking the app",
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              ...periods.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _bottomSheetTile(
                      context: context,
                      icon: LucideIcons.timer,
                      label: p == 0 ? "Immediate Lock" : "$p Minutes",
                      color: biometricGracePeriod == p ? cs.primary : null,
                      onTap: () {
                        _setBiometricGracePeriod(p);
                        Navigator.pop(context);
                      },
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showNetworkTypePicker() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Download Network",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface),
              ),
              const SizedBox(height: 20),
              _bottomSheetTile(
                context: context,
                icon: LucideIcons.wifi,
                label: "Wi-Fi Only",
                color: mediaNetworkType == "wifi" ? cs.primary : null,
                onTap: () {
                  _setMediaNetworkType("wifi");
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
              _bottomSheetTile(
                context: context,
                icon: LucideIcons.globe,
                label: "Wi-Fi & Cellular",
                color: mediaNetworkType == "all" ? cs.primary : null,
                onTap: () {
                  _setMediaNetworkType("all");
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _authenticate() async {
    try {
      AuthGuard.isAuthenticating = true;
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
    } finally {
      AuthGuard.isAuthenticating = false;
      AuthGuard.lastActiveAt = DateTime.now();
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

  Future<void> _repairAllThumbnails() async {
    showProcessing();
    try {
      List<ModelItem> items = await ModelItem.getMediaItems();
      int repairedCount = 0;
      for (var item in items) {
        if (item.thumbnail == null &&
            item.data != null &&
            item.data!.containsKey("path")) {
          final file = File(item.data!["path"]);
          if (file.existsSync()) {
            if (item.type == ItemType.image) {
              final bytes = await file.readAsBytes();
              final thumbnail = await compute(getImageThumbnail, bytes);
              if (thumbnail != null) {
                item.thumbnail = thumbnail;
                await item.update(["thumbnail"]);
                repairedCount++;
              }
            } else if (item.type == ItemType.video) {
              try {
                VideoInfoExtractor extractor =
                    VideoInfoExtractor(item.data!["path"]);
                final thumbnail = await extractor.getThumbnail();
                if (thumbnail != null) {
                  item.thumbnail = thumbnail;
                  await item.update(["thumbnail"]);
                  repairedCount++;
                }
                extractor.dispose();
              } catch (_) {}
            }
          }
        }
      }
      hideProcessing();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Repaired $repairedCount thumbnails")));
      }
    } catch (e) {
      hideProcessing();
      logger.error("Repair all thumbnails failed", error: e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Repair failed")));
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

  Widget _buildSubHeaderWithStatus(String title, bool isLocked) {
    return Padding(
      padding:
          const EdgeInsets.only(left: 4.0, right: 4.0, top: 14.0, bottom: 6.0),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isLocked ? "Group" : "Individual",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: isLocked
                    ? "Controlled by Individual Group Settings toggle"
                    : "Can be customized per group",
                child: Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
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
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.maximize, cs.primary),
              title: const Text("Immersive Mode"),
              subtitle: const Text("Hide status bar for a clean look"),
              trailing: Switch(
                value: immersiveMode,
                onChanged: _setImmersiveMode,
              ),
              onTap: () => _setImmersiveMode(!immersiveMode),
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.type, cs.primary),
              title: const Text("Font Family"),
              subtitle: Text(fontFamily),
              trailing: _buildTrailingChevron(),
              onTap: _showFontPicker,
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
          ]),

          _buildSubHeaderWithStatus("Display", useGroupSettings),
          _buildSettingsGroup([
            _SettingsTile(
              enabled: !useGroupSettings,
              leading:
                  _buildLeadingIcon(LucideIcons.clock9, cs.onSurfaceVariant),
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
          ]),

          _buildSubHeaderWithStatus("Behavior", useGroupSettings),
          _buildSettingsGroup([
            _SettingsTile(
              enabled: !useGroupSettings,
              leading: _buildLeadingIcon(
                  LucideIcons.arrowUpDown, cs.onSurfaceVariant),
              title: const Text("Sort Order"),
              subtitle:
                  Text(globalSortOldestFirst ? "Oldest first" : "Newest first"),
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
              leading: _buildLeadingIcon(LucideIcons.link, cs.onSurfaceVariant),
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
          ]),

          _buildSubHeaderWithStatus("Privacy", useGroupSettings),
          _buildSettingsGroup([
            _SettingsTile(
              enabled: !useGroupSettings,
              leading: _buildLeadingIcon(LucideIcons.lock, cs.onSurfaceVariant),
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
              leading:
                  _buildLeadingIcon(LucideIcons.eyeOff, cs.onSurfaceVariant),
              title: const Text("Privacy Shield"),
              subtitle: const Text("Gradient blur until tapped"),
              trailing: Switch(
                value: privacyShieldEnabled,
                onChanged: !useGroupSettings ? _setPrivacyShield : null,
              ),
              onTap: !useGroupSettings
                  ? () => _setPrivacyShield(!privacyShieldEnabled)
                  : null,
            ),
          ]),

          // ── Privacy & Security ───────────────────────────────────────────
          _buildSectionHeader("Privacy & Security"),
          _buildSettingsGroup([
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.shieldAlert, cs.primary),
              title: const Text("Screenshot Protection"),
              subtitle: const Text("Block screenshots on Android"),
              trailing: Switch(
                value: screenshotProtection,
                onChanged: _toggleScreenshotProtection,
              ),
              onTap: () => _toggleScreenshotProtection(!screenshotProtection),
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.timer, cs.primary),
              title: const Text("Biometric Grace Period"),
              subtitle: Text(biometricGracePeriod == 0
                  ? "Immediate lock"
                  : "Lock after $biometricGracePeriod mins"),
              trailing: _buildTrailingChevron(),
              onTap: _showGracePeriodPicker,
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.fingerprint, cs.primary),
              title: const Text("Device Authentication"),
              subtitle: const Text("Lock app with fingerprint/PIN"),
              trailing: Switch(
                value: isAuthEnabled,
                onChanged: (value) => _authenticate(),
              ),
              onTap: _authenticate,
            ),
          ]),

          // ── Media & Storage ──────────────────────────────────────────────
          _buildSectionHeader("Media & Storage"),
          _buildSettingsGroup([
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.download, cs.primary),
              title: const Text("Auto-Download Previews"),
              subtitle: const Text("For link previews & small media"),
              trailing: Switch(
                value: autoDownloadMedia,
                onChanged: _setAutoDownloadMedia,
              ),
              onTap: () => _setAutoDownloadMedia(!autoDownloadMedia),
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.wifi, cs.primary),
              title: const Text("Download Network"),
              subtitle: Text(mediaNetworkType == "wifi"
                  ? "Wi-Fi Only"
                  : "Wi-Fi & Cellular"),
              trailing: _buildTrailingChevron(),
              onTap: _showNetworkTypePicker,
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.imagePlus, cs.primary),
              title: const Text("Repair Thumbnails"),
              subtitle: const Text("Regenerate missing media previews"),
              trailing: _buildTrailingChevron(),
              onTap: _repairAllThumbnails,
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.trash2, Colors.orange),
              title: const Text("Clear Cache"),
              subtitle: Text("Size: $_cacheSize"),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text("Clear",
                    style: TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              onTap: _showClearCacheDialog,
            ),
          ]),

          // ── General ───────────────────────────────────────────────────────
          _buildSectionHeader("General"),
          _buildSettingsGroup([
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.watch, cs.primary),
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
            /* 
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.star, cs.tertiary),
              title: const Text('Original App (Play Store)'),
              trailing: _buildTrailingChevron(),
              onTap: _redirectToOriginalPlayStore,
            ),
            */
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.list, cs.primary),
              title: const Text("Developer Logging"),
              trailing: Switch(
                value: loggingEnabled,
                onChanged: _setLogging,
              ),
            ),
            _SettingsTile(
              leading: _buildLeadingIcon(LucideIcons.info, cs.secondary),
              title: const Text('App Version'),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Material You • v$_appVersion',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
              onTap: _showForkInfoDialog,
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
                'This is an Android-specific fork. Support for other platforms will be considered in the future. It brings modern improvements to the original app:',
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

  Widget _bottomSheetTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? subtitle,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tileColor = color ?? cs.onSurfaceVariant;
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tileColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: tileColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 15,
                            color: color ?? cs.onSurface)),
                    if (subtitle != null)
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                  ],
                ),
              ),
              if (color != null)
                Icon(LucideIcons.check, size: 18, color: color),
            ],
          ),
        ),
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
