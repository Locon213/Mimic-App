import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../models/log_entry.dart';
import '../models/network_stats.dart';
import '../providers/logs_provider.dart';

final class _NativeNetworkStats extends Struct {
  @Int64()
  external int downloadSpeed;

  @Int64()
  external int uploadSpeed;

  @Int64()
  external int ping;

  @Int64()
  external int totalDownload;

  @Int64()
  external int totalUpload;

  @Int64()
  external int lastUpdated;
}

typedef _ConnectNative = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _ConnectDart = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _DisconnectNative = Void Function();
typedef _DisconnectDart = void Function();
typedef _GetStatusNative = Int32 Function();
typedef _GetStatusDart = int Function();
typedef _GetStatsNative = _NativeNetworkStats Function();
typedef _GetStatsDart = _NativeNetworkStats Function();
typedef _GetServerNameNative = Pointer<Utf8> Function();
typedef _GetServerNameDart = Pointer<Utf8> Function();
typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);

class DesktopMimicClient {
  DesktopMimicClient._();

  static final DesktopMimicClient instance = DesktopMimicClient._();

  DynamicLibrary? _library;
  _ConnectDart? _connect;
  _DisconnectDart? _disconnect;
  _GetStatusDart? _getStatus;
  _GetStatsDart? _getStats;
  _GetServerNameDart? _getServerName;
  _FreeStringDart? _freeString;
  Timer? _statsTimer;
  NetworkStats _stats = NetworkStats();
  Function(NetworkStats)? _statsCallback;
  final LogsProvider _logs = LogsProvider.instance;

  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> connect(String serverUrl, String mode, {String? serverName}) async {
    if (!isSupported) {
      throw UnsupportedError('Desktop Mimic backend is only available on desktop platforms.');
    }

    final errorMessage = await Isolate.run(
      () => _desktopConnectOnWorker(serverUrl, mode),
    );
    if (errorMessage.isNotEmpty) {
      throw Exception(errorMessage);
    }

    _ensureLoaded();
    _startStatsPolling();
    _logs.info(
      LogCategory.mimicProtocol,
      'Desktop connect',
      'Native desktop backend connected to ${serverName ?? _extractServerName(serverUrl)} in $mode mode.',
    );
  }

  Future<void> disconnect() async {
    if (isSupported) {
      await Isolate.run(_desktopDisconnectOnWorker);
    }
    _stopStatsPolling();
    _stats = NetworkStats();
  }

  bool isConnected() => getStatus() == 2;

  int getStatus() {
    final getStatusFn = _getStatus;
    if (getStatusFn == null) {
      return 0;
    }
    return getStatusFn();
  }

  String getStatusString() {
    switch (getStatus()) {
      case 2:
        return 'connected';
      case 1:
        return 'connecting';
      case 3:
        return 'reconnecting';
      default:
        return 'disconnected';
    }
  }

  NetworkStats getStats() => _stats;

  String? getServerName() {
    final getServerNameFn = _getServerName;
    final freeStringFn = _freeString;
    if (getServerNameFn == null || freeStringFn == null) {
      return null;
    }

    final ptr = getServerNameFn();
    final value = ptr.toDartString();
    freeStringFn(ptr);
    return value.isEmpty ? null : value;
  }

  void setStatsCallback(Function(NetworkStats) callback) {
    _statsCallback = callback;
  }

  void _ensureLoaded() {
    if (_library != null) {
      return;
    }

    final library = _openLibrary();
    if (library == null) {
      throw StateError('Desktop backend library was not found.');
    }

    _library = library;
    _connect = library.lookupFunction<_ConnectNative, _ConnectDart>(
      'MimicClient_Connect',
    );
    _disconnect = library.lookupFunction<_DisconnectNative, _DisconnectDart>(
      'MimicClient_Disconnect',
    );
    _getStatus = library.lookupFunction<_GetStatusNative, _GetStatusDart>(
      'MimicClient_GetStatus',
    );
    _getStats = library.lookupFunction<_GetStatsNative, _GetStatsDart>(
      'MimicClient_GetStats',
    );
    _getServerName = library.lookupFunction<_GetServerNameNative, _GetServerNameDart>(
      'MimicClient_GetServerName',
    );
    _freeString = library.lookupFunction<_FreeStringNative, _FreeStringDart>(
      'MimicClient_FreeString',
    );
  }

  DynamicLibrary? _openLibrary() {
    return _openDesktopLibrary();
  }

  void _startStatsPolling() {
    _stopStatsPolling();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final getStatsFn = _getStats;
      if (getStatsFn == null) {
        return;
      }

      final nativeStats = getStatsFn();
      _stats = NetworkStats(
        downloadSpeed: nativeStats.downloadSpeed,
        uploadSpeed: nativeStats.uploadSpeed,
        ping: nativeStats.ping,
        totalDownload: nativeStats.totalDownload,
        totalUpload: nativeStats.totalUpload,
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(
          nativeStats.lastUpdated * 1000,
          isUtc: true,
        ).toLocal(),
      );
      _statsCallback?.call(_stats);
    });
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  String _extractServerName(String url) {
    final hashParts = url.split('#');
    if (hashParts.length > 1) {
      return hashParts[1];
    }
    final atParts = url.split('@');
    if (atParts.length > 1) {
      final hostPart = atParts[1];
      final endIdx = hostPart.indexOf('?');
      if (endIdx != -1) {
        return hostPart.substring(0, endIdx);
      }
      return hostPart;
    }
    return 'Unknown Server';
  }
}

String _desktopConnectOnWorker(String serverUrl, String mode) {
  final library = _openDesktopLibrary();
  if (library == null) {
    return 'Desktop backend library was not found.';
  }

  final connectFn = library.lookupFunction<_ConnectNative, _ConnectDart>(
    'MimicClient_Connect',
  );
  final freeStringFn = library.lookupFunction<_FreeStringNative, _FreeStringDart>(
    'MimicClient_FreeString',
  );

  final urlPtr = serverUrl.toNativeUtf8();
  final modePtr = mode.toNativeUtf8();

  try {
    final errorPtr = connectFn(urlPtr, modePtr);
    final errorMessage = errorPtr.toDartString();
    freeStringFn(errorPtr);
    return errorMessage;
  } finally {
    calloc.free(urlPtr);
    calloc.free(modePtr);
  }
}

void _desktopDisconnectOnWorker() {
  final library = _openDesktopLibrary();
  if (library == null) {
    return;
  }

  final disconnectFn = library.lookupFunction<_DisconnectNative, _DisconnectDart>(
    'MimicClient_Disconnect',
  );
  disconnectFn();
}

DynamicLibrary? _openDesktopLibrary() {
  final executableDir = File(Platform.resolvedExecutable).parent.path;
  final candidates = <String>{
    if (Platform.isWindows) ...{
      'mimic.dll',
      '$executableDir\\mimic.dll',
      '$executableDir\\data\\flutter_assets\\mimic.dll',
      '$executableDir\\data\\mimic.dll',
      '$executableDir\\lib\\mimic.dll',
    },
    if (Platform.isLinux) ...{
      'libmimic.so',
      '$executableDir/libmimic.so',
      '$executableDir/lib/libmimic.so',
    },
    if (Platform.isMacOS) ...{
      'libmimic.dylib',
      '$executableDir/libmimic.dylib',
      '$executableDir/../Frameworks/libmimic.dylib',
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
