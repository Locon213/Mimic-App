/// Android VpnService Platform Channel
/// Handles VPN connection using Android's VpnService API
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'network_stats.dart';

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

  /// Check if platform is Android
  bool get isAndroid => Platform.isAndroid;

  /// Prepare VPN - request permission from user
  Future<bool> prepareVpn() async {
    if (!isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('prepareVpn');
      return result ?? false;
    } catch (e) {
      throw Exception('Failed to prepare VPN: $e');
    }
  }

  /// Connect to VPN
  Future<void> connect(String serverUrl, String mode, {String? serverName}) async {
    if (!isAndroid) {
      // On non-Android, just mock the connection
      await _mockConnect(serverUrl, mode);
      return;
    }

    _serverUrl = serverUrl;
    _serverName = serverName ?? _extractServerName(serverUrl);
    _mode = mode;
    _status = 1; // connecting

    try {
      // Connect to VPN (permission will be requested if needed)
      await _channel.invokeMethod('connectVpn', {
        'serverUrl': serverUrl,
        'serverName': _serverName,
        'mode': mode,
      });

      _status = 2; // connected
      _startStatsPolling();
      _setupEventListener();
    } catch (e) {
      _status = 0;
      throw Exception('Failed to connect to VPN: $e');
    }
  }

  /// Disconnect from VPN
  Future<void> disconnect() async {
    if (!isAndroid) {
      _stopStatsPolling();
      _eventSubscription?.cancel();
      _status = 0;
      _stats = NetworkStats();
      return;
    }

    try {
      await _channel.invokeMethod('disconnectVpn');
    } catch (e) {
      // Ignore errors on disconnect
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
            break;
          case 'disconnected':
            _status = 0;
            _serverUrl = null;
            _serverName = null;
            _stopStatsPolling();
            break;
          case 'error':
            _status = 0;
            final error = event['error'] as String?;
            print('VPN Error: $error');
            break;
        }
      }
    });
  }

  /// Poll stats every second
  void _startStatsPolling() {
    _stopStatsPolling();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_status != 2) {
        timer.cancel();
        return;
      }
      _updateMockStats();
    });
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  /// Mock connection for non-Android platforms
  Future<void> _mockConnect(String serverUrl, String mode) async {
    await Future.delayed(const Duration(seconds: 2));
    _status = 2;
    _serverUrl = serverUrl;
    _mode = mode;
    _startStatsPolling();
  }

  /// Generate mock stats
  int _totalDownload = 0;
  int _totalUpload = 0;

  void _updateMockStats() {
    final downloadSpeed = 1024 * 100 + (DateTime.now().millisecond * 100);
    final uploadSpeed = 512 * 100 + (DateTime.now().millisecond * 50);

    _totalDownload += downloadSpeed;
    _totalUpload += uploadSpeed;

    _stats = NetworkStats(
      downloadSpeed: downloadSpeed,
      uploadSpeed: uploadSpeed,
      ping: 20 + (DateTime.now().millisecond % 30),
      totalDownload: _totalDownload,
      totalUpload: _totalUpload,
    );

    _statsCallback?.call(_stats);
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
