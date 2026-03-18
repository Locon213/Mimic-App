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
}
