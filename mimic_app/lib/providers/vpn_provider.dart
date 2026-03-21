import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import '../models/network_stats.dart' as models;
import '../models/log_entry.dart';
import '../models/network_stats.dart';
import '../models/server_config.dart';
import 'logs_provider.dart';
import '../services/android_vpn_client.dart';
import '../services/desktop_mimic_client.dart';
import '../services/system_tray_service.dart';

/// VPN Provider - Manages VPN connection state and statistics
class VpnProvider extends ChangeNotifier {
  ConnectionStatus _status = ConnectionStatus.disconnected;
  models.NetworkStats _stats = models.NetworkStats();
  ServerConfig? _currentServer;
  String _mode = 'TUN'; // Default to TUN
  String? _error;
  final _vpnClient = AndroidVpnClient.instance;
  final _desktopClient = DesktopMimicClient.instance;
  final _logs = LogsProvider.instance;

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

  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

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
      _logs.info(
        LogCategory.vpn,
        'Connection requested',
        'Connecting to ${server.displayName} using ${mode ?? _mode} mode.',
      );
      _status = ConnectionStatus.connecting;
      _currentServer = server;
      if (mode != null) {
        _mode = mode;
      }
      _error = null;
      notifyListeners();

      if (isAndroid) {
        await _vpnClient.connect(
          server.url,
          _mode,
          serverName: server.displayName,
        );
      } else if (isDesktop) {
        await _desktopClient.connect(
          server.url,
          _mode,
          serverName: server.displayName,
        );
      } else {
        throw UnsupportedError('VPN connection is not implemented for this platform.');
      }

      _status = ConnectionStatus.connected;
      _logs.info(
        LogCategory.vpn,
        'Connected',
        'VPN connected to ${server.displayName}.',
      );

      _setStatsCallback((stats) {
        _stats = stats;
        notifyListeners();
      });

      // Update system tray
      SystemTrayService.instance.updateConnectionStatus(true);

      notifyListeners();

    } catch (e) {
      _status = ConnectionStatus.disconnected;
      _error = e.toString();
      _logs.error(
        LogCategory.vpn,
        'Connection failed',
        e.toString(),
      );
      notifyListeners();
      rethrow;
    }
  }

  /// Disconnect from current server
  Future<void> disconnect() async {
    try {
      final serverName = _currentServer?.displayName ?? 'current server';
      if (isAndroid) {
        await _vpnClient.disconnect();
      } else if (isDesktop) {
        await _desktopClient.disconnect();
      }

      _status = ConnectionStatus.disconnected;
      _stats = models.NetworkStats();
      _currentServer = null;

      // Update system tray
      SystemTrayService.instance.updateConnectionStatus(false);

      _logs.info(
        LogCategory.vpn,
        'Disconnected',
        'VPN disconnected from $serverName.',
      );
      notifyListeners();

    } catch (e) {
      _error = e.toString();
      _logs.error(
        LogCategory.vpn,
        'Disconnect failed',
        e.toString(),
      );
      notifyListeners();
    }
  }

  /// Set connection mode (only when disconnected)
  Future<void> setMode(String newMode) async {
    if (isConnected || isConnecting) {
      _logs.warning(
        LogCategory.ui,
        'Mode change blocked',
        'Cannot change VPN mode while a connection is active.',
      );
      throw Exception('Cannot change mode while connected');
    }
    _logs.info(
      LogCategory.ui,
      'Mode changed',
      'Desktop VPN mode switched to $newMode.',
    );
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
  models.NetworkStats get currentStats =>
      isDesktop ? _desktopClient.getStats() : _vpnClient.getStats();

  /// Get server URL from VPN client
  String? get serverUrl => _currentServer?.url;

  /// Get server name from VPN client
  String? get serverName =>
      isDesktop ? _desktopClient.getServerName() : _vpnClient.getServerName();

  void _setStatsCallback(void Function(models.NetworkStats) callback) {
    if (isDesktop) {
      _desktopClient.setStatsCallback(callback);
      return;
    }
    _vpnClient.setStatsCallback(callback);
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
