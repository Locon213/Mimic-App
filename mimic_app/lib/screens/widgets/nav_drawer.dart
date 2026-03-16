import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/theme_provider.dart';
import '../../providers/vpn_provider.dart';
import '../../providers/server_provider.dart';
import '../../models/network_stats.dart';
import '../../utils/app_theme.dart';

/// Navigation Drawer - Side menu with app navigation
class NavDrawer extends StatelessWidget {
  const NavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context, isDark),

            // Menu Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _buildMenuItem(
                    context,
                    icon: Icons.home_rounded,
                    label: 'Home',
                    onTap: () => Navigator.pop(context),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.dns_rounded,
                    label: 'Servers',
                    subtitle: '${context.watch<ServerProvider>().servers.length} saved',
                    onTap: () {
                      Navigator.pop(context);
                      // Navigate to servers screen (if created)
                    },
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    onTap: () {
                      Navigator.pop(context);
                      _showSettings(context);
                    },
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.info_outline_rounded,
                    label: 'About',
                    onTap: () {
                      Navigator.pop(context);
                      _showAbout(context);
                    },
                  ),

                  const Divider(),

                  // Theme Toggle
                  Consumer<ThemeProvider>(
                    builder: (context, themeProvider, child) => ListTile(
                      leading: Icon(
                        themeProvider.isDarkMode
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                      ),
                      title: Text(
                        themeProvider.isDarkMode ? 'Light Mode' : 'Dark Mode',
                        style: TextStyle(
                          color: isDark ? AppColors.textDarkPrimary : AppColors.textPrimary,
                        ),
                      ),
                      trailing: Switch(
                        value: themeProvider.isDarkMode,
                        onChanged: (value) => themeProvider.toggleTheme(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Footer
            _buildFooter(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Consumer<VpnProvider>(
      builder: (context, vpnProvider, child) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.security_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Mimic VPN',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: vpnProvider.isConnected
                      ? Colors.white.withOpacity(0.2)
                      : Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: vpnProvider.isConnected
                            ? AppColors.connected
                            : AppColors.disconnected,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      vpnProvider.status.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: Icon(
        icon,
        color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isDark ? AppColors.textDarkPrimary : AppColors.textPrimary,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
              ),
            )
          : null,
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
      ),
      onTap: onTap,
    );
  }

  Widget _buildFooter(BuildContext context, bool isDark) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '1.0.0';

        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Version $version',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Developer: Locon213',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSettings(BuildContext context) {
    // Navigate to settings screen
  }

  void _showAbout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 600;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: isMobile ? 12 : 24, // Less padding on mobile
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceElevated : AppColors.surfaceElevatedLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Logo
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),

                const Text(
                  'Mimic VPN Client',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 2.0.0',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Cross-platform VPN client built with Flutter and Go Mobile.\nPowered by Mimic Protocol.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 20),

                const Divider(),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Developer: ',
                      style: TextStyle(
                        color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                      ),
                    ),
                    const Text(
                      'Locon213',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Built with Mimic Protocol SDK',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final url = Uri.parse('https://github.com/Locon213/Mimic-App');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not open GitHub'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.code_rounded),
                    label: const Text('View on GitHub'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
