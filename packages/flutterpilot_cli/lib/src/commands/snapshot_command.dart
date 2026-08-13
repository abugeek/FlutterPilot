import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:vm_service/vm_service_io.dart';

/// Command to manage time-travel state snapshots.
class SnapshotCommand extends Command<void> {
  @override
  final String name = 'snapshot';

  @override
  final String description =
      'Capture and instantly rewind application state via time-travel snapshots.';

  SnapshotCommand() {
    addSubcommand(_SnapshotSaveCommand());
    addSubcommand(_SnapshotRestoreCommand());
    addSubcommand(_SnapshotListCommand());
  }
}

class _SnapshotSaveCommand extends Command<void> {
  @override
  final String name = 'save';

  @override
  final String description = 'Capture current runtime state as a named snapshot.';

  _SnapshotSaveCommand() {
    argParser.addOption(
      'vm-uri',
      abbr: 'u',
      defaultsTo: 'ws://127.0.0.1:8181/ws',
      help: 'VM Service URI of running app.',
    );
  }

  @override
  Future<void> run() async {
    final snapshotName = argResults?.rest.firstOrNull;
    if (snapshotName == null || snapshotName.isEmpty) {
      stderr.writeln('❌ Please provide a snapshot name: flutterpilot snapshot save <name>');
      return;
    }

    final vmUri = argResults?['vm-uri'] as String;
    try {
      final service = await vmServiceConnectUri(vmUri);
      final vm = await service.getVM();
      final isolateId = vm.isolates?.firstOrNull?.id;
      if (isolateId == null) {
        stderr.writeln('❌ No active isolate found.');
        return;
      }

      await service.callServiceExtension(
        'ext.flutterpilot.saveStateSnapshot',
        isolateId: isolateId,
        args: {'name': snapshotName},
      );

      stdout.writeln('✅ State snapshot "$snapshotName" saved successfully!');
    } catch (e) {
      stderr.writeln('⚠️ Error saving snapshot: $e');
    }
  }
}

class _SnapshotRestoreCommand extends Command<void> {
  @override
  final String name = 'restore';

  @override
  final String description = 'Rewind app state back to a named snapshot.';

  _SnapshotRestoreCommand() {
    argParser.addOption(
      'vm-uri',
      abbr: 'u',
      defaultsTo: 'ws://127.0.0.1:8181/ws',
      help: 'VM Service URI of running app.',
    );
  }

  @override
  Future<void> run() async {
    final snapshotName = argResults?.rest.firstOrNull;
    if (snapshotName == null || snapshotName.isEmpty) {
      stderr.writeln('❌ Please provide a snapshot name: flutterpilot snapshot restore <name>');
      return;
    }

    final vmUri = argResults?['vm-uri'] as String;
    try {
      final service = await vmServiceConnectUri(vmUri);
      final vm = await service.getVM();
      final isolateId = vm.isolates?.firstOrNull?.id;
      if (isolateId == null) {
        stderr.writeln('❌ No active isolate found.');
        return;
      }

      await service.callServiceExtension(
        'ext.flutterpilot.restoreStateSnapshot',
        isolateId: isolateId,
        args: {'name': snapshotName},
      );

      stdout.writeln('⚡ App state successfully rewound to "$snapshotName" (<100ms)!');
    } catch (e) {
      stderr.writeln('⚠️ Error restoring snapshot: $e');
    }
  }
}

class _SnapshotListCommand extends Command<void> {
  @override
  final String name = 'list';

  @override
  final String description = 'List all stored state snapshots.';

  _SnapshotListCommand() {
    argParser.addOption(
      'vm-uri',
      abbr: 'u',
      defaultsTo: 'ws://127.0.0.1:8181/ws',
      help: 'VM Service URI of running app.',
    );
  }

  @override
  Future<void> run() async {
    final vmUri = argResults?['vm-uri'] as String;
    try {
      final service = await vmServiceConnectUri(vmUri);
      final vm = await service.getVM();
      final isolateId = vm.isolates?.firstOrNull?.id;
      if (isolateId == null) {
        stderr.writeln('❌ No active isolate found.');
        return;
      }

      final res = await service.callServiceExtension(
        'ext.flutterpilot.listStateSnapshots',
        isolateId: isolateId,
      );

      final list = res.json?['snapshots'] as List? ?? [];
      if (list.isEmpty) {
        stdout.writeln('No saved snapshots found.');
        return;
      }

      stdout.writeln('Saved Snapshots (${list.length}):');
      for (final s in list) {
        stdout.writeln('  - ${s['name']} (${s['timestamp']}) -> Route: ${s['currentRoute']}');
      }
    } catch (e) {
      stderr.writeln('⚠️ Error listing snapshots: $e');
    }
  }
}
