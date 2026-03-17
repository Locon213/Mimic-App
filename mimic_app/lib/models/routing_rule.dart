/// Routing Rule Model
enum RuleType { direct, block, proxy }

class RoutingRule {
  final String id;
  final String name;
  final String value; // domain, package name, IP, etc.
  final RuleType type;
  final DateTime createdAt;

  RoutingRule({
    required this.id,
    required this.name,
    required this.value,
    required this.type,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  RoutingRule copyWith({
    String? id,
    String? name,
    String? value,
    RuleType? type,
    DateTime? createdAt,
  }) {
    return RoutingRule(
      id: id ?? this.id,
      name: name ?? this.name,
      value: value ?? this.value,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'value': value,
      'type': type.name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory RoutingRule.fromJson(Map<String, dynamic> json) {
    return RoutingRule(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] ?? '',
      value: json['value'] ?? '',
      type: RuleType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RuleType.proxy,
      ),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }
}

/// App Settings Model
class AppSettings {
  final bool autoConnect;
  final bool startOnBoot;
  final bool showNotification;
  final String selectedMode;
  final List<RoutingRule> rules;

  AppSettings({
    this.autoConnect = false,
    this.startOnBoot = false,
    this.showNotification = true,
    this.selectedMode = 'TUN',
    List<RoutingRule>? rules,
  }) : rules = rules ?? [];

  AppSettings copyWith({
    bool? autoConnect,
    bool? startOnBoot,
    bool? showNotification,
    String? selectedMode,
    List<RoutingRule>? rules,
  }) {
    return AppSettings(
      autoConnect: autoConnect ?? this.autoConnect,
      startOnBoot: startOnBoot ?? this.startOnBoot,
      showNotification: showNotification ?? this.showNotification,
      selectedMode: selectedMode ?? this.selectedMode,
      rules: rules ?? this.rules,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'auto_connect': autoConnect,
      'start_on_boot': startOnBoot,
      'show_notification': showNotification,
      'selected_mode': selectedMode,
      'rules': rules.map((r) => r.toJson()).toList(),
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      autoConnect: json['auto_connect'] ?? false,
      startOnBoot: json['start_on_boot'] ?? false,
      showNotification: json['show_notification'] ?? true,
      selectedMode: json['selected_mode'] ?? 'TUN',
      rules: (json['rules'] as List<dynamic>?)
              ?.map((r) => RoutingRule.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
