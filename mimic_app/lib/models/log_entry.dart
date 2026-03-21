enum LogCategory { vpn, mimicProtocol, system, ui }

enum LogLevel { info, warning, error }

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.category,
    required this.level,
    required this.title,
    required this.message,
  });

  final DateTime timestamp;
  final LogCategory category;
  final LogLevel level;
  final String title;
  final String message;

  Map<String, dynamic> toJson() => {
        'ts': timestamp.millisecondsSinceEpoch,
        'cat': category.name,
        'lvl': level.name,
        't': title,
        'm': message,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
        category: LogCategory.values.firstWhere(
          (c) => c.name == json['cat'],
          orElse: () => LogCategory.system,
        ),
        level: LogLevel.values.firstWhere(
          (l) => l.name == json['lvl'],
          orElse: () => LogLevel.info,
        ),
        title: json['t'] as String? ?? '',
        message: json['m'] as String? ?? '',
      );

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
