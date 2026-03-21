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
    this.countryCode = '',
    DateTime? createdAt,
    this.lastUsed,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Auto-detect country code from server name or URL
  /// Supports patterns: "#US MIMIC", "#RU Server", "US-Server", emoji flags
  static String detectCountryCode(String name, String url) {
    final text = '$name $url';

    // Pattern 1: #XX at start (e.g., "#US MIMIC", "#RU Server")
    final hashMatch = RegExp(r'#([A-Za-z]{2})\b').firstMatch(text);
    if (hashMatch != null) {
      return hashMatch.group(1)!.toUpperCase();
    }

    // Pattern 2: XX- or XX_ at start of name (e.g., "US-Server")
    final prefixMatch = RegExp(r'^([A-Za-z]{2})[-_]').firstMatch(name.trim());
    if (prefixMatch != null) {
      return prefixMatch.group(1)!.toUpperCase();
    }

    // Pattern 3: Emoji flag in name (🇺🇸, 🇷🇺 etc.)
    final emojiMatch = RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true).firstMatch(text);
    if (emojiMatch != null) {
      final emoji = emojiMatch.group(0)!;
      if (emoji.length >= 2) {
        final first = emoji.codeUnitAt(0) - 127397;
        final second = emoji.codeUnitAt(1) - 127397;
        if (first >= 65 && first <= 90 && second >= 65 && second <= 90) {
          return String.fromCharCode(first) + String.fromCharCode(second);
        }
      }
    }

    return '';
  }

  /// Get flag emoji from country code
  /// Any 2-letter ASCII code converts to a flag emoji via Unicode regional indicators
  String get flag {
    final code = resolvedCountryCode;
    if (code.length != 2) return '\u{1F310}'; // globe emoji

    final firstChar = code.codeUnitAt(0) + 127397;
    final secondChar = code.codeUnitAt(1) + 127397;
    return String.fromCharCode(firstChar) + String.fromCharCode(secondChar);
  }

  /// Get the resolved country code (auto-detected or manually set)
  String get resolvedCountryCode {
    if (countryCode.isNotEmpty && countryCode.length == 2) {
      return countryCode.toUpperCase();
    }
    return detectCountryCode(name, url);
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
      countryCode: json['country_code'] ?? '',
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      lastUsed: json['last_used'] != null 
          ? DateTime.parse(json['last_used']) 
          : null,
    );
  }
}
