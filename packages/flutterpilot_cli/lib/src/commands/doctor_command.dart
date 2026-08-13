import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// Command to diagnose FlutterPilot setup and environment.
class DoctorCommand extends Command<void> {
  @override
  final String name = 'doctor';

  @override
  final String description =
      'Checks the local environment, connected devices, and AI IDE MCP configurations.';

  @override
  Future<void> run() async {
    stdout.writeln('🏥 Running FlutterPilot Doctor...\n');

    // 1. Check Flutter SDK
    try {
      final res = await Process.run('flutter', ['--version']);
      if (res.exitCode == 0) {
        final firstLine = (res.stdout as String).split('\n').first;
        stdout.writeln('✅ Flutter SDK: $firstLine');
      } else {
        stdout.writeln('❌ Flutter SDK: Not found or returned error.');
      }
    } catch (_) {
      stdout.writeln('❌ Flutter SDK: Not found in PATH.');
    }

    // 2. Check Dart SDK
    try {
      final res = await Process.run('dart', ['--version']);
      if (res.exitCode == 0) {
        final version = (res.stdout as String).trim().isEmpty ? (res.stderr as String).trim() : (res.stdout as String).trim();
        stdout.writeln('✅ Dart SDK: $version');
      }
    } catch (_) {
      stdout.writeln('❌ Dart SDK: Not found in PATH.');
    }

    // 3. Check Connected Devices
    try {
      final res = await Process.run('flutter', ['devices']);
      if (res.exitCode == 0) {
        stdout.writeln('\n📱 Connected Devices:');
        for (final line in (res.stdout as String).split('\n')) {
          if (line.trim().isNotEmpty && !line.startsWith('Searching') && !line.startsWith('No devices')) {
            stdout.writeln('   $line');
          }
        }
      }
    } catch (_) {}

    // 4. Check AI IDE Configs
    stdout.writeln('\n🤖 AI Assistant MCP Configurations:');
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

    // Claude Desktop
    final claudeConfig = File(p.join(home, 'Library', 'Application Support', 'Claude', 'claude_desktop_config.json'));
    if (claudeConfig.existsSync()) {
      stdout.writeln('✅ Claude Desktop config detected (${claudeConfig.path})');
    } else {
      stdout.writeln('ℹ️ Claude Desktop config not found at default location.');
    }

    // Cursor
    final cursorConfig = File(p.join('.', '.cursor', 'mcp.json'));
    if (cursorConfig.existsSync()) {
      stdout.writeln('✅ Local Cursor MCP config detected (${cursorConfig.path})');
    } else {
      stdout.writeln('ℹ️ Cursor MCP config not found in current directory (.cursor/mcp.json)');
    }

    stdout.writeln('\n🩺 Doctor check completed.\n');
  }
}
