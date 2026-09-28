import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// `flutterpilot mcp ...`: connect AI clients to the FlutterPilot server.
class McpCommand extends Command<void> {
  @override
  final String name = 'mcp';

  @override
  final String description =
      'Connects AI clients (Claude Code, Cursor, VS Code) to the FlutterPilot MCP server.';

  McpCommand() {
    addSubcommand(McpInstallCommand());
  }
}

/// An MCP client whose project-scoped config `mcp install` writes.
enum McpClient {
  claude('Claude Code', '.mcp.json', 'mcpServers'),
  cursor('Cursor', '.cursor/mcp.json', 'mcpServers'),
  vscode('VS Code', '.vscode/mcp.json', 'servers');

  const McpClient(this.label, this.configPath, this.serversKey);
  final String label;
  final String configPath;

  /// VS Code calls the map `servers`; the others `mcpServers`.
  final String serversKey;

  /// Whether [project] already uses this client.
  bool detectedIn(String project) => switch (this) {
    claude => [
      '.mcp.json',
      '.claude',
      'CLAUDE.md',
    ].any((f) => FileSystemEntity.typeSync(p.join(project, f)) != .notFound),
    cursor => Directory(p.join(project, '.cursor')).existsSync(),
    vscode => Directory(p.join(project, '.vscode')).existsSync(),
  };
}

/// The command line that starts the server.
typedef ServerLaunch = ({String command, List<String> args});

/// `flutterpilot mcp install`: writes the project's MCP config for each
/// client, pointing at a compiled FlutterPilot server.
class McpInstallCommand extends Command<void> {
  @override
  final String name = 'install';

  @override
  final String description =
      "Adds the FlutterPilot server to the project's MCP config for Claude "
      'Code (.mcp.json), Cursor (.cursor/mcp.json) and VS Code '
      '(.vscode/mcp.json). Other servers in those files are kept.';

  McpInstallCommand() {
    argParser
      ..addOption(
        'project-root',
        abbr: 'p',
        help: 'Path to the Flutter project root (where pubspec.yaml lives).',
        defaultsTo: '.',
      )
      ..addMultiOption(
        'client',
        abbr: 'c',
        allowed: McpClient.values.map((c) => c.name),
        help:
            'Clients to configure. Default: the ones the project already '
            'uses (.mcp.json/.claude, .cursor, .vscode), else claude.',
      )
      ..addOption(
        'local',
        help:
            'Path to the FlutterPilot checkout whose server to use. Default: '
            'the one this CLI comes from.',
      )
      ..addFlag(
        'compile',
        defaultsTo: true,
        help:
            'Compile the server to an executable (fast start; clients need '
            'no dart on PATH). --no-compile runs it with "dart run".',
      )
      ..addFlag(
        'allow-destructive',
        negatable: false,
        help: 'Let the server write app state and storage.',
      );
  }

  @override
  Future<void> run() async {
    final project = p.normalize(
      p.absolute(argResults!['project-root'] as String),
    );
    if (!File(p.join(project, 'pubspec.yaml')).existsSync()) {
      throw UsageException(
        'No pubspec.yaml found in $project. Run this in your Flutter app.',
        usage,
      );
    }
    final serverDir = await _serverPackage(argResults!['local'] as String?);
    final chosen = argResults!['client'] as List<String>;
    final clients = chosen.isNotEmpty
        ? [for (final c in chosen) McpClient.values.byName(c)]
        : detectClients(project);

    final ServerLaunch launch;
    try {
      launch = argResults!['compile'] as bool
          ? await _compile(serverDir)
          : (
              command: Platform.resolvedExecutable,
              args: [
                'run',
                p.join(serverDir, 'bin', 'flutterpilot_server.dart'),
              ],
            );
    } on ProcessException catch (e) {
      stderr.writeln('❌ ${e.message}\nNothing was written.');
      exitCode = 1;
      return;
    }
    final extra = [
      if (argResults!['allow-destructive'] as bool) '--allow-destructive',
    ];

    var failed = false;
    for (final client in clients) {
      final result = writeConfig(project, client, launch, extraArgs: extra);
      failed |= result.startsWith('❌');
      stdout.writeln(result);
    }
    // Claude Code starts servers in the project folder, where the server
    // looks first: no -p, so one entry serves every project.
    final args = [...launch.args, ...extra];
    stdout.writeln(
      '\nFor Claude Code in every project instead (user scope):\n'
      '  claude mcp add --scope user flutterpilot -- '
      '${[launch.command, ...args].map(_shellQuote).join(' ')}\n'
      '\nNext: flutterpilot dev (runs the app so the server finds it).',
    );
    if (clients.contains(McpClient.claude)) {
      stdout.writeln(
        'Claude Code asks you to approve project servers from .mcp.json on '
        'first use.',
      );
    }
    if (failed) exitCode = 1;
  }

  /// Whether any client's config in [project] has a flutterpilot server.
  static bool isConfigured(String project) => McpClient.values.any((c) {
    final f = File(p.join(project, c.configPath));
    try {
      return f.existsSync() && f.readAsStringSync().contains('"flutterpilot"');
    } catch (_) {
      return false;
    }
  });

  /// Clients the project already uses, or Claude Code if none.
  static List<McpClient> detectClients(String project) {
    final found = [
      for (final c in McpClient.values)
        if (c.detectedIn(project)) c,
    ];
    return found.isEmpty ? [McpClient.claude] : found;
  }

  /// The server entry for [client]: VS Code gets `${workspaceFolder}` and
  /// `type`, the others the absolute project path.
  static Map<String, Object> serverEntry(
    McpClient client,
    String project,
    ServerLaunch launch, {
    List<String> extraArgs = const [],
  }) => {
    if (client == McpClient.vscode) 'type': 'stdio',
    'command': launch.command,
    'args': [
      ...launch.args,
      ...extraArgs,
      '-p',
      client == McpClient.vscode ? r'${workspaceFolder}' : project,
    ],
  };

  /// Adds or replaces the `flutterpilot` server in [client]'s config under
  /// [project], keeping everything else. Returns a line for the user.
  static String writeConfig(
    String project,
    McpClient client,
    ServerLaunch launch, {
    List<String> extraArgs = const [],
  }) {
    final file = File(p.join(project, client.configPath));
    final entry = serverEntry(client, project, launch, extraArgs: extraArgs);
    Map<String, dynamic> config = {};
    if (file.existsSync()) {
      final text = file.readAsStringSync();
      try {
        final decoded = text.trim().isEmpty
            ? <String, dynamic>{}
            : jsonDecode(text);
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        config = decoded;
      } on FormatException {
        // JSONC (comments, trailing commas) is valid for VS Code; rewriting
        // it would drop the user's comments.
        return '❌ ${client.label}: ${client.configPath} is not plain JSON '
            '(comments?), left unchanged. Add this under '
            '"${client.serversKey}" yourself:\n'
            '${const JsonEncoder.withIndent('  ').convert({'flutterpilot': entry})}';
      }
    }
    final servers = config[client.serversKey];
    if (servers != null && servers is! Map) {
      return '❌ ${client.label}: "${client.serversKey}" in '
          '${client.configPath} is not an object, left unchanged.';
    }
    final map = Map<String, dynamic>.from((servers as Map?) ?? {});
    final before = map['flutterpilot'];
    if (jsonEncode(before) == jsonEncode(entry)) {
      return '✅ ${client.label}: ${client.configPath} already up to date.';
    }
    map['flutterpilot'] = entry;
    config[client.serversKey] = map;
    file
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(config)}\n',
      );
    return '✅ ${client.label}: ${before == null ? 'added' : 'updated'} '
        'flutterpilot in ${client.configPath}.';
  }

  /// The flutterpilot_server package: from --local, or next to this CLI's
  /// own package (a checkout, or the clone `pub global activate` made).
  static Future<String> _serverPackage(String? local) async {
    String dir;
    if (local != null) {
      dir = p.join(p.absolute(local), 'packages', 'flutterpilot_server');
    } else {
      final lib = await Isolate.resolvePackageUri(
        Uri.parse('package:flutterpilot_cli/flutterpilot_cli.dart'),
      );
      if (lib == null) {
        throw UsageException(
          "Can't tell where this CLI is installed; pass --local <FlutterPilot checkout>.",
          '',
        );
      }
      dir = p.normalize(
        p.join(p.dirname(lib.toFilePath()), '..', '..', 'flutterpilot_server'),
      );
    }
    if (!File(p.join(dir, 'bin', 'flutterpilot_server.dart')).existsSync()) {
      throw UsageException(
        'No FlutterPilot server at $dir; pass --local <FlutterPilot checkout>.',
        '',
      );
    }
    return dir;
  }

  /// Compiles the server to `build/flutterpilot_server` — again on every
  /// install, so an update never leaves a stale executable.
  static Future<ServerLaunch> _compile(String serverDir) async {
    final dart = Platform.resolvedExecutable;
    Future<void> sh(List<String> args) async {
      final r = await Process.run(dart, args, workingDirectory: serverDir);
      if (r.exitCode != 0) {
        throw ProcessException(
          dart,
          args,
          'dart ${args.join(' ')} failed in $serverDir:\n${r.stdout}${r.stderr}',
          r.exitCode,
        );
      }
    }

    if (!File(
      p.join(serverDir, '.dart_tool', 'package_config.json'),
    ).existsSync()) {
      stdout.writeln('Fetching server dependencies…');
      await sh(['pub', 'get']);
    }
    final exe = p.join(
      serverDir,
      'build',
      Platform.isWindows ? 'flutterpilot_server.exe' : 'flutterpilot_server',
    );
    Directory(p.dirname(exe)).createSync(recursive: true);
    stdout.writeln('Compiling the FlutterPilot server (about a minute)…');
    await sh([
      'compile',
      'exe',
      p.join('bin', 'flutterpilot_server.dart'),
      '-o',
      exe,
    ]);
    return (command: exe, args: const <String>[]);
  }

  static String _shellQuote(String s) => RegExp(r'^[\w@%+=:,./-]+$').hasMatch(s)
      ? s
      : "'${s.replaceAll("'", r"'\''")}'";
}
