import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

/// Demonstrates the FlutterPilot Hive inspector for local storage introspection.
///
/// Provides a simple key-value editor backed by a Hive box.
/// The [HivePilotInspector] (registered in main.dart) lets an AI agent
/// call `ext.flutterpilot.getHiveContents` to read all stored data.
class StorageScreen extends StatefulWidget {
  final Box settingsBox;
  const StorageScreen({super.key, required this.settingsBox});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  final _keyController = TextEditingController();
  final _valueController = TextEditingController();

  Box get _box => widget.settingsBox;

  void _save() {
    final key = _keyController.text.trim();
    final value = _valueController.text.trim();
    if (key.isEmpty) return;

    _box.put(key, value);
    _keyController.clear();
    _valueController.clear();
    setState(() {});
  }

  void _delete(String key) {
    _box.delete(key);
    setState(() {});
  }

  void _seedDemoData() {
    _box.putAll({
      'theme': 'dark',
      'locale': 'en_US',
      'onboarding_complete': 'true',
      'last_login': DateTime.now().toIso8601String(),
    });
    setState(() {});
  }

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _box.toMap().entries.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Storage (Hive)')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.blue.shade50,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.smart_toy, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AI Agent: call ext.flutterpilot.getHiveContents '
                        'to inspect stored data.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('storage_key_field'),
                    controller: _keyController,
                    decoration: const InputDecoration(
                      labelText: 'Key',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('storage_value_field'),
                    controller: _valueController,
                    decoration: const InputDecoration(
                      labelText: 'Value',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('storage_save_button'),
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('seed_demo_data_button'),
                onPressed: _seedDemoData,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Seed Demo Data'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Stored Entries (${entries.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Text(
                        'No data yet. Add a key-value pair or seed demo data.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      key: const Key('storage_entries_list'),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          leading: const Icon(Icons.vpn_key),
                          title: Text('${entry.key}'),
                          subtitle: Text('${entry.value}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _delete('${entry.key}'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
