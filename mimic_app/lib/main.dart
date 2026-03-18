/// Mimic Protocol Client - Main Entry Point
/// Cross-platform VPN client built with Flutter and Go Mobile

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import 'models/log_entry.dart';
import 'providers/vpn_provider.dart';
import 'providers/server_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/logs_provider.dart';
import 'services/desktop_go_logs_service.dart';
import 'services/native_logs_service.dart';
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

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const MimicApp());
}

class MimicApp extends StatelessWidget {
  const MimicApp({super.key});

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
            // Load servers on initialization
            serverProvider.loadServers();
            return serverProvider;
          },
        ),
        ChangeNotifierProvider(
          create: (context) {
            final settingsProvider = SettingsProvider();
            // Load settings on initialization
            settingsProvider.loadSettings();
            return settingsProvider;
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
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
