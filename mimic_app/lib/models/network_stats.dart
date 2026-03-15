/// Network statistics model
class NetworkStats {
  final int downloadSpeed; // bytes per second
  final int uploadSpeed; // bytes per second
  final int ping; // milliseconds
  final int totalDownload; // total bytes received
  final int totalUpload; // total bytes sent
  final DateTime lastUpdated;

  NetworkStats({
    this.downloadSpeed = 0,
    this.uploadSpeed = 0,
    this.ping = 0,
    this.totalDownload = 0,
    this.totalUpload = 0,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  /// Get download speed as human readable string
  String get downloadSpeedString => _formatBytes(downloadSpeed) + '/s';

  /// Get upload speed as human readable string
  String get uploadSpeedString => _formatBytes(uploadSpeed) + '/s';

  /// Get total download as human readable string
  String get totalDownloadString => _formatBytes(totalDownload);

  /// Get total upload as human readable string
  String get totalUploadString => _formatBytes(totalUpload);

  /// Format bytes to human readable string
  static String _formatBytes(int bytes) {
    if (bytes < 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    int exp = 0;
    double size = bytes.toDouble();
    
    while (size >= 1024 && exp < units.length - 1) {
      size /= 1024;
      exp++;
    }
    
    return '${size.toStringAsFixed(1)} ${units[exp]}';
  }

  NetworkStats copyWith({
    int? downloadSpeed,
    int? uploadSpeed,
    int? ping,
    int? totalDownload,
    int? totalUpload,
    DateTime? lastUpdated,
  }) {
    return NetworkStats(
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      uploadSpeed: uploadSpeed ?? this.uploadSpeed,
      ping: ping ?? this.ping,
      totalDownload: totalDownload ?? this.totalDownload,
      totalUpload: totalUpload ?? this.totalUpload,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

/// Connection status enum
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

extension ConnectionStatusExtension on ConnectionStatus {
  String get label {
    switch (this) {
      case ConnectionStatus.disconnected:
        return 'Disconnected';
      case ConnectionStatus.connecting:
        return 'Connecting...';
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.reconnecting:
        return 'Reconnecting...';
    }
  }

  bool get isConnected => this == ConnectionStatus.connected;
  bool get isConnecting => this == ConnectionStatus.connecting;
  bool get isDisconnected => this == ConnectionStatus.disconnected;
}
