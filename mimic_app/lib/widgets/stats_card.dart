import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../providers/vpn_provider.dart';
import '../utils/app_theme.dart';

/// Statistics Card - Shows real-time network statistics
class StatsCard extends StatelessWidget {
  const StatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VpnProvider>(
      builder: (context, vpnProvider, child) {
        final stats = vpnProvider.stats;
        final isDark = Theme.of(context).brightness == Brightness.dark;

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
                    Icons.speed_rounded,
                    size: 20,
                    color: isDark
                        ? AppColors.textDarkSecondary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Network Statistics',
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

              const SizedBox(height: 20),

              // Speed Gauges
              Row(
                children: [
                  Expanded(
                    child: _SpeedGauge(
                      title: 'Download',
                      value: stats.downloadSpeedString,
                      icon: Icons.download_rounded,
                      color: AppColors.connected,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SpeedGauge(
                      title: 'Upload',
                      value: stats.uploadSpeedString,
                      icon: Icons.upload_rounded,
                      color: AppColors.accent,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Divider
              Container(
                height: 1,
                color: isDark
                    ? AppColors.surfaceElevated
                    : AppColors.surfaceElevatedLight,
              ),

              const SizedBox(height: 16),

              // Total Traffic & Ping
              Row(
                children: [
                  Expanded(
                    child: _StatItem(
                      label: 'Total Download',
                      value: stats.totalDownloadString,
                      icon: Icons.download_done_rounded,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StatItem(
                      label: 'Total Upload',
                      value: stats.totalUploadString,
                      icon: Icons.upload_file_rounded,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Ping
              Row(
                children: [
                  Expanded(
                    child: _StatItem(
                      label: 'Ping',
                      value: '${stats.ping} ms',
                      icon: Icons.signal_cellular_alt_rounded,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SpeedGauge extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool isDark;

  const _SpeedGauge({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isDark;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.textDarkSecondary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textDarkPrimary : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
