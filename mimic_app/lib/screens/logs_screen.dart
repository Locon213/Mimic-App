import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/log_entry.dart';
import '../providers/logs_provider.dart';
import '../utils/app_theme.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> with SingleTickerProviderStateMixin {
  DateTime? _selectedDate;
  List<LogEntry> _storedLogs = [];
  List<DateTime> _availableDates = [];
  bool _loadingStored = false;
  late TabController _tabController;

  static const List<_LogsTab> _tabs = [
    _LogsTab('Live', null),
    _LogsTab('VPN', LogCategory.vpn),
    _LogsTab('Protocol', LogCategory.mimicProtocol),
    _LogsTab('System', LogCategory.system),
    _LogsTab('UI', LogCategory.ui),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadAvailableDates();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableDates() async {
    final dates = await context.read<LogsProvider>().getAvailableLogDates();
    if (mounted) {
      setState(() => _availableDates = dates);
    }
  }

  Future<void> _loadStoredLogs(DateTime date) async {
    setState(() {
      _loadingStored = true;
      _selectedDate = date;
    });
    final logs = await context.read<LogsProvider>().loadStoredLogs(date);
    if (mounted) {
      setState(() {
        _storedLogs = logs;
        _loadingStored = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now.subtract(const Duration(days: 2)),
      lastDate: now,
      selectableDayPredicate: (date) {
        // Only allow dates that have log files
        if (_availableDates.isEmpty) return true;
        return _availableDates.any((d) =>
            d.year == date.year && d.month == date.month && d.day == date.day);
      },
    );
    if (picked != null) {
      await _loadStoredLogs(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          // Date picker for stored logs
          IconButton(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded),
            tooltip: 'View stored logs',
          ),
          if (_selectedDate != null)
            IconButton(
              onPressed: () {
                setState(() {
                  _selectedDate = null;
                  _storedLogs = [];
                });
              },
              icon: const Icon(Icons.live_tv_rounded),
              tooltip: 'Back to live',
            ),
          IconButton(
            onPressed: () => _showClearDialog(context),
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear logs',
          ),
        ],
        bottom: TabBar(
          isScrollable: true,
          controller: _tabController,
          tabs: _tabs.map((tab) => Tab(text: tab.label)).toList(),
        ),
      ),
      body: Container(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        child: Column(
          children: [
            // Stored logs info bar
            if (_selectedDate != null)
              _buildStoredInfoBar(isDark),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _tabs.map((tab) {
                  if (_selectedDate != null) {
                    return _buildStoredList(tab.category, isDark);
                  }
                  return _LiveLogsList(category: tab.category);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoredInfoBar(bool isDark) {
    final dateStr = DateFormat('dd.MM.yyyy').format(_selectedDate!);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(
            color: AppColors.primary.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            'Stored logs: $dateStr',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const Spacer(),
          Text(
            '${_storedLogs.length} entries',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoredList(LogCategory? category, bool isDark) {
    if (_loadingStored) {
      return const Center(child: CircularProgressIndicator());
    }

    var logs = _storedLogs;
    if (category != null) {
      logs = logs.where((e) => e.category == category).toList();
    }

    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 48,
              color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'No logs for this date',
              style: TextStyle(
                color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _LogCard(entry: logs[index]),
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Logs'),
        content: const Text(
          'This will clear live logs and delete all stored log files. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              context.read<LogsProvider>().clear();
              await context.read<LogsProvider>().clearStoredLogs();
              if (context.mounted) {
                Navigator.pop(context);
                setState(() {
                  _selectedDate = null;
                  _storedLogs = [];
                  _availableDates = [];
                });
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

class _LogsTab {
  const _LogsTab(this.label, this.category);

  final String label;
  final LogCategory? category;
}

/// Live logs list (from memory)
class _LiveLogsList extends StatelessWidget {
  const _LiveLogsList({required this.category});

  final LogCategory? category;

  @override
  Widget build(BuildContext context) {
    return Consumer<LogsProvider>(
      builder: (context, logsProvider, child) {
        final logs = logsProvider.byCategory(category);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        if (logs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sensors_rounded,
                  size: 48,
                  color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                ),
                const SizedBox(height: 12),
                Text(
                  'No live logs yet',
                  style: TextStyle(
                    color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _labelForCategory(entry.category),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Level indicator
              Icon(
                switch (entry.level) {
                  LogLevel.info => Icons.info_outline_rounded,
                  LogLevel.warning => Icons.warning_amber_rounded,
                  LogLevel.error => Icons.error_outline_rounded,
                },
                size: 14,
                color: accent,
              ),
              const Spacer(),
              Text(
                entry.formattedTime,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textDarkPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            entry.message,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
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
        return 'Mimic';
      case LogCategory.system:
        return 'System';
      case LogCategory.ui:
        return 'UI';
    }
  }
}
