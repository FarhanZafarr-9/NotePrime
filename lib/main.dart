// main.dart

// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:ntsapp/services/service_events.dart';
import 'package:ntsapp/utils/auth_guard.dart';
import 'package:ntsapp/utils/common.dart';
import 'package:ntsapp/utils/enums.dart';
import 'package:ntsapp/ui/pages/page_home.dart';
import 'package:ntsapp/ui/pages/page_desktop_categories_groups.dart';
import 'package:ntsapp/storage/storage_sqlite.dart';
import 'package:ntsapp/utils/utils_sync.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:window_size/window_size.dart';
import 'package:quick_actions/quick_actions.dart';

import 'ui/pages/page_media_migration.dart';
import 'models/model_item_group.dart';
import 'services/service_logger.dart';
import 'services/service_notification.dart';
import 'models/model_setting.dart';
import 'storage/storage_secure.dart';
import 'ui/themes.dart';
// import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  // await Firebase.initializeApp();
  // Process the sync message
  if (message.data['type'] == 'Sync') {
    final String sentryDsn = const String.fromEnvironment("SENTRY_DSN");
    if (!isDebugEnabled) {
      await SentryFlutter.init(
        (options) {
          options.dsn = sentryDsn;
          options.tracesSampleRate = 1.0;
          options.profilesSampleRate = 1.0;
        },
      );
    }
    try {
      await StorageSqlite.initialize(mode: ExecutionMode.fcmBackground);
      await initializeDependencies(mode: ExecutionMode.fcmBackground);
    } catch (e, s) {
      AppLogger(prefixes: ["FcmBg"])
          .error("Sync error", error: e, stackTrace: s);
    }
    try {
      await SyncUtils().triggerSync(true);
    } catch (e, s) {
      AppLogger(prefixes: ["FcmBg"])
          .error("Sync error", error: e, stackTrace: s);
    }
  }
}

// Mobile-specific callback - must be top-level function
@pragma('vm:entry-point')
void backgroundTaskDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await StorageSqlite.initialize(mode: ExecutionMode.appBackground);
      await initializeDependencies(mode: ExecutionMode.appBackground);
    } catch (e, s) {
      AppLogger(prefixes: ["BG"])
          .error("Initialize failed", error: e, stackTrace: s);
      return Future.value(false);
    }
    final String sentryDsn = const String.fromEnvironment("SENTRY_DSN");
    if (!isDebugEnabled) {
      await SentryFlutter.init(
        (options) {
          options.dsn = sentryDsn;
          options.tracesSampleRate = 1.0;
          options.profilesSampleRate = 1.0;
        },
      );
    }
    try {
      switch (taskName) {
        case DataSync.syncTaskId:
          await SyncUtils().triggerSync(true);
          break;
      }
      return Future.value(true);
    } catch (e, s) {
      // Capture exceptions with Sentry
      await Sentry.captureException(e, stackTrace: s);
      return Future.value(false);
    }
  });
}

final logger = AppLogger(prefixes: ["main"]);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    setWindowMinSize(const Size(720, 640));
  }
  await initializeMediaParams();
  await StorageSqlite.initialize(mode: ExecutionMode.appForeground);
  final String sentryDsn = const String.fromEnvironment("SENTRY_DSN");
  if (isDebugEnabled) {
    runApp(const MainApp());
  } else {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        // Set tracesSampleRate to 1.0 to capture 100% of transactions for tracing.
        // We recommend adjusting this value in production.
        options.tracesSampleRate = 1.0;
        // The sampling rate for profiling is relative to tracesSampleRate
        // Setting to 1.0 will profile 100% of sampled transactions:
        options.profilesSampleRate = 1.0;
      },
      appRunner: () => runApp(const MainApp()),
    );
  }
  unawaited(initializeRestInParallel());
}

Future<void> initializeRestInParallel() async {
  await Future.wait(([
    initializeDependencies(mode: ExecutionMode.appForeground),
    initializeFirebase(),
    initializeBackgroundSync(),
    initializePurchases()
  ]));
}

Future<void> initializeFirebase() async {
  if (runningOnMobile) {
    //initialize notificatins
    // await Firebase.initializeApp();
    logger.info("skipped firebase initialization (offline mode)");
    // FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    // logger.info("initialized firebase background handler");
    if (await SyncUtils.canSync()) {
      await NotificationService.instance.initialize();
      logger.info("initialized notification service");
    }
  }
}

Future<void> initializeBackgroundSync() async {
  //initialize background sync
  await DataSync.initialize();
  logger.info("initialized datasync");
}

Future<void> initializePurchases() async {
  // initialize purchases -- not required in background tasks
  if (revenueCatSupported) {
    String rcKey = "";
    if (Platform.isAndroid) {
      rcKey = const String.fromEnvironment("RC_KEY_ANDROID");
    }
    if (rcKey.isNotEmpty) {
      if (isDebugEnabled) {
        await Purchases.setLogLevel(LogLevel.debug);
      }
      PurchasesConfiguration configuration = PurchasesConfiguration(rcKey);
      await Purchases.configure(configuration);
      logger.info("Initialized purchases");
    }
  }
}

Future<void> initializeMediaParams() async {
  // initialized media params once before accessing sqlite
  SecureStorage secureStorage = SecureStorage();
  String mediaParamsInitialized =
      await secureStorage.read(key: "media_params_initialized") ?? "no";
  if (mediaParamsInitialized == "no") {
    await secureStorage.write(
        key: AppString.appName.string, value: "Note Safe");
    await secureStorage.write(key: "media_dir", value: "ntsmedia");
    await secureStorage.write(key: "backup_dir", value: "ntsbackup");
    await secureStorage.write(key: "db_file", value: "notetoself.db");
    await secureStorage.write(key: "media_params_initialized", value: "yes");
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.system;
  late bool _isDarkMode;
  bool _useDynamicColor = false;
  Color? _accentColor;

  // sharing intent
  StreamSubscription? _intentSub;
  final List<String> _sharedContents = [];

  // quick actions
  final QuickActions _quickActions = const QuickActions();

  final logger = AppLogger(prefixes: ["MainApp"]);

  @override
  void initState() {
    super.initState();
    AuthGuard.lastActiveAt = DateTime.now();
    // Load the theme from saved preferences
    String? savedTheme = ModelSetting.get("theme", null);
    switch (savedTheme) {
      case "light":
        _themeMode = ThemeMode.light;
        _isDarkMode = false;
        break;
      case "dark":
        _themeMode = ThemeMode.dark;
        _isDarkMode = true;
        break;
      default:
        // Default to system theme
        _themeMode = ThemeMode.system;
        _isDarkMode =
            PlatformDispatcher.instance.platformBrightness == Brightness.dark;
        break;
    }
    // Load dynamic color setting
    _useDynamicColor = ModelSetting.get("use_dynamic_color", "no") == "yes";
    // Load custom accent color
    String? savedAccent = ModelSetting.get("accent_color", null);
    if (savedAccent != null) {
      _accentColor = colorFromHex(savedAccent);
    }
    // Initialize lock state for cold start
    if (ModelSetting.get("local_auth", "no") == "yes") {
      AuthGuard.isLocked.value = true;
    }
    //sharing intent
    if (runningOnMobile) {
      // Listen to media sharing coming from outside the app while the app is in the memory.
      _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
          (sharedContents) {
        setState(() {
          _sharedContents.clear();
          for (SharedMediaFile sharedContent in sharedContents) {
            _sharedContents.add(sharedContent.path);
          }
        });
      }, onError: (err) {
        logger.error("getIntentDataStream error", error: err);
      });

      // Get the media sharing coming from outside the app while the app is closed.
      ReceiveSharingIntent.instance.getInitialMedia().then((sharedContents) {
        setState(() {
          _sharedContents.clear();
          for (SharedMediaFile sharedContent in sharedContents) {
            _sharedContents.add(sharedContent.path);
          }
          // Tell the library that we are done processing the intent.
          ReceiveSharingIntent.instance.reset();
        });
      });

      // Quick Actions
      _quickActions.initialize((String shortcutType) {
        logger.info("QuickAction triggered: $shortcutType");
        if (shortcutType == 'action_new_group') {
          EventStream().publish(AppEvent(type: EventType.navigateToGroup, value: 'new'));
        } else if (shortcutType.startsWith('group_')) {
          final groupId = shortcutType.replaceFirst('group_', '');
          EventStream().publish(AppEvent(type: EventType.navigateToGroup, value: groupId));
        }
      });

      _quickActions.setShortcutItems(<ShortcutItem>[
        const ShortcutItem(
          type: 'action_new_group',
          localizedTitle: 'New Group',
          icon: 'ic_launcher', // Use app icon as fallback
        ),
      ]);
      
      _updateQuickActions();
    }
    EventStream().notifier.addListener(_handleAppEvent);
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _updateQuickActions() async {
    final pinnedGroups = await ModelGroup.getPinned();
    logger.info("Found ${pinnedGroups.length} pinned groups for shortcuts.");
    final shortcuts = <ShortcutItem>[
      const ShortcutItem(
        type: 'action_new_group',
        localizedTitle: 'New Group',
        icon: 'ic_launcher',
      ),
    ];

    for (var group in pinnedGroups.take(3)) {
      shortcuts.add(ShortcutItem(
        type: 'group_${group.id}',
        localizedTitle: group.title,
        icon: 'ic_launcher',
      ));
    }

    await Future.delayed(const Duration(milliseconds: 500));
    _quickActions.setShortcutItems(shortcuts);
    logger.info("Shortcuts updated with ${shortcuts.length} items");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (AuthGuard.isAuthenticating) {
      logger.info("Lifecycle change ignored due to active authentication");
      return;
    }
    logger.info("App State:$state");

    if (Platform.isIOS || Platform.isAndroid) {
      if (state == AppLifecycleState.resumed) {
        if (ModelSetting.get("local_auth", "no") == "yes") {
          if (DateTime.now().difference(AuthGuard.lastActiveAt).inSeconds > 60) {
            AuthGuard.lastActiveAt = DateTime.now();
            EventStream().publish(AppEvent(type: EventType.authorise));
          } else {
            // Re-unlock if returning within the grace period
            AuthGuard.isLocked.value = false;
          }
        }
        SyncUtils().startAutoSync();
        logger.info("Started Foreground Sync");
      } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
        if (ModelSetting.get("local_auth", "no") == "yes") {
          AuthGuard.isLocked.value = true;
        }
        AuthGuard.lastActiveAt = DateTime.now();
        if (state == AppLifecycleState.paused) {
          SyncUtils().stopAutoSync();
          logger.info("Stopped Foreground Sync");
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    EventStream().notifier.removeListener(_handleAppEvent);
    _intentSub?.cancel();
    super.dispose();
  }

  void _handleAppEvent() {
    final AppEvent? event = EventStream().notifier.value;
    if (event == null) return;

    if (event.type == EventType.changedGroupId) {
      _updateQuickActions();
    }
  }

  // Toggle between light and dark modes
  Future<void> _onThemeToggle() async {
    setState(() {
      _themeMode = _isDarkMode ? ThemeMode.light : ThemeMode.dark;
      _isDarkMode = !_isDarkMode;
    });
    await ModelSetting.set("theme", _isDarkMode ? "dark" : "light");
  }

  Future<void> _onDynamicColorToggle() async {
    setState(() {
      _useDynamicColor = !_useDynamicColor;
    });
    await ModelSetting.set("use_dynamic_color", _useDynamicColor ? "yes" : "no");
  }

  // Handle accent color change
  Future<void> _onAccentColorChange(Color color) async {
    setState(() {
      _accentColor = color;
    });
    await ModelSetting.set("accent_color", colorToHex(color));
  }

  @override
  Widget build(BuildContext context) {
    bool isLargeScreen = false;
    if (isDebugEnabled) {
      isLargeScreen = MediaQuery.of(context).size.width > 600;
    } else {
      isLargeScreen =
          Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    }
    Widget page = PageCategoriesGroups(
      runningOnDesktop: false,
      setShowHidePage: null,
      sharedContents: _sharedContents,
      isDarkMode: _isDarkMode,
      onThemeToggle: _onThemeToggle,
      useDynamicColor: _useDynamicColor,
      onDynamicColorToggle: _onDynamicColorToggle,
      accentColor: _accentColor,
      onAccentColorChange: _onAccentColorChange,
    );
    if (isLargeScreen) {
      page = PageCategoriesGroupsPane(
        sharedContents: _sharedContents,
        isDarkMode: _isDarkMode,
        onThemeToggle: _onThemeToggle,
        useDynamicColor: _useDynamicColor,
        onDynamicColorToggle: _onDynamicColorToggle,
        accentColor: _accentColor,
        onAccentColorChange: _onAccentColorChange,
      );
    }
    String processMedia = ModelSetting.get("process_media", "no");
    if (processMedia == "yes") {
      page = PageMediaMigration(
        runningOnDesktop: !runningOnMobile,
        isDarkMode: _isDarkMode,
        onThemeToggle: _onThemeToggle,
        useDynamicColor: _useDynamicColor,
        onDynamicColorToggle: _onDynamicColorToggle,
        accentColor: _accentColor,
        onAccentColorChange: _onAccentColorChange,
      );
    }
    return ChangeNotifierProvider(
      create: (_) => FontSizeController(),
      child: DynamicColorBuilder(builder: (lightDynamic, darkDynamic) {
        ColorScheme? lightColorScheme;
        ColorScheme? darkColorScheme;

        if (_useDynamicColor) {
          lightColorScheme = lightDynamic;
          darkColorScheme = darkDynamic;
        }

        return Builder(builder: (context) {
          return MaterialApp(
            builder: (context, child) {
              final textScaler =
                  Provider.of<FontSizeController>(context).textScaler;
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: textScaler,
                ),
                child: ValueListenableBuilder<bool>(
                  valueListenable: AuthGuard.isLocked,
                  builder: (context, isLocked, _) {
                    return Stack(
                      children: [
                        Positioned.fill(child: child!),
                        if (isLocked) const PrivacyShield(),
                      ],
                    );
                  },
                ),
              );
            },
            theme: AppThemes.getTheme(Brightness.light, lightColorScheme,
                seedColor: _accentColor),
            darkTheme: AppThemes.getTheme(Brightness.dark, darkColorScheme,
                seedColor: _accentColor),
            themeMode: _themeMode,
            // Uses system theme by default
            home: page,
            navigatorObservers: [
              SentryNavigatorObserver(),
            ],
            debugShowCheckedModeBanner: false,
          );
        });
      }),
    );
  }
}

class DataSync {
  static const String syncTaskId = 'dataSync';
  static final logger = AppLogger(prefixes: ["DataSync"]);
  // Initialize background sync based on platform
  static Future<void> initialize() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await _initializeBackgroundForMobile();
    }
    // sync on app start
    SyncUtils().startAutoSync();
    logger.info("Started autosync");
  }

  // Mobile-specific initialization using Workmanager
  static Future<void> _initializeBackgroundForMobile() async {
    await Workmanager()
        .initialize(backgroundTaskDispatcher, isInDebugMode: isDebugEnabled);
    await Workmanager().registerPeriodicTask(
      syncTaskId,
      syncTaskId,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: Duration(minutes: 15),
    );
    logger.info("Background Task Registered");
  }
}

class PrivacyShield extends StatelessWidget {
  const PrivacyShield({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: GestureDetector(
        onTap: () {
          EventStream().publish(AppEvent(type: EventType.authorise));
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    LucideIcons.shieldCheck,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  "Note Safe Locked",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    EventStream().publish(AppEvent(type: EventType.authorise));
                  },
                  icon: const Icon(LucideIcons.unlock, size: 18),
                  label: const Text("Unlock"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
