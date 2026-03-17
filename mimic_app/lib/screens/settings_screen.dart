import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/vpn_provider.dart';
import '../utils/app_theme.dart';
import 'rules_screen.dart';

/// Settings Screen - Modern minimalist settings with routing rules
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          if (settingsProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // General Settings Section
                _SectionTitle(title: 'General', isDark: isDark),
                const SizedBox(height: 12),

                _SettingCard(
                  icon: Icons.flash_auto_rounded,
                  title: 'Auto Connect',
                  subtitle: 'Automatically connect to last used server',
                  isDark: isDark,
                  trailing: Switch(
                    value: settingsProvider.autoConnect,
                    onChanged: (value) {
                      settingsProvider.updateSettings(autoConnect: value);
                    },
                  ),
                ),

                const SizedBox(height: 8),

                _SettingCard(
                  icon: Icons.power_rounded,
                  title: 'Start on Boot',
                  subtitle: 'Launch VPN when device starts',
                  isDark: isDark,
                  trailing: Switch(
                    value: settingsProvider.startOnBoot,
                    onChanged: (value) {
                      settingsProvider.updateSettings(startOnBoot: value);
                    },
                  ),
                ),

                const SizedBox(height: 8),

                _SettingCard(
                  icon: Icons.notifications_active_rounded,
                  title: 'Show Notification',
                  subtitle: 'Display VPN status in notification bar',
                  isDark: isDark,
                  trailing: Switch(
                    value: settingsProvider.showNotification,
                    onChanged: (value) {
                      settingsProvider.updateSettings(showNotification: value);
                    },
                  ),
                ),

                const SizedBox(height: 24),

                // Routing Rules Section
                _SectionTitle(title: 'Routing Rules', isDark: isDark),
                const SizedBox(height: 12),

                _RuleCard(
                  icon: Icons.direct_rounded,
                  title: 'Direct',
                  subtitle: '${settingsProvider.directRules.length} rules',
                  description: 'Apps and domains that bypass VPN',
                  color: AppColors.connected,
                  isDark: isDark,
                  onTap: () => _navigateToRules(context, RuleType.direct),
                ),

                const SizedBox(height: 8),

                _RuleCard(
                  icon: Icons.block_rounded,
                  title: 'Block',
                  subtitle: '${settingsProvider.blockRules.length} rules',
                  description: 'Apps and domains that are blocked',
                  color: AppColors.error,
                  isDark: isDark,
                  onTap: () => _navigateToRules(context, RuleType.block),
                ),

                const SizedBox(height: 8),

                _RuleCard(
                  icon: Icons.proxy_rounded,
                  title: 'Proxy',
                  subtitle: '${settingsProvider.proxyRules.length} rules',
                  description: 'Apps and domains that use VPN',
                  color: AppColors.accent,
                  isDark: isDark,
                  onTap: () => _navigateToRules(context, RuleType.proxy),
                ),

                const SizedBox(height: 32),

                // Danger Zone
                _SectionTitle(title: 'Danger Zone', isDark: isDark),
                const SizedBox(height: 12),

                _DangerButton(
                  icon: Icons.delete_sweep_rounded,
                  title: 'Clear All Rules',
                  subtitle: 'Remove all routing rules',
                  isDark: isDark,
                  onTap: () => _showClearConfirm(context, settingsProvider),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _navigateToRules(BuildContext context, RuleType type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RulesScreen(ruleType: type),
      ),
    );
  }

  void _showClearConfirm(BuildContext context, SettingsProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: const Text('Clear All Rules?'),
        content: const Text(
          'This will remove all Direct, Block, and Proxy rules. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.clearAllRules();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All rules cleared'),
                  backgroundColor: AppColors.connected,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

// Section Title Widget
class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionTitle({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

// Setting Card Widget
class _SettingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final Widget trailing;

  const _SettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.surfaceElevated : AppColors.surfaceElevatedLight,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isDark ? AppColors.primary : AppColors.primary).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: isDark ? AppColors.primary : AppColors.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textDarkPrimary : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

// Rule Card Widget
class _RuleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _RuleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textDarkPrimary : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

// Danger Button Widget
class _DangerButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  const _DangerButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.error.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.delete_sweep_rounded, color: AppColors.error, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.error.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.error,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
