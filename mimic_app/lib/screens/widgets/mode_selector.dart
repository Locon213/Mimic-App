import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/vpn_provider.dart';
import '../../utils/app_theme.dart';

/// Mode Selector - Toggle between Proxy and TUN modes
class ModeSelector extends StatelessWidget {
  const ModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VpnProvider>(
      builder: (context, vpnProvider, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final currentMode = vpnProvider.mode;
        final availableModes = vpnProvider.availableModes;

        // Only show on desktop (mobile has TUN only)
        if (availableModes.length <= 1) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? AppColors.surfaceElevated
                  : AppColors.surfaceElevatedLight,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: isDark
                        ? AppColors.textDarkSecondary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Connection Mode',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textDarkPrimary
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Mode Toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceElevated
                      : AppColors.surfaceElevatedLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ModeButton(
                        icon: Icons.security_rounded,
                        label: 'Proxy',
                        subtitle: 'HTTPS/SOCKS5',
                        isSelected: currentMode == 'Proxy',
                        isDark: isDark,
                        onTap: vpnProvider.isDisconnected
                            ? () => vpnProvider.setMode('Proxy')
                            : null,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _ModeButton(
                        icon: Icons.public_rounded,
                        label: 'TUN',
                        subtitle: 'Global Routing',
                        isSelected: currentMode == 'TUN',
                        isDark: isDark,
                        onTap: vpnProvider.isDisconnected
                            ? () => vpnProvider.setMode('TUN')
                            : null,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Mode description
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: currentMode == 'Proxy'
                      ? AppColors.primary.withOpacity(0.1)
                      : AppColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: currentMode == 'Proxy'
                          ? AppColors.primary
                          : AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        currentMode == 'Proxy'
                            ? 'Route specific traffic through proxy. Suitable for browsers and apps.'
                            : 'Route all device traffic through VPN. Requires admin/root privileges.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.textDarkSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Warning when connected
              if (vpnProvider.isConnected || vpnProvider.isConnecting)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Disconnect to change mode',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppColors.textDarkSecondary
                                : AppColors.textSecondary,
                          ),
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
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final bool isDark;
  final VoidCallback? onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? Colors.white
                  : (isDark ? AppColors.textDarkSecondary : AppColors.textSecondary),
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppColors.textDarkPrimary : AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? Colors.white.withOpacity(0.8)
                    : (isDark ? AppColors.textDarkSecondary : AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
