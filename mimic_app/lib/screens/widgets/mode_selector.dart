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
        final isProxy = vpnProvider.mode == 'Proxy';

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
                        isSelected: isProxy,
                        isDark: isDark,
                        onTap: () {
                          if (!vpnProvider.isConnected) {
                            // Mode can only be changed when disconnected
                            // This would need to be handled in the provider
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _ModeButton(
                        icon: Icons.public_rounded,
                        label: 'TUN',
                        subtitle: 'Global Routing',
                        isSelected: !isProxy,
                        isDark: isDark,
                        onTap: () {
                          if (!vpnProvider.isConnected) {
                            // Mode can only be changed when disconnected
                          }
                        },
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
                  color: isProxy
                      ? AppColors.primaryStart.withOpacity(0.1)
                      : AppColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      isProxy ? Icons.info_outline : Icons.info_outline,
                      size: 18,
                      color: isProxy
                          ? AppColors.primaryStart
                          : AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isProxy
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
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
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
              color: isSelected ? Colors.white : (isDark ? AppColors.textDarkSecondary : AppColors.textSecondary),
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
