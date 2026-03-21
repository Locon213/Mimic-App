import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';

class SystemTrayService {
  static SystemTrayService? _instance;
  static SystemTrayService get instance {
    _instance ??= SystemTrayService._();
    return _instance!;
  }

  SystemTrayService._();

  final SystemTray _systemTray = SystemTray();
  bool _isInitialized = false;
  VoidCallback? _onShowWindow;
  VoidCallback? _onToggleConnection;
  VoidCallback? _onQuit;
  bool _isConnected = false;

  bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> init({
    required VoidCallback onShowWindow,
    required VoidCallback onToggleConnection,
    required VoidCallback onQuit,
  }) async {
    if (!isSupported || _isInitialized) return;

    _onShowWindow = onShowWindow;
    _onToggleConnection = onToggleConnection;
    _onQuit = onQuit;

    try {
      await _systemTray.initSystemTray(
        title: 'Mimic VPN',
        iconPath: Platform.isWindows
            ? 'assets/icon.png'
            : 'assets/icon.png',
      );

      await _updateMenu();

      _systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) {
          _onShowWindow?.call();
        } else if (eventName == kSystemTrayEventRightClick) {
          _systemTray.popUpContextMenu();
        }
      });

      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize system tray: $e');
    }
  }

  Future<void> _updateMenu() async {
    final Menu menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: _isConnected ? 'Connected' : 'Disconnected',
        enabled: false,
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: _isConnected ? 'Disconnect' : 'Connect',
        onClicked: (menuItem) => _onToggleConnection?.call(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Show Window',
        onClicked: (menuItem) => _onShowWindow?.call(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Quit',
        onClicked: (menuItem) => _onQuit?.call(),
      ),
    ]);

    await _systemTray.setContextMenu(menu);
  }

  Future<void> updateConnectionStatus(bool isConnected) async {
    _isConnected = isConnected;
    if (_isInitialized) {
      await _systemTray.setTitle(isConnected ? 'Mimic VPN - Connected' : 'Mimic VPN');
      await _updateMenu();
    }
  }

  Future<void> dispose() async {
    if (_isInitialized) {
      await _systemTray.destroy();
      _isInitialized = false;
    }
  }
}
