import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/vpn_provider.dart';
import '../providers/server_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/logs_provider.dart';
import '../models/log_entry.dart';
import '../utils/app_theme.dart';
import 'widgets/connection_tile.dart';
import 'widgets/stats_card.dart';
import 'widgets/server_selector.dart';
import 'widgets/mode_selector.dart';
import 'widgets/nav_drawer.dart';

/// Home Screen - Main VPN control interface with minimalist design
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  bool _autoConnectAttempted = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ServerProvider>().loadServers();
      _attemptAutoConnect();
    });
  }

  Future<void> _attemptAutoConnect() async {
    if (_autoConnectAttempted) return;
    _autoConnectAttempted = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final autoConnect = prefs.getBool('auto_connect_enabled') ?? false;
      if (!autoConnect) return;

      final lastServerId = prefs.getString('last_connected_server_id');
      if (lastServerId == null) return;

      // Wait a bit for servers to load
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      final serverProvider = context.read<ServerProvider>();
      final vpnProvider = context.read<VpnProvider>();

      if (vpnProvider.isConnected || vpnProvider.isConnecting) return;

      final server = serverProvider.servers.where(
        (s) => s.id == lastServerId,
      ).firstOrNull;

      if (server != null) {
        serverProvider.selectServer(server);
        final mode = prefs.getString('last_connected_mode') ?? 'TUN';
        try {
          await vpnProvider.connect(server, mode: mode);
        } catch (e) {
          // Auto-connect failed silently
        }
      }
    } catch (e) {
      // Auto-connect failed silently
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [
                    AppColors.backgroundDark,
                    AppColors.backgroundDark,
                    AppColors.surfaceDark,
                  ]
                : [
                    AppColors.backgroundLight,
                    AppColors.backgroundLight,
                    AppColors.surfaceLight,
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Minimal App Bar
              _buildAppBar(),

              // Main Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),

                      // Connection Status & Button
                      ConnectionTile(
                        onConnectPressed: _handleConnect,
                        onDisconnectPressed: _handleDisconnect,
                      )
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1)),

                      const SizedBox(height: 24),

                      // Server Selector
                      ServerSelector()
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 600.ms)
                          .slideY(begin: 0.1, end: 0),

                      // Mode Selector (Desktop only)
                      Consumer<VpnProvider>(
                        builder: (context, vpnProvider, child) {
                          if (vpnProvider.availableModes.length > 1) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: ModeSelector()
                                  .animate()
                                  .fadeIn(delay: 300.ms, duration: 600.ms),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),

                      const SizedBox(height: 16),

                      // Stats Card - Only when connected
                      Consumer<VpnProvider>(
                        builder: (context, vpnProvider, child) {
                          if (vpnProvider.isConnected) {
                            return Column(
                              children: [
                                const SizedBox(height: 16),
                                StatsCard()
                                    .animate()
                                    .fadeIn(delay: 400.ms, duration: 600.ms)
                                    .slideY(begin: 0.1, end: 0),
                              ],
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),

                      const SizedBox(height: 40),

                      // Bottom status hint
                      Consumer<VpnProvider>(
                        builder: (context, vpnProvider, child) {
                          if (vpnProvider.isDisconnected) {
                            return Text(
                              'Tap to connect and secure your connection',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? AppColors.textDarkSecondary
                                    : AppColors.textSecondary,
                              ),
                            ).animate().fadeIn(delay: 600.ms, duration: 800.ms);
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      drawer: const NavDrawer(),
    );
  }

  Widget _buildAppBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // Menu Button
          Builder(
            builder: (context) => Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceElevated : AppColors.surfaceElevatedLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: IconButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu_rounded, size: 24),
                padding: const EdgeInsets.all(10),
              ),
            ),
          ),

          const Spacer(),

          // App Title
          Column(
            children: [
              Text(
                'Mimic',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.textDarkPrimary : AppColors.textPrimary,
                ),
              ),
              Text(
                'VPN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Theme Toggle
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) => Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceElevated : AppColors.surfaceElevatedLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: IconButton(
                onPressed: themeProvider.toggleTheme,
                icon: Icon(
                  themeProvider.isDarkMode
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  size: 24,
                ),
                padding: const EdgeInsets.all(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleConnect() {
    final serverProvider = context.read<ServerProvider>();
    final logs = context.read<LogsProvider>();

    if (serverProvider.selectedServer == null) {
      logs.warning(
        LogCategory.ui,
        'Connect blocked',
        'Connect was requested without selecting a server first.',
      );
      _showNoServerDialog();
      return;
    }

    logs.info(
      LogCategory.ui,
      'Connect button',
      'User requested VPN connection from the home screen.',
    );
    _connectToSelectedServer();
  }

  void _handleDisconnect() {
    context.read<LogsProvider>().info(
      LogCategory.ui,
      'Disconnect button',
      'User requested VPN disconnection from the home screen.',
    );
    context.read<VpnProvider>().disconnect();
  }

  Future<void> _connectToSelectedServer() async {
    final serverProvider = context.read<ServerProvider>();
    final vpnProvider = context.read<VpnProvider>();

    try {
      await vpnProvider.connect(
        serverProvider.selectedServer!,
        mode: vpnProvider.mode,
      );

      // Save last connected server for auto-connect
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_connected_server_id', serverProvider.selectedServer!.id);
      await prefs.setString('last_connected_mode', vpnProvider.mode);
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e')),
      );
    }
  }

  void _showNoServerDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: const Text('No Server Selected'),
        content: const Text('Please select or add a server to connect.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
