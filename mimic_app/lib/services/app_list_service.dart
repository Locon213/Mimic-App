import 'package:flutter/services.dart';
import 'dart:io';

/// Service for getting installed apps on Android
class AppListService {
  static const MethodChannel _channel = MethodChannel('com.locon213.mimic/app_list');

  /// Get list of installed apps on Android
  /// Returns a list of maps with 'packageName' and 'appName' keys
  static Future<List<Map<String, String>>> getInstalledApps() async {
    if (!Platform.isAndroid) {
      return [];
    }

    try {
      final List<dynamic> result = await _channel.invokeMethod('getInstalledApps');
      return result.map((app) {
        return {
          'packageName': app['packageName'] as String? ?? '',
          'appName': app['appName'] as String? ?? '',
        };
      }).toList();
    } on PlatformException catch (e) {
      print('Failed to get installed apps: ${e.message}');
      return [];
    }
  }

  /// Get app icon as base64 string
  static Future<String?> getAppIcon(String packageName) async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final String? result = await _channel.invokeMethod('getAppIcon', {
        'packageName': packageName,
      });
      return result;
    } on PlatformException catch (e) {
      print('Failed to get app icon: ${e.message}');
      return null;
    }
  }
}
