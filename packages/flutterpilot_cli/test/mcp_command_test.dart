import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:flutterpilot_cli/flutterpilot_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory app;
  final repo = p.normalize(p.join(Directory.current.path, '..', '..'));
  final serverScript = p.join(
    repo,
    'packages',
    'flutterpilot_server',
    'bin',
    'flutterpilot_server.dart',
  );
  const launch = (command: '/bin/fp', args: <String>[]);

  setUp(() {
    app = Directory.systemTemp.createTempSync('fp_mcp_');
    File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync('name: app\n');
  });
  tearDown(() => app.deleteSync(recursive: true));

  Map<String, dynamic> read(String path) =>
      jsonDecode(File(p.join(app.path, path)).readAsStringSync())
          as Map<String, dynamic>;

  Future<void> install(List<String> args) =>
      (CommandRunner<void>('flutterpilot', '')..addCommand(McpCommand())).run([
        'mcp',
        'install',
        '-p',
        app.path,
        '--local',
        repo,
        '--no-compile',
        ...args,
      ]);

  test('writes each client its own config shape', () async {
    await install(['-c', 'claude', '-c', 'cursor', '-c', 'vscode']);
    final claude = read('.mcp.json')['mcpServers']['flutterpilot'];
    expect(claude['command'], Platform.resolvedExecutable);
    expect(claude['args'], ['run', serverScript, '-p', p.normalize(app.path)]);
    expect(read('.cursor/mcp.json')['mcpServers']['flutterpilot'], claude);
    final vscode = read('.vscode/mcp.json')['servers']['flutterpilot'];
    expect(vscode['type'], 'stdio');
    expect(vscode['args'], ['run', serverScript, '-p', r'${workspaceFolder}']);
  });

  test('defaults to the clients the project uses, else Claude Code', () {
    expect(McpInstallCommand.detectClients(app.path), [McpClient.claude]);
    Directory(p.join(app.path, '.vscode')).createSync();
    Directory(p.join(app.path, '.cursor')).createSync();
    expect(McpInstallCommand.detectClients(app.path), [
      McpClient.cursor,
      McpClient.vscode,
    ]);
  });

  test('keeps other servers and settings; reinstall is a no-op', () {
    File(p.join(app.path, '.mcp.json')).writeAsStringSync(
      jsonEncode({
        'mcpServers': {
          'other': {'command': 'x'},
        },
        'extra': 1,
      }),
    );
    expect(
      McpInstallCommand.writeConfig(app.path, McpClient.claude, launch),
      contains('added'),
    );
    final config = read('.mcp.json');
    expect(config['extra'], 1);
    expect(config['mcpServers'].keys, ['other', 'flutterpilot']);
    expect(
      McpInstallCommand.writeConfig(app.path, McpClient.claude, launch),
      contains('already up to date'),
    );
    expect(
      McpInstallCommand.writeConfig(
        app.path,
        McpClient.claude,
        launch,
        extraArgs: ['--allow-destructive'],
      ),
      contains('updated'),
    );
    expect(read('.mcp.json')['mcpServers']['flutterpilot']['args'], [
      '--allow-destructive',
      '-p',
      app.path,
    ]);
  });

  test('leaves a JSONC file alone and says what to add', () {
    final file = File(p.join(app.path, '.vscode', 'mcp.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{\n  // mine\n  "servers": {}\n}\n');
    final result = McpInstallCommand.writeConfig(
      app.path,
      McpClient.vscode,
      launch,
    );
    expect(result, startsWith('❌'));
    expect(result, contains('"flutterpilot"'));
    expect(file.readAsStringSync(), contains('// mine'));
  });

  test('isConfigured sees any client config with flutterpilot', () {
    expect(McpInstallCommand.isConfigured(app.path), isFalse);
    McpInstallCommand.writeConfig(app.path, McpClient.cursor, launch);
    expect(McpInstallCommand.isConfigured(app.path), isTrue);
  });

  test('refuses a folder without pubspec.yaml', () async {
    File(p.join(app.path, 'pubspec.yaml')).deleteSync();
    expect(install([]), throwsA(isA<UsageException>()));
  });
}
