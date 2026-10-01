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

  test('without a server beside the CLI, builds one from a package that '
      'depends on flutterpilot_server', () async {
    final home = Directory.systemTemp.createTempSync('fp_home_');
    addTearDown(() => home.deleteSync(recursive: true));
    final serverPath = p.join(repo, 'packages', 'flutterpilot_server');
    final r = await Process.run(
      Platform.resolvedExecutable,
      [
        'run',
        'bin/flutterpilot.dart',
        'mcp',
        'install',
        '-p',
        app.path,
        '--server-path',
        serverPath,
        '--no-compile',
        '-c',
        'claude',
      ],
      environment: {'FLUTTERPILOT_HOME': home.path},
    );
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final host = p.join(home.path, 'server');
    expect(
      File(p.join(host, 'pubspec.yaml')).readAsStringSync(),
      contains(serverPath),
    );
    expect(
      File(p.join(host, 'bin', 'flutterpilot_server.dart')).readAsStringSync(),
      contains('runFlutterPilotServer(args)'),
    );
    // Resolved, so `dart run` works.
    expect(
      File(p.join(host, '.dart_tool', 'package_config.json')).existsSync(),
      isTrue,
    );
    expect(read('.mcp.json')['mcpServers']['flutterpilot']['args'], [
      'run',
      p.join(host, 'bin', 'flutterpilot_server.dart'),
      '-p',
      p.normalize(app.path),
    ]);
  });

  test('writes the documented shape for every other client', () async {
    await install(['-c', 'all', '--no-dart']);
    final entry = {
      'command': Platform.resolvedExecutable,
      'args': ['run', serverScript, '-p', p.normalize(app.path)],
    };
    for (final (path, key) in [
      ('.gemini/settings.json', 'mcpServers'),
      ('.agents/mcp_config.json', 'mcpServers'),
      ('.zed/settings.json', 'context_servers'),
      ('.junie/mcp/mcp.json', 'mcpServers'),
      ('.kiro/settings/mcp.json', 'mcpServers'),
      ('.roo/mcp.json', 'mcpServers'),
    ]) {
      expect(read(path)[key]['flutterpilot'], entry, reason: path);
    }
    // opencode: one command list, and a type.
    expect(read('opencode.json')['mcp']['flutterpilot'], {
      'type': 'local',
      'command': [Platform.resolvedExecutable, ...entry['args']! as List],
      'enabled': true,
    });
    // Codex: a TOML table.
    expect(
      File(p.join(app.path, '.codex', 'config.toml')).readAsStringSync(),
      '[mcp_servers.flutterpilot]\n'
      'command = ${jsonEncode(Platform.resolvedExecutable)}\n'
      'args = ${jsonEncode(entry['args'])}\n',
    );
    for (final client in McpClient.values) {
      expect(
        McpInstallCommand.installedLaunch(app.path, client)?.command,
        Platform.resolvedExecutable,
        reason: client.name,
      );
    }
  });

  test('Codex: keeps the rest of config.toml; reinstall is a no-op', () {
    final file = File(p.join(app.path, '.codex', 'config.toml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '# mine\n'
        'model = "gpt-5"\n'
        '\n'
        '[mcp_servers.flutterpilot]\n'
        'command = "/old/server"\n'
        'args = []\n'
        '\n'
        '[mcp_servers.flutterpilot.env]\n'
        'A = "1"\n'
        '\n'
        '[mcp_servers.docs]\n'
        "command = 'npx'\n"
        'args = [\n'
        '  "-y",\n'
        '  "docs-mcp",\n'
        ']\n',
      );
    expect(
      McpInstallCommand.writeConfig(app.path, McpClient.codex, launch),
      contains('updated'),
    );
    expect(
      file.readAsStringSync(),
      '# mine\n'
      'model = "gpt-5"\n'
      '\n'
      '[mcp_servers.docs]\n'
      "command = 'npx'\n"
      'args = [\n'
      '  "-y",\n'
      '  "docs-mcp",\n'
      ']\n'
      '\n'
      '[mcp_servers.flutterpilot]\n'
      'command = "/bin/fp"\n'
      'args = ["-p",${jsonEncode(app.path)}]\n',
    );
    expect(
      McpInstallCommand.writeConfig(app.path, McpClient.codex, launch),
      contains('already up to date'),
    );
    // The Dart MCP server goes in next to it, once.
    expect(
      McpInstallCommand.writeDartConfig(app.path, McpClient.codex, '/sdk/dart'),
      contains('added the Dart MCP server'),
    );
    expect(file.readAsStringSync(), contains('[mcp_servers.dart]\n'));
    expect(
      McpInstallCommand.writeDartConfig(app.path, McpClient.codex, '/sdk/dart'),
      contains('already set up'),
    );
    expect(
      '[mcp_servers.dart]'.allMatches(file.readAsStringSync()),
      hasLength(1),
    );
  });

  test('opencode.jsonc is left alone, with the entry to add', () {
    final file = File(p.join(app.path, 'opencode.jsonc'))
      ..writeAsStringSync('{\n  // mine\n}\n');
    final result = McpInstallCommand.writeConfig(
      app.path,
      McpClient.opencode,
      launch,
    );
    expect(result, startsWith('❌'));
    expect(result, contains('"type": "local"'));
    expect(file.readAsStringSync(), contains('// mine'));
    expect(File(p.join(app.path, 'opencode.json')).existsSync(), isFalse);
  });

  test('detects the newer clients by their folders', () {
    for (final dir in ['.codex', '.gemini', '.zed', '.kiro']) {
      Directory(p.join(app.path, dir)).createSync();
    }
    expect(McpInstallCommand.detectClients(app.path), [
      McpClient.codex,
      McpClient.gemini,
      McpClient.zed,
      McpClient.kiro,
    ]);
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

  test('adds the Dart MCP server without the tools FlutterPilot has', () async {
    await install(['-c', 'claude', '-c', 'vscode']);
    final dart = read('.mcp.json')['mcpServers']['dart'];
    expect(dart['command'], Platform.resolvedExecutable);
    expect(dart['args'], [
      'mcp-server',
      '--disable',
      'flutter,dart_tooling_daemon',
    ]);
    expect(read('.vscode/mcp.json')['servers']['dart']['type'], 'stdio');
  });

  test('--no-dart adds only FlutterPilot', () async {
    await install(['-c', 'claude', '--no-dart']);
    expect(read('.mcp.json')['mcpServers'].keys, ['flutterpilot']);
  });

  test("keeps the user's own Dart MCP server and says what to disable", () {
    File(p.join(app.path, '.mcp.json')).writeAsStringSync(
      jsonEncode({
        'mcpServers': {
          'github': {
            'command': 'docker',
            'args': ['run', 'github-mcp-server'],
          },
          'dart-tools': {
            'command': 'dart',
            'args': ['mcp-server'],
          },
        },
      }),
    );
    final result = McpInstallCommand.writeDartConfig(
      app.path,
      McpClient.claude,
      '/sdk/dart',
    );
    expect(result, contains('kept your Dart MCP server "dart-tools"'));
    expect(result, contains('"--disable", "flutter,dart_tooling_daemon"'));
    expect(read('.mcp.json')['mcpServers'].keys, ['github', 'dart-tools']);
    // Ours from an earlier install is up to date.
    File(p.join(app.path, '.mcp.json')).deleteSync();
    McpInstallCommand.writeDartConfig(app.path, McpClient.claude, '/sdk/dart');
    expect(
      McpInstallCommand.writeDartConfig(
        app.path,
        McpClient.claude,
        '/sdk/dart',
      ),
      contains('already set up'),
    );
  });

  test('refuses a folder without pubspec.yaml', () async {
    File(p.join(app.path, 'pubspec.yaml')).deleteSync();
    expect(install([]), throwsA(isA<UsageException>()));
  });
}
