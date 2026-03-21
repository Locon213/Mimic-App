/// Mimic Protocol Client - Main Entry Point
/// Cross-platform VPN client built with Flutter and Go Mobile

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform, exit;

import 'models/log_entry.dart';
import 'providers/vpn_provider.dart';
import 'providers/server_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/logs_provider.dart';
import 'services/desktop_go_logs_service.dart';
import 'services/native_logs_service.dart';
import 'services/system_tray_service.dart';
import 'services/persistent_log_storage.dart';
import 'screens/home_screen.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LogsProvider.instance.info(
    LogCategory.system,
    'App started',
    'Mimic UI initialized and providers are loading.',
  );
  NativeLogsService.instance.start();
  DesktopGoLogsService.instance.start();
  await PersistentLogStorage.instance.init();

  // Set preferred orientations (mobile only)
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const MimicApp());
}

class MimicApp extends StatefulWidget {
  const MimicApp({super.key});

  @override
  State<MimicApp> createState() => _MimicAppState();
}

class _MimicAppState extends State<MimicApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSystemTray();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemTrayService.instance.dispose();
    super.dispose();
  }

  void _initSystemTray() {
    final tray = SystemTrayService.instance;
    if (!tray.isSupported) return;

    tray.init(
      onShowWindow: () {
        // Bring window to front - handled by the OS for now
      },
      onToggleConnection: () {
        final vpnProvider = _navigatorKey.currentContext != null
            ? Provider.of<VpnProvider>(_navigatorKey.currentContext!, listen: false)
            : null;
        vpnProvider?.toggleConnection();
      },
      onQuit: () {
        SystemTrayService.instance.dispose();
        // Exit app
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          exit(0);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: LogsProvider.instance),
        ChangeNotifierProvider(create: (_) => VpnProvider()),
        ChangeNotifierProvider(
          create: (context) {
            final serverProvider = ServerProvider();
            serverProvider.loadServers();
            return serverProvider;
          },
        ),
        ChangeNotifierProvider(
          create: (context) {
            final settingsProvider = SettingsProvider();
            settingsProvider.loadSettings();
            return settingsProvider;
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'Mimic VPN',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
