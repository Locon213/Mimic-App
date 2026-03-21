import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yaml/yaml.dart';

import '../../providers/server_provider.dart';
import '../../providers/vpn_provider.dart';
import '../../utils/app_theme.dart';
import '../../models/server_config.dart';
import '../yaml_config_editor.dart';

/// Server Selector - Shows current server and allows selection
class ServerSelector extends StatelessWidget {
  const ServerSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ServerProvider, VpnProvider>(
      builder: (context, serverProvider, vpnProvider, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final selectedServer = serverProvider.selectedServer;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? AppColors.surfaceElevated
                  : AppColors.surfaceElevatedLight,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.dns_rounded,
                    size: 20,
                    color: isDark
                        ? AppColors.textDarkSecondary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Server',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textDarkPrimary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _showServerList(context),
                    child: const Text('View All'),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Selected Server Card
              if (selectedServer != null)
                _ServerCard(
                  server: selectedServer,
                  isDark: isDark,
                  isConnected: vpnProvider.isConnected,
                )
              else
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surfaceElevated
                        : AppColors.surfaceElevatedLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.dns_outlined,
                        color: isDark
                            ? AppColors.textDarkSecondary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'No server selected',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? AppColors.textDarkSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => _showAddServerDialog(context),
                        icon: const Icon(Icons.add_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showServerList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ServerListSheet(),
    );
  }

  void _showAddServerDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final urlController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          title: const Text('Add Server'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'Server Link',
                    hintText: 'mimic://uuid@server:port#US MIMIC',
                    prefixIcon: Icon(Icons.link),
                    helperText: 'Use #CC Name for auto-flag (e.g., #US, #RU)',
                  ),
                  maxLines: 3,
                  onChanged: (value) {
                    if (value.contains('#') && nameController.text.isEmpty) {
                      final parts = value.split('#');
                      if (parts.length > 1 && parts.last.isNotEmpty) {
                        nameController.text = parts.last;
                        setDialogState(() {});
                      }
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Server Name (optional)',
                    hintText: '#US MIMIC',
                    prefixIcon: Icon(Icons.label),
                    helperText: 'Use #CC prefix for country flag',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final url = urlController.text.trim();
                if (url.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a server URL'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }

                try {
                  final server = ServerConfig(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text.trim(),
                    url: url,
                  );

                  context.read<ServerProvider>().addServer(server);
                  context.read<ServerProvider>().selectServer(server);

                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Added: ${server.flag} ${server.displayName}'),
                      backgroundColor: AppColors.connected,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString()}'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  final ServerConfig server;
  final bool isDark;
  final bool isConnected;

  const _ServerCard({
    required this.server,
    required this.isDark,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isConnected
            ? AppColors.connectedGradient
            : AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isConnected ? AppColors.connected : AppColors.primary)
                .withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Flag
          Text(
            server.flag,
            style: const TextStyle(fontSize: 40),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: Colors.white.withOpacity(0.8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      server.countryCode,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    if (isConnected) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerListSheet extends StatelessWidget {
  const _ServerListSheet();

  void _showAddServerDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final urlController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          title: const Text('Add Server'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'Server Link',
                    hintText: 'mimic://uuid@server:port#US MIMIC',
                    prefixIcon: Icon(Icons.link),
                    helperText: 'Use #CC Name for auto-flag (e.g., #US, #RU)',
                  ),
                  maxLines: 3,
                  onChanged: (value) {
                    if (value.contains('#') && nameController.text.isEmpty) {
                      final parts = value.split('#');
                      if (parts.length > 1 && parts.last.isNotEmpty) {
                        nameController.text = parts.last;
                        setDialogState(() {});
                      }
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Server Name (optional)',
                    hintText: '#US MIMIC',
                    prefixIcon: Icon(Icons.label),
                    helperText: 'Use #CC prefix for country flag',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final url = urlController.text.trim();
                if (url.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a server URL'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }

                try {
                  final server = ServerConfig(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text.trim(),
                    url: url,
                  );

                  context.read<ServerProvider>().addServer(server);
                  context.read<ServerProvider>().selectServer(server);

                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Added: ${server.flag} ${server.displayName}'),
                      backgroundColor: AppColors.connected,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString()}'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerProvider>(
      builder: (context, serverProvider, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceElevated : AppColors.surfaceElevatedLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Text(
                      'Saved Servers',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _showAddServerDialog(context),
                      icon: const Icon(Icons.add_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Server List
              if (serverProvider.isLoading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (serverProvider.servers.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.folder_open_outlined,
                        size: 64,
                        color: isDark
                            ? AppColors.textDarkSecondary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No servers saved',
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark
                              ? AppColors.textDarkSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add a server to get started',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? AppColors.textDarkSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: serverProvider.servers.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: isDark
                        ? AppColors.surfaceElevated
                        : AppColors.surfaceElevatedLight,
                  ),
                  itemBuilder: (context, index) {
                    final server = serverProvider.servers[index];
                    final isSelected =
                        serverProvider.selectedServer?.id == server.id;

                    return ListTile(
                      leading: Text(
                        server.flag,
                        style: const TextStyle(fontSize: 32),
                      ),
                      title: Text(
                        server.displayName,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isDark
                              ? AppColors.textDarkPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        server.countryCode,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.textDarkSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.connected.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Selected',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.connected,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          IconButton(
                            onPressed: () => _editServerConfig(context, server),
                            icon: const Icon(Icons.edit_outlined),
                            color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                            tooltip: 'Edit config',
                          ),
                          IconButton(
                            onPressed: () => _confirmDelete(context, server),
                            icon: const Icon(Icons.delete_outline_rounded),
                            color: AppColors.error,
                          ),
                        ],
                      ),
                      onTap: () {
                        serverProvider.selectServer(server);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),

              // Bottom padding
              SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, ServerConfig server) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Server'),
        content: Text('Are you sure you want to delete "${server.displayName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<ServerProvider>().deleteServer(server.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _editServerConfig(BuildContext context, ServerConfig server) {
    Navigator.pop(context); // Close the bottom sheet first

    final yamlContent = _serverToYaml(server);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => YamlConfigEditor(
          title: 'Edit: ${server.displayName}',
          initialContent: yamlContent,
          onSave: (content) {
            final updated = _yamlToServer(content, server);
            if (updated != null) {
              context.read<ServerProvider>().updateServer(updated);
            }
          },
        ),
      ),
    );
  }

  String _serverToYaml(ServerConfig server) {
    final buffer = StringBuffer();
    buffer.writeln('url: ${server.url}');
    buffer.writeln('name: ${server.displayName}');
    if (server.countryCode.isNotEmpty) {
      buffer.writeln('country_code: ${server.countryCode}');
    }
    if (server.domains.isNotEmpty) {
      buffer.writeln('domains: ${server.domains}');
    }
    return buffer.toString();
  }

  ServerConfig? _yamlToServer(String yaml, ServerConfig original) {
    try {
      final doc = loadYaml(yaml);
      if (doc is! YamlMap) return null;

      return ServerConfig(
        id: original.id,
        name: doc['name']?.toString() ?? original.name,
        url: doc['url']?.toString() ?? original.url,
        countryCode: doc['country_code']?.toString() ?? original.countryCode,
        domains: doc['domains']?.toString() ?? original.domains,
        createdAt: original.createdAt,
        lastUsed: original.lastUsed,
      );
    } catch (e) {
      return null;
    }
  }
}
