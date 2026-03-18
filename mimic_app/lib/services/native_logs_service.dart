import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/log_entry.dart';
import '../providers/logs_provider.dart';

class NativeLogsService {
  NativeLogsService._();

  static final NativeLogsService instance = NativeLogsService._();
  static const EventChannel _channel =
      EventChannel('com.locon213.mimic_app/native_logs');

  StreamSubscription? _subscription;
  bool _started = false;

  void start() {
    if (_started || kIsWeb) {
      return;
    }

    if (!(Platform.isAndroid || Platform.isWindows || Platform.isLinux)) {
      return;
    }

    _started = true;
    _subscription = _channel.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (Object error) {
        LogsProvider.instance.warning(
          LogCategory.system,
          'Native logs unavailable',
          error.toString(),
        );
      },
    );
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) {
      return;
    }

    final source = event['source'] as String? ?? 'Native';
    final message = event['message'] as String? ?? 'Unknown native event';
    final level = event['level'] as String? ?? 'info';

    final category = _categoryForSource(source);
    switch (level) {
      case 'error':
        LogsProvider.instance.error(category, source, message);
        break;
      case 'warning':
        LogsProvider.instance.warning(category, source, message);
        break;
      default:
        LogsProvider.instance.info(category, source, message);
        break;
    }
  }

  LogCategory _categoryForSource(String source) {
    final lower = source.toLowerCase();
    if (lower.contains('vpn')) {
      return LogCategory.vpn;
    }
    if (lower.contains('mimic')) {
      return LogCategory.mimicProtocol;
    }
    return LogCategory.system;
  }
}
