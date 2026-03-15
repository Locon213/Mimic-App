/// Server configuration model
class ServerConfig {
  final String id;
  final String name;
  final String url;
  final String domains;
  final String countryCode;
  final DateTime createdAt;
  final DateTime? lastUsed;

  ServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.domains = '',
    this.countryCode = 'US',
    DateTime? createdAt,
    this.lastUsed,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Get flag emoji from country code
  String get flag {
    if (countryCode.isEmpty) return '🌐';
    final code = countryCode.toUpperCase();
    if (code.length != 2) return '🌐';

    // Convert country code to flag emoji
    final firstChar = code.codeUnitAt(0) + 127397;
    final secondChar = code.codeUnitAt(1) + 127397;
    return String.fromCharCode(firstChar) + String.fromCharCode(secondChar);
  }

  /// Extract server name from URL if not provided
  String get displayName => name.isNotEmpty ? name : _extractServerName(url);

  static String _extractServerName(String url) {
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

  ServerConfig copyWith({
    String? id,
    String? name,
    String? url,
    String? domains,
    String? countryCode,
    DateTime? createdAt,
    DateTime? lastUsed,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      domains: domains ?? this.domains,
      countryCode: countryCode ?? this.countryCode,
      createdAt: createdAt ?? this.createdAt,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'domains': domains,
      'country_code': countryCode,
      'created_at': createdAt.toIso8601String(),
      'last_used': lastUsed?.toIso8601String(),
    };
  }

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      domains: json['domains'] ?? '',
      countryCode: json['country_code'] ?? 'US',
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      lastUsed: json['last_used'] != null 
          ? DateTime.parse(json['last_used']) 
          : null,
    );
  }
}
