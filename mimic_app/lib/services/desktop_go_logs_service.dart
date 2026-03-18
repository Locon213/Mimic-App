import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';

import '../models/log_entry.dart';
import '../providers/logs_provider.dart';

typedef _PollLogNative = Pointer<Utf8> Function();
typedef _PollLogDart = Pointer<Utf8> Function();
typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);

class DesktopGoLogsService {
  DesktopGoLogsService._();

  static final DesktopGoLogsService instance = DesktopGoLogsService._();

  DynamicLibrary? _library;
  _PollLogDart? _pollLog;
  _FreeStringDart? _freeString;
  Timer? _pollTimer;
  bool _started = false;

  void start() {
    if (_started || kIsWeb) {
      return;
    }

    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }

    try {
      _library = _openLibrary();
      if (_library == null) {
        LogsProvider.instance.warning(
          LogCategory.system,
          'Go backend logs unavailable',
          'Desktop backend library was not found for FFI log polling.',
        );
        return;
      }

      _pollLog = _library!.lookupFunction<_PollLogNative, _PollLogDart>(
        'MimicClient_PollLog',
      );
      _freeString = _library!.lookupFunction<_FreeStringNative, _FreeStringDart>(
        'MimicClient_FreeString',
      );

      _started = true;
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 700),
        (_) => _drainLogs(),
      );
      LogsProvider.instance.info(
        LogCategory.system,
        'Go backend log bridge',
        'Desktop FFI log polling initialized.',
      );
    } catch (e) {
      LogsProvider.instance.warning(
        LogCategory.system,
        'Go backend logs unavailable',
        e.toString(),
      );
    }
  }

  DynamicLibrary? _openLibrary() {
    final candidates = <String>{
      if (Platform.isWindows) ...{
        'mimic.dll',
        '${File(Platform.resolvedExecutable).parent.path}\\mimic.dll',
        '${File(Platform.resolvedExecutable).parent.path}\\lib\\mimic.dll',
        '${File(Platform.resolvedExecutable).parent.path}\\data\\mimic.dll',
      },
      if (Platform.isLinux) ...{
        'libmimic.so',
        '${File(Platform.resolvedExecutable).parent.path}/libmimic.so',
        '${File(Platform.resolvedExecutable).parent.path}/lib/libmimic.so',
      },
      if (Platform.isMacOS) ...{
        'libmimic.dylib',
        '${File(Platform.resolvedExecutable).parent.path}/libmimic.dylib',
        '${File(Platform.resolvedExecutable).parent.path}/../Frameworks/libmimic.dylib',
      },
    };

    for (final candidate in candidates) {
      try {
        return DynamicLibrary.open(candidate);
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  void _drainLogs() {
    if (_pollLog == null || _freeString == null) {
      return;
    }

    for (var i = 0; i < 32; i++) {
      final ptr = _pollLog!();
      if (ptr.address == 0) {
        return;
      }

      final raw = ptr.toDartString();
      _freeString!(ptr);

      if (raw.isEmpty) {
        return;
      }

      _handlePayload(raw);
    }
  }

  void _handlePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final source = decoded['source'] as String? ?? 'GoBackend';
      final message = decoded['message'] as String? ?? raw;
      final level = decoded['level'] as String? ?? 'info';

      switch (level) {
        case 'error':
          LogsProvider.instance.error(LogCategory.mimicProtocol, source, message);
          break;
        case 'warning':
          LogsProvider.instance.warning(
            LogCategory.mimicProtocol,
            source,
            message,
          );
          break;
        default:
          LogsProvider.instance.info(
            LogCategory.mimicProtocol,
            source,
            message,
          );
          break;
      }
    } catch (_) {
      LogsProvider.instance.info(
        LogCategory.mimicProtocol,
        'GoBackend',
        raw,
      );
    }
  }
}
