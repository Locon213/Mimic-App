import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/log_entry.dart';
import '../providers/logs_provider.dart';
import '../utils/app_theme.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  static const List<_LogsTab> _tabs = [
    _LogsTab('All', null),
    _LogsTab('VPN', LogCategory.vpn),
    _LogsTab('Mimic Protocol', LogCategory.mimicProtocol),
    _LogsTab('System', LogCategory.system),
    _LogsTab('UI', LogCategory.ui),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Logs'),
          actions: [
            IconButton(
              onPressed: () => context.read<LogsProvider>().clear(),
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Clear logs',
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: _tabs.map((tab) => Tab(text: tab.label)).toList(),
          ),
        ),
        body: Container(
          color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
          child: TabBarView(
            children:
                _tabs.map((tab) => _LogsList(category: tab.category)).toList(),
          ),
        ),
      ),
    );
  }
}

class _LogsTab {
  const _LogsTab(this.label, this.category);

  final String label;
  final LogCategory? category;
}

class _LogsList extends StatelessWidget {
  const _LogsList({required this.category});

  final LogCategory? category;

  @override
  Widget build(BuildContext context) {
    return Consumer<LogsProvider>(
      builder: (context, logsProvider, child) {
        final logs = logsProvider.byCategory(category);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        if (logs.isEmpty) {
          return Center(
            child: Text(
              'No logs yet',
              style: TextStyle(
                color: isDark
                    ? AppColors.textDarkSecondary
                    : AppColors.textSecondary,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _LogCard(entry: logs[index]),
        );
      },
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = switch (entry.level) {
      LogLevel.info => AppColors.accent,
      LogLevel.warning => AppColors.warning,
      LogLevel.error => AppColors.error,
    };

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceElevatedLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _labelForCategory(entry.category),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatTime(entry.timestamp),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.textDarkSecondary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            entry.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color:
                  isDark ? AppColors.textDarkPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            entry.message,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color:
                  isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  static String _labelForCategory(LogCategory category) {
    switch (category) {
      case LogCategory.vpn:
        return 'VPN';
      case LogCategory.mimicProtocol:
        return 'Mimic Protocol';
      case LogCategory.system:
        return 'System';
      case LogCategory.ui:
        return 'UI';
    }
  }

  static String _formatTime(DateTime dateTime) {
    final h = dateTime.hour.toString().padLeft(2, '0');
    final m = dateTime.minute.toString().padLeft(2, '0');
    final s = dateTime.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
