import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_config.dart';

/// Server Provider - Manages saved server configurations
class ServerProvider extends ChangeNotifier {
  List<ServerConfig> _servers = [];
  ServerConfig? _selectedServer;
  bool _isLoading = false;

  // Getters
  List<ServerConfig> get servers => _servers;
  ServerConfig? get selectedServer => _selectedServer;
  bool get isLoading => _isLoading;
  bool get hasServers => _servers.isNotEmpty;

  /// Load servers from storage
  Future<void> loadServers() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final serversJson = prefs.getStringList('saved_servers') ?? [];
      
      _servers = serversJson
          .map((json) => ServerConfig.fromJson(jsonDecode(json)))
          .toList();
      
      // Sort by last used (most recent first)
      _servers.sort((a, b) {
        if (b.lastUsed == null) return -1;
        if (a.lastUsed == null) return 1;
        return b.lastUsed!.compareTo(a.lastUsed!);
      });
    } catch (e) {
      debugPrint('Error loading servers: $e');
      _servers = [];
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
    } catch (e) {
      debugPrint('Error saving servers: $e');
      rethrow;
    }
  }

  /// Add a new server
  Future<void> addServer(ServerConfig server) async {
    _servers.add(server);
    await saveServers();
    notifyListeners();
  }

  /// Update an existing server
  Future<void> updateServer(ServerConfig updatedServer) async {
    final index = _servers.indexWhere((s) => s.id == updatedServer.id);
    if (index != -1) {
      _servers[index] = updatedServer;
      await saveServers();
      notifyListeners();
    }
  }

  /// Delete a server
  Future<void> deleteServer(String serverId) async {
    _servers.removeWhere((s) => s.id == serverId);
    
    if (_selectedServer?.id == serverId) {
      _selectedServer = null;
    }
    
    await saveServers();
    notifyListeners();
  }

  /// Select a server
  void selectServer(ServerConfig server) {
    _selectedServer = server;
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
    } catch (e) {
      debugPrint('Error importing servers: $e');
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
}
