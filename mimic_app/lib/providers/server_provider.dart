import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/log_entry.dart';
import '../models/server_config.dart';
import 'logs_provider.dart';

/// Server Provider - Manages saved server configurations
class ServerProvider extends ChangeNotifier {
  List<ServerConfig> _servers = [];
  ServerConfig? _selectedServer;
  bool _isLoading = false;
  String? _loadError;
  final _logs = LogsProvider.instance;

  // Getters
  List<ServerConfig> get servers => _servers;
  ServerConfig? get selectedServer => _selectedServer;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  bool get hasServers => _servers.isNotEmpty;
  bool get hasSelectedServer => _selectedServer != null;

  /// Load servers from storage
  Future<void> loadServers() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final serversJson = prefs.getStringList('saved_servers') ?? [];

      debugPrint('Loading ${serversJson.length} saved servers');

      _servers = serversJson
          .map((json) {
            try {
              return ServerConfig.fromJson(jsonDecode(json));
            } catch (e) {
              debugPrint('Error parsing server: $e');
              return null;
            }
          })
          .whereType<ServerConfig>()
          .toList();

      // Sort by last used (most recent first)
      _servers.sort((a, b) {
        if (b.lastUsed == null && a.lastUsed == null) return 0;
        if (b.lastUsed == null) return 1;
        if (a.lastUsed == null) return -1;
        return b.lastUsed!.compareTo(a.lastUsed!);
      });

      debugPrint('Loaded ${_servers.length} servers successfully');
      _logs.info(
        LogCategory.system,
        'Servers loaded',
        'Loaded ${_servers.length} saved server profiles.',
      );

      // Restore selected server if any
      if (_servers.isNotEmpty) {
        final selectedId = prefs.getString('selected_server_id');
        if (selectedId != null) {
          _selectedServer = _servers.firstWhere(
            (s) => s.id == selectedId,
            orElse: () => _servers.first,
          );
        } else {
          _selectedServer = _servers.first;
        }
        debugPrint('Selected server: ${_selectedServer?.displayName}');
      }
    } catch (e) {
      debugPrint('Error loading servers: $e');
      _logs.error(
        LogCategory.system,
        'Load servers failed',
        e.toString(),
      );
      _loadError = e.toString();
      _servers = [];
      _selectedServer = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save servers to storage
  Future<void> saveServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serversJson = _servers
          .map((server) => jsonEncode(server.toJson()))
          .toList();

      await prefs.setStringList('saved_servers', serversJson);
      debugPrint('Saved ${_servers.length} servers');
    } catch (e) {
      debugPrint('Error saving servers: $e');
      rethrow;
    }
  }

  /// Add a new server
  Future<void> addServer(ServerConfig server) async {
    debugPrint('Adding server: ${server.displayName} (${server.url})');
    _logs.info(
      LogCategory.ui,
      'Server added',
      'Added server profile ${server.displayName}.',
    );
    _servers.add(server);
    await saveServers();
    notifyListeners();
    debugPrint('Server added, total: ${_servers.length}');
  }

  /// Update an existing server
  Future<void> updateServer(ServerConfig updatedServer) async {
    final index = _servers.indexWhere((s) => s.id == updatedServer.id);
    if (index != -1) {
      _servers[index] = updatedServer;
      await saveServers();
      notifyListeners();
    } else {
      debugPrint('Server not found for update: ${updatedServer.id}');
    }
  }

  /// Delete a server
  Future<void> deleteServer(String serverId) async {
    debugPrint('Deleting server: $serverId');
    _logs.info(
      LogCategory.ui,
      'Server deleted',
      'Deleted saved server profile $serverId.',
    );
    _servers.removeWhere((s) => s.id == serverId);

    if (_selectedServer?.id == serverId) {
      _selectedServer = _servers.isNotEmpty ? _servers.first : null;
    }

    await saveServers();
    notifyListeners();
    debugPrint('Server deleted, remaining: ${_servers.length}');
  }

  /// Select a server
  void selectServer(ServerConfig server) async {
    debugPrint('Selecting server: ${server.displayName}');
    _logs.info(
      LogCategory.ui,
      'Server selected',
      'Selected ${server.displayName} as the active server.',
    );
    _selectedServer = server;
    
    // Save selected server ID
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_server_id', server.id);
    } catch (e) {
      debugPrint('Error saving selected server: $e');
      _logs.warning(
        LogCategory.system,
        'Persist selected server failed',
        e.toString(),
      );
    }
    
    notifyListeners();
  }

  /// Update server's last used timestamp
  Future<void> markServerAsUsed(ServerConfig server) async {
    final index = _servers.indexWhere((s) => s.id == server.id);
    if (index != -1) {
      _servers[index] = server.copyWith(lastUsed: DateTime.now());
      await saveServers();
      notifyListeners();
    }
  }

  /// Import servers from JSON
  Future<void> importServers(String jsonString) async {
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final importedServers = jsonList
          .map((json) => ServerConfig.fromJson(json))
          .toList();

      _servers.addAll(importedServers);
      await saveServers();
      notifyListeners();
      debugPrint('Imported ${importedServers.length} servers');
    } catch (e) {
      debugPrint('Error importing servers: $e');
      _logs.error(
        LogCategory.ui,
        'Import servers failed',
        e.toString(),
      );
      rethrow;
    }
  }

  /// Export servers to JSON
  String exportServers() {
    final jsonList = _servers.map((s) => s.toJson()).toList();
    return jsonEncode(jsonList);
  }

  /// Clear all servers
  Future<void> clearAllServers() async {
    _servers = [];
    _selectedServer = null;
    await saveServers();
    notifyListeners();
  }

  /// Refresh - reload servers from storage
  Future<void> refresh() async {
    await loadServers();
  }
}
