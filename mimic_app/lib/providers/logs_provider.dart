import 'package:flutter/foundation.dart';

import '../models/log_entry.dart';
import '../services/persistent_log_storage.dart';

class LogsProvider extends ChangeNotifier {
  LogsProvider._();

  static final LogsProvider instance = LogsProvider._();

  static const int _maxEntries = 300;
  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries.reversed);

  List<LogEntry> byCategory(LogCategory? category) {
    final data = entries;
    if (category == null) {
      return data;
    }
    return data.where((entry) => entry.category == category).toList();
  }

  void add({
    required LogCategory category,
    required String title,
    required String message,
    LogLevel level = LogLevel.info,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      category: category,
      level: level,
      title: title,
      message: message,
    );

    _entries.add(entry);

    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }

    // Persist to disk (fire and forget)
    PersistentLogStorage.instance.write(entry);

    notifyListeners();
  }

  void info(LogCategory category, String title, String message) =>
      add(category: category, title: title, message: message);

  void warning(LogCategory category, String title, String message) => add(
        category: category,
        title: title,
        message: message,
        level: LogLevel.warning,
      );

  void error(LogCategory category, String title, String message) => add(
        category: category,
        title: title,
        message: message,
        level: LogLevel.error,
      );

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// Load stored logs from disk for a specific date
  Future<List<LogEntry>> loadStoredLogs(DateTime date) async {
    return PersistentLogStorage.instance.readForDate(date);
  }

  /// Get available log dates
  Future<List<DateTime>> getAvailableLogDates() async {
    return PersistentLogStorage.instance.getAvailableDates();
  }

  /// Clear all stored logs from disk
  Future<void> clearStoredLogs() async {
    await PersistentLogStorage.instance.clearAll();
  }
}
