import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../models/routing_rule.dart';
import '../utils/app_theme.dart';

/// Rules Screen - Manage routing rules for a specific type
class RulesScreen extends StatefulWidget {
  final RuleType ruleType;

  const RulesScreen({super.key, required this.ruleType});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final typeColor = _getTypeColor();
    final typeName = _getTypeName();

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          typeName,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddRuleDialog(context),
          ),
        ],
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          final rules = settingsProvider.getRulesByType(widget.ruleType);

          if (rules.isEmpty) {
            return _buildEmptyState(context, isDark, typeColor);
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: rules.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final rule = rules[index];
              return _RuleTile(
                rule: rule,
                isDark: isDark,
                color: typeColor,
                onDelete: () => _confirmDelete(context, settingsProvider, rule.id),
              );
            },
          );
        },
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
        return 'Direct Rules';
      case RuleType.block:
        return 'Block Rules';
      case RuleType.proxy:
        return 'Proxy Rules';
    }
  }

  Widget _buildEmptyState(BuildContext context, bool isDark, Color color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.rule_rounded,
              size: 48,
              color: color,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Rules Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textDarkPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first rule to get started',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _showAddRuleDialog(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Rule'),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddRuleDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameController = TextEditingController();
    final valueController = TextEditingController();
    bool? isDomain = widget.ruleType == RuleType.direct ? null : true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          title: Text('Add ${_getTypeName().split(' ')[0]} Rule'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Rule type selector for Direct (Apps vs Domains)
                if (widget.ruleType == RuleType.direct) ...[
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceElevated : AppColors.surfaceElevatedLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setDialogState(() => isDomain = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isDomain == false ? _getTypeColor() : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  'Apps',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDomain == false
                                        ? Colors.white
                                        : (isDark ? AppColors.textDarkSecondary : AppColors.textSecondary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setDialogState(() => isDomain = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isDomain == true ? _getTypeColor() : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  'Domains',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDomain == true
                                        ? Colors.white
                                        : (isDark ? AppColors.textDarkSecondary : AppColors.textSecondary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: valueController,
                  decoration: InputDecoration(
                    labelText: isDomain == true || widget.ruleType != RuleType.direct
                        ? 'Domain'
                        : 'Package Name',
                    hintText: isDomain == true || widget.ruleType != RuleType.direct
                        ? 'example.com'
                        : 'com.example.app',
                    prefixIcon: const Icon(Icons.dns_rounded),
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'My Rule',
                    prefixIcon: Icon(Icons.label_rounded),
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
                final value = valueController.text.trim();
                if (value.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a value'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }

                context.read<SettingsProvider>().addDomainRule(
                      value,
                      nameController.text.trim(),
                      widget.ruleType,
                    );

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Rule added successfully'),
                    backgroundColor: AppColors.connected,
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, SettingsProvider provider, String ruleId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        title: const Text('Delete Rule?'),
        content: const Text('Are you sure you want to delete this rule?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.deleteRule(ruleId);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// Rule Tile Widget
class _RuleTile extends StatelessWidget {
  final RoutingRule rule;
  final bool isDark;
  final Color color;
  final VoidCallback onDelete;

  const _RuleTile({
    required this.rule,
    required this.isDark,
    required this.color,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(rule.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.delete_rounded,
          color: Colors.white,
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                rule.type == RuleType.direct
                    ? Icons.apps_rounded
                    : rule.type == RuleType.block
                        ? Icons.block_rounded
                        : Icons.security_rounded,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.name.isNotEmpty ? rule.name : rule.value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.textDarkPrimary : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rule.value,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.textDarkSecondary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              color: AppColors.error,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
