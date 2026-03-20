import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:convert';
import '../providers/settings_provider.dart';
import '../models/routing_rule.dart';
import '../utils/app_theme.dart';
import '../services/app_list_service.dart';

/// App Selection Screen - Select installed apps for routing rules
class AppSelectionScreen extends StatefulWidget {
  final RuleType ruleType;

  const AppSelectionScreen({super.key, required this.ruleType});

  @override
  State<AppSelectionScreen> createState() => _AppSelectionScreenState();
}

class _AppSelectionScreenState extends State<AppSelectionScreen> {
  List<AppInfo> _apps = [];
  List<AppInfo> _filteredApps = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    setState(() => _isLoading = true);

    try {
      if (Platform.isAndroid) {
        final apps = await _getInstalledApps();
        setState(() {
          _apps = apps;
          _filteredApps = apps;
          _isLoading = false;
        });
      } else {
        // For non-Android platforms, show a message
        setState(() {
          _apps = [];
          _filteredApps = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load apps: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<List<AppInfo>> _getInstalledApps() async {
    try {
      final appsData = await AppListService.getInstalledApps();
      final List<AppInfo> apps = [];
      
      for (final appData in appsData) {
        final packageName = appData['packageName'] ?? '';
        final appName = appData['appName'] ?? packageName;
        
        // Try to get the app icon
        String? iconBase64;
        try {
          iconBase64 = await AppListService.getAppIcon(packageName);
        } catch (e) {
          // Icon not available, will use default
        }
        
        apps.add(AppInfo(
          packageName: packageName,
          appName: appName,
          iconBase64: iconBase64,
        ));
      }
      
      // Sort apps alphabetically by name
      apps.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
      
      return apps;
    } catch (e) {
      print('Error loading apps: $e');
      return [];
    }
  }

  void _filterApps(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredApps = _apps;
      } else {
        _filteredApps = _apps
            .where((app) =>
                app.appName.toLowerCase().contains(query.toLowerCase()) ||
                app.packageName.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _selectApp(AppInfo app) {
    final settingsProvider = context.read<SettingsProvider>();
    settingsProvider.addDomainRule(
      app.packageName,
      app.appName,
      widget.ruleType,
    );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${app.appName} added to ${widget.ruleType.name} rules'),
        backgroundColor: AppColors.connected,
      ),
    );
  }

  Color _getTypeColor() {
    switch (widget.ruleType) {
      case RuleType.direct:
        return AppColors.connected;
      case RuleType.block:
        return AppColors.error;
      case RuleType.proxy:
        return AppColors.accent;
    }
  }

  String _getTypeName() {
    switch (widget.ruleType) {
      case RuleType.direct:
        return 'Direct';
      case RuleType.block:
        return 'Block';
      case RuleType.proxy:
        return 'Proxy';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final typeColor = _getTypeColor();

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Select App for ${_getTypeName()}',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _filterApps,
              decoration: InputDecoration(
                hintText: 'Search apps...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          _filterApps('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // Info text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Select an app to add to ${_getTypeName()} rules. The app will be routed according to this rule.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // App list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : !Platform.isAndroid
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.phone_android_rounded,
                              size: 64,
                              color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'App selection is only available on Android',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _filteredApps.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 64,
                                  color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isEmpty ? 'No apps found' : 'No apps match your search',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filteredApps.length,
                            itemBuilder: (context, index) {
                              final app = _filteredApps[index];
                              return _AppTile(
                                app: app,
                                isDark: isDark,
                                color: typeColor,
                                onTap: () => _selectApp(app),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

/// App Info model
class AppInfo {
  final String packageName;
  final String appName;
  final String? iconBase64;

  AppInfo({
    required this.packageName,
    required this.appName,
    this.iconBase64,
  });
}

/// App Tile Widget
class _AppTile extends StatelessWidget {
  final AppInfo app;
  final bool isDark;
  final Color color;
  final VoidCallback onTap;

  const _AppTile({
    required this.app,
    required this.isDark,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _buildAppIcon(),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.appName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textDarkPrimary : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        app.packageName,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.add_circle_outline_rounded,
                  color: color,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppIcon() {
    if (app.iconBase64 != null && app.iconBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(app.iconBase64!);
        return Image.memory(
          bytes,
          width: 28,
          height: 28,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.android_rounded,
              color: color,
              size: 28,
            );
          },
        );
      } catch (e) {
        return Icon(
          Icons.android_rounded,
          color: color,
          size: 28,
        );
      }
    }
    return Icon(
      Icons.android_rounded,
      color: color,
      size: 28,
    );
  }
}
