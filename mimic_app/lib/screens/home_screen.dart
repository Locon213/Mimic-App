import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../providers/vpn_provider.dart';
import '../providers/server_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/app_theme.dart';
import 'widgets/connection_tile.dart';
import 'widgets/stats_card.dart';
import 'widgets/server_selector.dart';
import 'widgets/mode_selector.dart';
import 'widgets/nav_drawer.dart';

/// Home Screen - Main VPN control interface
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Load saved servers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ServerProvider>().loadServers();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: Theme.of(context).brightness == Brightness.dark
                ? [
                    AppColors.backgroundDark,
                    AppColors.surfaceDark,
                  ]
                : [
                    AppColors.backgroundLight,
                    AppColors.surfaceLight,
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              _buildAppBar(),
              
              // Main Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Connection Status & Button
                      ConnectionTile(
                        onConnectPressed: _handleConnect,
                        onDisconnectPressed: _handleDisconnect,
                      )
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .slideY(begin: 0.2, end: 0),
                      
                      const SizedBox(height: 20),
                      
                      // Statistics Card
                      Consumer<VpnProvider>(
                        builder: (context, vpnProvider, child) {
                          if (vpnProvider.isConnected) {
                            return StatsCard()
                                .animate()
                                .fadeIn(delay: 300.ms, duration: 600.ms)
                                .slideY(begin: 0.2, end: 0);
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Mode Selector
                      ModeSelector()
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 600.ms)
                          .slideY(begin: 0.2, end: 0),
                      
                      const SizedBox(height: 20),
                      
                      // Server Selector
                      ServerSelector()
                          .animate()
                          .fadeIn(delay: 400.ms, duration: 600.ms)
                          .slideY(begin: 0.2, end: 0),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Builder(
            builder: (context) => IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.surfaceElevated
                    : AppColors.surfaceElevatedLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          
          const Spacer(),
          
          Text(
            'Mimic VPN',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  gradient: AppColors.primaryGradient,
                ),
          ),
          
          const Spacer(),
          
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) => IconButton(
              onPressed: themeProvider.toggleTheme,
              icon: Icon(
                themeProvider.isDarkMode
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.surfaceElevated
                    : AppColors.surfaceElevatedLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleConnect() {
    final serverProvider = context.read<ServerProvider>();
    final vpnProvider = context.read<VpnProvider>();
    
    if (serverProvider.selectedServer == null) {
      _showNoServerDialog();
      return;
    }
    
    vpnProvider.connect(
      serverProvider.selectedServer!,
      mode: vpnProvider.mode,
    );
  }

  void _handleDisconnect() {
    context.read<VpnProvider>().disconnect();
  }

  void _showNoServerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No Server Selected'),
        content: const Text('Please select a server from the list below.'),
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
