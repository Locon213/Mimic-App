import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/log_entry.dart';

/// Persistent log storage that saves logs to daily files.
/// Retains logs for [retentionDays] (default 3), auto-cleans older files.
class PersistentLogStorage {
  static final PersistentLogStorage instance = PersistentLogStorage._();
  PersistentLogStorage._();

  static const int retentionDays = 3;
  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 5MB per day

  Directory? _logDir;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _logDir = Directory('${appDir.path}/mimic_logs');
      if (!await _logDir!.exists()) {
        await _logDir!.create(recursive: true);
      }
      _initialized = true;
      await _cleanOldLogs();
    } catch (e) {
      debugPrint('Failed to init log storage: $e');
    }
  }

  /// Write a log entry to today's log file
  Future<void> write(LogEntry entry) async {
    if (!_initialized || _logDir == null) return;
    try {
      final file = _fileForDate(DateTime.now());

      // Check file size and rotate if needed
      if (await file.exists()) {
        final stat = await file.stat();
        if (stat.size > _maxFileSizeBytes) {
          // Rename current file with timestamp suffix
          final ts = DateTime.now().millisecondsSinceEpoch;
          await file.copy('${file.path}.$ts');
          await file.delete();
        }
      }

      final sink = file.openWrite(mode: FileMode.append);
      final line = jsonEncode(entry.toJson());
      sink.writeln(line);
      await sink.flush();
      await sink.close();
    } catch (e) {
      debugPrint('Failed to write log: $e');
    }
  }

  /// Read all logs for a specific date
  Future<List<LogEntry>> readForDate(DateTime date) async {
    if (!_initialized || _logDir == null) return [];
    try {
      final file = _fileForDate(date);
      if (!await file.exists()) return [];

      final lines = await file.readAsLines();
      final entries = <LogEntry>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          entries.add(LogEntry.fromJson(json));
        } catch (_) {
          // Skip malformed lines
        }
      }
      return entries;
    } catch (e) {
      debugPrint('Failed to read logs: $e');
      return [];
    }
  }

  /// Read logs for today
  Future<List<LogEntry>> readToday() => readForDate(DateTime.now());

  /// Get available log dates (up to retentionDays)
  Future<List<DateTime>> getAvailableDates() async {
    if (!_initialized || _logDir == null) return [];
    try {
      final dates = <DateTime>[];
      final files = await _logDir!.list().toList();
      for (final file in files) {
        if (file is File) {
          final name = file.uri.pathSegments.last;
          final date = _parseDateFromFilename(name);
          if (date != null && !dates.contains(date)) {
            dates.add(date);
          }
        }
      }
      dates.sort((a, b) => b.compareTo(a)); // newest first
      return dates;
    } catch (e) {
      debugPrint('Failed to get dates: $e');
      return [];
    }
  }

  /// Clear all stored logs
  Future<void> clearAll() async {
    if (!_initialized || _logDir == null) return;
    try {
      if (await _logDir!.exists()) {
        await _logDir!.delete(recursive: true);
        await _logDir!.create(recursive: true);
      }
    } catch (e) {
      debugPrint('Failed to clear logs: $e');
    }
  }

  /// Delete logs older than retentionDays
  Future<void> _cleanOldLogs() async {
    if (_logDir == null) return;
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: retentionDays));
      final files = await _logDir!.list().toList();
      for (final file in files) {
        if (file is File) {
          final name = file.uri.pathSegments.last;
          final date = _parseDateFromFilename(name);
          if (date != null && date.isBefore(cutoff)) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to clean old logs: $e');
    }
  }

  File _fileForDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return File('${_logDir!.path}/$y-$m-$d.jsonl');
  }

  DateTime? _parseDateFromFilename(String name) {
    // Format: YYYY-MM-DD.jsonl or YYYY-MM-DD.jsonl.TS
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})\.jsonl').firstMatch(name);
    if (match == null) return null;
    try {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    } catch (_) {
      return null;
    }
  }
}
