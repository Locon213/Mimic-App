/// Android VpnService Platform Channel
/// Handles VPN connection using Android's VpnService API
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import '../models/log_entry.dart';
import '../models/network_stats.dart';
import '../providers/logs_provider.dart';

/// Android VpnService client for real VPN connections
class AndroidVpnClient {
  static AndroidVpnClient? _instance;

  static AndroidVpnClient get instance {
    _instance ??= AndroidVpnClient._();
    return _instance!;
  }

  AndroidVpnClient._();

  /// Platform channel for VPN commands
  static const MethodChannel _channel = MethodChannel('com.locon213.mimic_app/vpn');

  /// Event channel for VPN status updates
  static const EventChannel _eventChannel =
      EventChannel('com.locon213.mimic_app/vpn_events');

  int _status = 0; // 0=disconnected, 1=connecting, 2=connected
  String? _serverUrl;
  String? _serverName;
  String _mode = 'TUN';
  NetworkStats _stats = NetworkStats();
  Function(NetworkStats)? _statsCallback;
  Timer? _statsTimer;
  StreamSubscription? _eventSubscription;
  final LogsProvider _logs = LogsProvider.instance;

  /// Check if platform is Android
  bool get isAndroid => Platform.isAndroid;

  /// Prepare VPN - request permission from user
  Future<bool> prepareVpn() async {
    if (!isAndroid) return false;

    try {
      _logs.info(
        LogCategory.system,
        'VPN permission check',
        'Requesting Android VpnService preparation state.',
      );
      final result = await _channel.invokeMethod<bool>('prepareVpn');
      return result ?? false;
    } catch (e) {
      _logs.error(
        LogCategory.system,
        'VPN permission check failed',
        e.toString(),
      );
      throw Exception('Failed to prepare VPN: $e');
    }
  }

  /// Connect to VPN
  Future<void> connect(String serverUrl, String mode, {String? serverName}) async {
    _serverUrl = serverUrl;
    _serverName = serverName ?? _extractServerName(serverUrl);
    _mode = mode;
    _status = 1; // connecting

    if (!isAndroid) {
      throw UnsupportedError('Android VPN client can only be used on Android.');
    }

    try {
      _setupEventListener();
      _logs.info(
        LogCategory.mimicProtocol,
        'Native connect',
        'Calling platform channel for ${_serverName ?? serverUrl} in $mode mode.',
      );
      // Connect to VPN (permission will be requested if needed)
      await _channel.invokeMethod('connectVpn', {
        'serverUrl': serverUrl,
        'serverName': _serverName,
        'mode': mode,
      });
    } catch (e) {
      _status = 0;
      _logs.error(
        LogCategory.mimicProtocol,
        'Native connect failed',
        e.toString(),
      );
      throw Exception('Failed to connect to VPN: $e');
    }
  }

  /// Disconnect from VPN
  Future<void> disconnect() async {
    if (!isAndroid) {
      throw UnsupportedError('Android VPN client can only be used on Android.');
    }

    try {
      await _channel.invokeMethod('disconnectVpn');
    } catch (e) {
      _logs.warning(
        LogCategory.mimicProtocol,
        'Native disconnect warning',
        e.toString(),
      );
    }

    _stopStatsPolling();
    _eventSubscription?.cancel();
    _status = 0;
    _stats = NetworkStats();
    _serverUrl = null;
    _serverName = null;
  }

  /// Check if connected
  bool isConnected() => _status == 2;

  /// Get current status
  int getStatus() => _status;

  /// Get status as string
  String getStatusString() {
    switch (_status) {
      case 2:
        return 'connected';
      case 1:
        return 'connecting';
      default:
        return 'disconnected';
    }
  }

  /// Get current stats
  NetworkStats getStats() => _stats;

  /// Get server URL
  String? getServerUrl() => _serverUrl;

  /// Get server name
  String? getServerName() => _serverName;

  /// Set stats callback
  void setStatsCallback(Function(NetworkStats) callback) {
    _statsCallback = callback;
  }

  /// Setup event listener for VPN status changes
  void _setupEventListener() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final eventType = event['event'] as String?;
        switch (eventType) {
          case 'connected':
            _status = 2;
            _serverUrl = event['serverUrl'] as String?;
            _serverName = event['serverName'] as String?;
            _startStatsPolling();
            _logs.info(
              LogCategory.system,
              'Android VPN event',
              'Platform reported connected state.',
            );
            break;
          case 'disconnected':
            _status = 0;
            _serverUrl = null;
            _serverName = null;
            _stopStatsPolling();
            _logs.info(
              LogCategory.system,
              'Android VPN event',
              'Platform reported disconnected state.',
            );
            break;
          case 'error':
            _status = 0;
            _stopStatsPolling();
            final error = event['error'] as String?;
            _logs.error(
              LogCategory.system,
              'Android VPN error',
              error ?? 'Unknown VPN platform error',
            );
            break;
        }
      }
    });
  }

  /// Poll stats every second
  void _startStatsPolling() {
    _stopStatsPolling();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_status != 2) {
        timer.cancel();
        return;
      }

      try {
        final result = await _channel.invokeMapMethod<String, dynamic>('getStats');
        if (result != null) {
          _stats = NetworkStats(
            downloadSpeed: result['downloadSpeed'] as int? ?? 0,
            uploadSpeed: result['uploadSpeed'] as int? ?? 0,
            ping: result['ping'] as int? ?? 0,
            totalDownload: result['totalDownload'] as int? ?? 0,
            totalUpload: result['totalUpload'] as int? ?? 0,
          );
          _statsCallback?.call(_stats);
          return;
        }
      } catch (e) {
        _logs.warning(
          LogCategory.mimicProtocol,
          'Native stats fallback',
          e.toString(),
        );
      }
    });
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  /// Extract server name from URL
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
