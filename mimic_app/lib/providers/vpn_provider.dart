import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import '../models/network_stats.dart' as models;
import '../models/network_stats.dart';
import '../models/server_config.dart';
import '../services/android_vpn_client.dart';

/// VPN Provider - Manages VPN connection state and statistics
class VpnProvider extends ChangeNotifier {
  ConnectionStatus _status = ConnectionStatus.disconnected;
  models.NetworkStats _stats = models.NetworkStats();
  ServerConfig? _currentServer;
  String _mode = 'TUN'; // Default to TUN
  String? _error;
  final _vpnClient = AndroidVpnClient.instance;

  // Getters
  ConnectionStatus get status => _status;
  models.NetworkStats get stats => _stats;
  ServerConfig? get currentServer => _currentServer;
  String get mode => _mode;
  String? get error => _error;

  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isConnecting => _status == ConnectionStatus.connecting;
  bool get isDisconnected => _status == ConnectionStatus.disconnected;

  /// Check if running on Android
  bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Check if running on mobile platform
  bool get isMobilePlatform =>
      kIsWeb || Platform.isAndroid || Platform.isIOS;

  /// Get available modes based on platform
  List<String> get availableModes {
    if (isMobilePlatform) {
      return ['TUN']; // Only TUN mode on mobile
    }
    return ['Proxy', 'TUN']; // Both modes on desktop
  }

  /// Connect to a server
  Future<void> connect(ServerConfig server, {String? mode}) async {
    try {
      _status = ConnectionStatus.connecting;
      _currentServer = server;
      if (mode != null) {
        _mode = mode;
      }
      _error = null;
      notifyListeners();

      // Connect via Android VpnService on Android
      await _vpnClient.connect(
        server.url,
        _mode,
        serverName: server.displayName,
      );

      _status = ConnectionStatus.connected;

      // Set stats callback
      _vpnClient.setStatsCallback((stats) {
        _stats = stats;
        notifyListeners();
      });

      notifyListeners();

    } catch (e) {
      _status = ConnectionStatus.disconnected;
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Disconnect from current server
  Future<void> disconnect() async {
    try {
      // Disconnect via VpnService
      await _vpnClient.disconnect();

      _status = ConnectionStatus.disconnected;
      _stats = models.NetworkStats();
      _currentServer = null;
      notifyListeners();

    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Set connection mode (only when disconnected)
  Future<void> setMode(String newMode) async {
    if (isConnected || isConnecting) {
      throw Exception('Cannot change mode while connected');
    }
    _mode = newMode;
    notifyListeners();
  }

  /// Toggle connection
  Future<void> toggleConnection() async {
    if (isConnected) {
      await disconnect();
    } else if (_currentServer != null) {
      await connect(_currentServer!, mode: _mode);
    }
  }

  /// Reconnect to current server
  Future<void> reconnect() async {
    if (_currentServer != null) {
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
      await connect(_currentServer!, mode: _mode);
    }
  }

  /// Get current stats from VPN client
  models.NetworkStats get currentStats => _vpnClient.getStats();

  /// Get server URL from VPN client
  String? get serverUrl => _vpnClient.getServerUrl();

  /// Get server name from VPN client
  String? get serverName => _vpnClient.getServerName();

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
