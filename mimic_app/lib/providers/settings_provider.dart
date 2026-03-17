import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/routing_rule.dart';

/// Settings Provider - Manages app settings and routing rules
class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = AppSettings();
  bool _isLoading = false;

  // Getters
  AppSettings get settings => _settings;
  bool get isLoading => _isLoading;
  bool get autoConnect => _settings.autoConnect;
  bool get startOnBoot => _settings.startOnBoot;
  bool get showNotification => _settings.showNotification;
  String get selectedMode => _settings.selectedMode;
  List<RoutingRule> get rules => _settings.rules;

  /// Get rules by type
  List<RoutingRule> getRulesByType(RuleType type) {
    return _settings.rules.where((r) => r.type == type).toList();
  }

  /// Get direct rules
  List<RoutingRule> get directRules => getRulesByType(RuleType.direct);

  /// Get block rules
  List<RoutingRule> get blockRules => getRulesByType(RuleType.block);

  /// Get proxy rules
  List<RoutingRule> get proxyRules => getRulesByType(RuleType.proxy);

  /// Load settings from storage
  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('app_settings');

      if (settingsJson != null) {
        _settings = AppSettings.fromJson(jsonDecode(settingsJson));
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save settings to storage
  Future<void> saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = jsonEncode(_settings.toJson());
      await prefs.setString('app_settings', settingsJson);
    } catch (e) {
      debugPrint('Error saving settings: $e');
      rethrow;
    }
  }

  /// Update settings
  Future<void> updateSettings({
    bool? autoConnect,
    bool? startOnBoot,
    bool? showNotification,
    String? selectedMode,
  }) async {
    _settings = _settings.copyWith(
      autoConnect: autoConnect,
      startOnBoot: startOnBoot,
      showNotification: showNotification,
      selectedMode: selectedMode,
    );
    await saveSettings();
    notifyListeners();
  }

  /// Add routing rule
  Future<void> addRule(RoutingRule rule) async {
    _settings = _settings.copyWith(
      rules: [..._settings.rules, rule],
    );
    await saveSettings();
    notifyListeners();
  }

  /// Update routing rule
  Future<void> updateRule(RoutingRule rule) async {
    final index = _settings.rules.indexWhere((r) => r.id == rule.id);
    if (index == -1) return;

    _settings.rules[index] = rule;
    await saveSettings();
    notifyListeners();
  }

  /// Delete routing rule
  Future<void> deleteRule(String ruleId) async {
    _settings = _settings.copyWith(
      rules: _settings.rules.where((r) => r.id != ruleId).toList(),
    );
    await saveSettings();
    notifyListeners();
  }

  /// Add app to direct rules (Android)
  Future<void> addAppToDirect(String packageName, String appName) async {
    // Check if already exists
    final exists = _settings.rules.any(
      (r) => r.type == RuleType.direct && r.value == packageName,
    );

    if (!exists) {
      final rule = RoutingRule(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: appName,
        value: packageName,
        type: RuleType.direct,
      );
      await addRule(rule);
    }
  }

  /// Remove app from direct rules
  Future<void> removeAppFromDirect(String packageName) async {
    final rule = _settings.rules.firstWhere(
      (r) => r.type == RuleType.direct && r.value == packageName,
    );
    if (rule.id.isNotEmpty) {
      await deleteRule(rule.id);
    }
  }

  /// Check if app is in direct rules
  bool isAppInDirect(String packageName) {
    return _settings.rules.any(
      (r) => r.type == RuleType.direct && r.value == packageName,
    );
  }

  /// Add domain to rule
  Future<void> addDomainRule(String domain, String name, RuleType type) async {
    final rule = RoutingRule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.isEmpty ? domain : name,
      value: domain,
      type: type,
    );
    await addRule(rule);
  }

  /// Clear all rules
  Future<void> clearAllRules() async {
    _settings = _settings.copyWith(rules: []);
    await saveSettings();
    notifyListeners();
  }

  /// Clear rules by type
  Future<void> clearRulesByType(RuleType type) async {
    _settings = _settings.copyWith(
      rules: _settings.rules.where((r) => r.type != type).toList(),
    );
    await saveSettings();
    notifyListeners();
  }
}
