import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../version.dart';

/// `flutterpilot mcp ...`: connect AI clients to the FlutterPilot server.
class McpCommand extends Command<void> {
  @override
  final String name = 'mcp';

  @override
  final String description =
      'Connects AI clients (Claude Code, Cursor, VS Code, Codex, Gemini CLI, '
      'Antigravity, Zed, opencode, Junie, Kiro, Roo Code) to the FlutterPilot '
      'MCP server.';

  McpCommand() {
    addSubcommand(McpInstallCommand());
  }
}

/// An MCP client whose project-scoped config `mcp install` writes. Each
/// row is that client's documented format (checked 2026-10-01); clients
/// with only a user-level config (Claude Desktop, Windsurf, Cline) get the
/// entry printed instead.
enum McpClient {
  claude('Claude Code', '.mcp.json', 'mcpServers', [
    '.mcp.json',
    '.claude',
    'CLAUDE.md',
  ]),
  cursor('Cursor', '.cursor/mcp.json', 'mcpServers', ['.cursor']),
  vscode('VS Code', '.vscode/mcp.json', 'servers', ['.vscode']),
  codex('Codex', '.codex/config.toml', 'mcp_servers', ['.codex']),
  gemini('Gemini CLI', '.gemini/settings.json', 'mcpServers', [
    '.gemini',
    'GEMINI.md',
  ]),
  antigravity('Antigravity', '.agents/mcp_config.json', 'mcpServers', [
    '.agents',
  ]),
  zed('Zed', '.zed/settings.json', 'context_servers', ['.zed']),
  opencode('opencode', 'opencode.json', 'mcp', [
    'opencode.json',
    'opencode.jsonc',
    '.opencode',
  ]),
  junie('JetBrains Junie', '.junie/mcp/mcp.json', 'mcpServers', ['.junie']),
  kiro('Kiro', '.kiro/settings/mcp.json', 'mcpServers', ['.kiro']),
  roo('Roo Code', '.roo/mcp.json', 'mcpServers', ['.roo']);

  const McpClient(this.label, this.configPath, this.serversKey, this.markers);
  final String label;
  final String configPath;

  /// The map of servers: VS Code calls it `servers`, Zed `context_servers`,
  /// opencode `mcp`, Codex the `[mcp_servers.<name>]` tables; the others
  /// `mcpServers`.
  final String serversKey;

  /// Files or folders that show a project uses this client.
  final List<String> markers;

  /// Codex keeps its config in TOML; the others in JSON.
  bool get isToml => this == codex;

  /// Whether [project] already uses this client.
  bool detectedIn(String project) => markers.any(
    (f) => FileSystemEntity.typeSync(p.join(project, f)) != .notFound,
  );
}

/// The command line that starts the server.
typedef ServerLaunch = ({String command, List<String> args});

/// `flutterpilot mcp install`: writes the project's MCP config for each
/// client, pointing at a compiled FlutterPilot server.
/// Those of [configPaths] (relative to [project]) that exist and that git
/// would offer to commit: untracked and not ignored. Empty outside a git
/// repository or without git.
List<String> untrackedConfigs(String project, List<String> configPaths) {
  if (configPaths.isEmpty) return const [];
  try {
    final result = Process.runSync('git', [
      'status',
      '--porcelain',
      '--',
      ...configPaths,
    ], workingDirectory: project);
    if (result.exitCode != 0) return const [];
    final untracked = {
      for (final line in LineSplitter.split(result.stdout as String))
        if (line.startsWith('?? ')) line.substring(3).trim(),
    };
    // git names a new folder (".cursor/"), not the file inside it.
    return [
      for (final path in configPaths)
        if (untracked.any((u) => u == path || path.startsWith(u))) path,
    ];
  } on ProcessException {
    return const [];
  }
}

class McpInstallCommand extends Command<void> {
  @override
  final String name = 'install';

  @override
  final String description =
      "Adds the FlutterPilot server to the project's MCP config for the "
      'clients it uses (Claude Code, Cursor, VS Code, Codex, Gemini CLI, '
      'Antigravity, Zed, opencode, Junie, Kiro, Roo Code; --client picks), '
      'with the official Dart MCP server for the code side. Other servers '
      'in those files are kept. Prints the entry for any other client.';

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
        allowed: [...McpClient.values.map((c) => c.name), 'all'],
        help:
            'Clients to configure ("all" for every one). Default: the ones '
            'the project already uses (its .cursor, .vscode, .codex, '
            '.gemini, ... folder or config), else claude.',
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
      ..addOption(
        'server-path',
        hide: true,
        help:
            'Build the server from this flutterpilot_server folder the way '
            'a pub.dev install does (tests).',
      )
      ..addFlag(
        'dart',
        defaultsTo: true,
        help:
            'Also add the official Dart MCP server ("dart mcp-server": '
            'analyzer, symbols, pub), without its running-app tools, which '
            'FlutterPilot has.',
      )
      ..addFlag(
        'allow-destructive',
        negatable: false,
        help: 'Let the server write app state and storage.',
      )
      ..addFlag(
        'static-tools',
        negatable: false,
        help:
            'Have the server list every tool from the start and never change '
            "the list: for a client that doesn't refresh it when the server "
            'says it changed.',
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
    final serverPath = argResults!['server-path'] as String?;
    final serverDir =
        (serverPath == null
            ? await _serverPackage(argResults!['local'] as String?)
            : null) ??
        _hostPackage(serverPath);
    final chosen = argResults!['client'] as List<String>;
    final clients = chosen.contains('all')
        ? McpClient.values
        : chosen.isNotEmpty
        ? [for (final c in chosen) McpClient.values.byName(c)]
        : detectClients(project);

    final ServerLaunch launch;
    try {
      await _resolve(serverDir);
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
      if (argResults!['static-tools'] as bool) '--static-tools',
    ];

    final dart = argResults!['dart'] as bool && await _hasDartMcp()
        ? Platform.resolvedExecutable
        : null;
    if (argResults!['dart'] as bool && dart == null) {
      stdout.writeln(
        'ℹ️ This Dart SDK has no "dart mcp-server": only FlutterPilot is added.',
      );
    }
    var failed = false;
    for (final client in clients) {
      final result = writeConfig(project, client, launch, extraArgs: extra);
      failed |= result.startsWith('❌');
      stdout.writeln(result);
      if (dart != null && !result.startsWith('❌')) {
        stdout.writeln(writeDartConfig(project, client, dart));
      }
    }
    final exposed = untrackedConfigs(project, [
      for (final client in clients) client.configPath,
    ]);
    if (exposed.isNotEmpty) {
      stdout.writeln(
        '⚠️ ${exposed.join(', ')}: holds paths on this machine and git does '
        'not ignore it. To keep it out of commits:',
      );
      for (final file in exposed) {
        stdout.writeln('  echo ${_shellQuote(file)} >> .git/info/exclude');
      }
    }
    // Claude Code starts servers in the project folder, where the server
    // looks first: no -p, so one entry serves every project.
    final args = [...launch.args, ...extra];
    final line = [launch.command, ...args].map(_shellQuote).join(' ');
    stdout.writeln(
      '\nFor Claude Code in every project instead (user scope):\n'
      '  claude mcp add --scope user flutterpilot -- $line\n'
      '${dart == null ? '' : '  claude mcp add --scope user dart -- ${_shellQuote(dart)} mcp-server --disable $dartMcpDisabled\n'}'
      '\nAny other client that starts a local (stdio) MCP server — Claude '
      'Desktop\n(claude_desktop_config.json), Windsurf, Cline, GitHub '
      'Copilot CLI, ... — takes\nthis entry in its MCP config:\n'
      '${const JsonEncoder.withIndent('  ').convert({
        'mcpServers': {'flutterpilot': serverEntry(McpClient.claude, project, launch, extraArgs: extra)},
      })}\n'
      '\nNext: run the app (flutter run, flutterpilot dev or your IDE); the '
      'server finds it.',
    );
    if (clients.contains(McpClient.claude)) {
      stdout.writeln(
        'Claude Code asks you to approve project servers from .mcp.json on '
        'first use.',
      );
    }
    if (clients.contains(McpClient.gemini)) {
      stdout.writeln(
        'Gemini CLI starts project servers only in a folder you trust '
        '(it asks on first run).',
      );
    }
    if (clients.contains(McpClient.codex)) {
      stdout.writeln(
        'Codex reads .codex/config.toml only in a project you have marked '
        'as trusted. For every project instead:\n'
        '  codex mcp add flutterpilot -- $line -p ${_shellQuote(project)}',
      );
    }
    if (failed) exitCode = 1;
  }

  /// Whether any client's config in [project] has a flutterpilot server.
  static bool isConfigured(String project) => McpClient.values.any((c) {
    final f = File(p.join(project, c.configPath));
    try {
      return f.existsSync() && f.readAsStringSync().contains('flutterpilot');
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
  }) => _entry(client, launch.command, [
    ...launch.args,
    ...extraArgs,
    '-p',
    client == McpClient.vscode ? r'${workspaceFolder}' : project,
  ]);

  /// [command] and [args] in the shape [client]'s config takes: opencode
  /// wants one `command` list and a `type`, VS Code a `type`.
  static Map<String, Object> _entry(
    McpClient client,
    String command,
    List<String> args,
  ) => switch (client) {
    McpClient.opencode => {
      'type': 'local',
      'command': [command, ...args],
      'enabled': true,
    },
    McpClient.vscode => {'type': 'stdio', 'command': command, 'args': args},
    _ => {'command': command, 'args': args},
  };

  /// The Dart MCP server's feature categories FlutterPilot covers: hot
  /// reload/restart, runtime errors, the widget inspector, Flutter Driver
  /// and app launching (`flutter`), and its DTD/VM service connection
  /// (`dart_tooling_daemon`). What stays is the code side: analyze_files,
  /// lsp, pub, pub_dev_search and reading dependencies.
  static const dartMcpDisabled = 'flutter,dart_tooling_daemon';

  /// The official Dart MCP server's entry: it takes the project from the
  /// client's workspace folders, so it has no path.
  static Map<String, Object> dartEntry(McpClient client, String dart) =>
      _entry(client, dart, ['mcp-server', '--disable', dartMcpDisabled]);

  /// Adds the Dart MCP server as `dart` to [client]'s config, unless one
  /// is there already (under any name): then says how to drop its tools
  /// FlutterPilot duplicates.
  static String writeDartConfig(
    String project,
    McpClient client,
    String dart,
  ) => _editServers(project, client, 'dart', dartEntry(client, dart), (
    servers,
  ) {
    final entry = dartEntry(client, dart);
    for (final MapEntry(:key, :value) in servers.entries) {
      if (!jsonEncode(value).contains('"mcp-server"')) continue;
      if (jsonEncode(value) == jsonEncode(entry)) {
        return '✅ ${client.label}: Dart MCP server already set up.';
      }
      return 'ℹ️ ${client.label}: kept your Dart MCP server "$key". Its hot '
          'reload, runtime errors, widget inspector and Flutter Driver tools '
          'duplicate FlutterPilot\'s: add "--disable", "$dartMcpDisabled" to '
          'its args to give the agent one of each.';
    }
    servers['dart'] = entry;
    return '✅ ${client.label}: added the Dart MCP server (dart) in '
        '${client.configPath}, without the tools FlutterPilot has.';
  });

  /// Whether this SDK has the Dart MCP server.
  static Future<bool> _hasDartMcp() async {
    try {
      final r = await Process.run(Platform.resolvedExecutable, [
        'mcp-server',
        '--version',
      ]).timeout(const Duration(seconds: 60));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Adds or replaces the `flutterpilot` server in [client]'s config under
  /// [project], keeping everything else. Returns a line for the user.
  static String writeConfig(
    String project,
    McpClient client,
    ServerLaunch launch, {
    List<String> extraArgs = const [],
  }) {
    final entry = serverEntry(client, project, launch, extraArgs: extraArgs);
    return _editServers(project, client, 'flutterpilot', entry, (servers) {
      final before = servers['flutterpilot'];
      if (jsonEncode(before) == jsonEncode(entry)) {
        return '✅ ${client.label}: ${client.configPath} already up to date.';
      }
      servers['flutterpilot'] = entry;
      return '✅ ${client.label}: ${before == null ? 'added' : 'updated'} '
          'flutterpilot in ${client.configPath}.';
    });
  }

  /// Reads [client]'s config, lets [change] edit its servers and returns
  /// its line; writes the file only if the servers changed. A file that
  /// isn't plain JSON is left alone, with [entry] to add as [name] by hand.
  static String _editServers(
    String project,
    McpClient client,
    String name,
    Map<String, Object> entry,
    String Function(Map<String, dynamic> servers) change,
  ) {
    if (client.isToml) return _editToml(project, client, name, entry, change);
    final file = File(p.join(project, client.configPath));
    final snippet = const JsonEncoder.withIndent('  ').convert({name: entry});
    // opencode reads opencode.jsonc too; a second file would shadow it.
    final jsonc = File('${file.path}c');
    if (client == McpClient.opencode &&
        !file.existsSync() &&
        jsonc.existsSync()) {
      return '❌ ${client.label}: this project uses opencode.jsonc '
          '(comments), left unchanged. Add this under '
          '"${client.serversKey}" yourself:\n$snippet';
    }
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
            '"${client.serversKey}" yourself:\n$snippet';
      }
    }
    final servers = config[client.serversKey];
    if (servers != null && servers is! Map) {
      return '❌ ${client.label}: "${client.serversKey}" in '
          '${client.configPath} is not an object, left unchanged.';
    }
    final map = Map<String, dynamic>.from((servers as Map?) ?? {});
    final before = jsonEncode(map);
    final result = change(map);
    if (jsonEncode(map) != before) {
      config[client.serversKey] = map;
      file
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(config)}\n',
        );
    }
    return result;
  }

  /// A line that starts a TOML table: `[a.b]` or `[[a.b]]`.
  // ponytail: line-based, not a TOML parser. A multi-line array whose
  // element line is a bare `["x"]` would read as a header; Codex configs
  // written by `codex mcp add` or by hand don't have those.
  static final _tomlHeader = RegExp(
    r'^\s*\[\[?\s*([^\[\]]+?)\s*\]\]?\s*(#.*)?$',
  );

  /// [text] split into its tables: the header's name (null before the
  /// first header) and the lines up to the next header.
  static List<({String? table, List<String> lines})> _tomlTables(String text) {
    final tables = [(table: null as String?, lines: <String>[])];
    for (final line in const LineSplitter().convert(text)) {
      final header = _tomlHeader.firstMatch(line);
      if (header != null) tables.add((table: header.group(1), lines: []));
      tables.last.lines.add(line);
    }
    return tables;
  }

  /// The servers in a Codex config as a JSON-like map (name → command and
  /// args, where they are written the way JSON writes them), for the same
  /// [change] callbacks the JSON clients use.
  static Map<String, dynamic> _tomlServers(String text, String key) {
    final servers = <String, dynamic>{};
    for (final (:table, :lines) in _tomlTables(text)) {
      if (table == null || !table.startsWith('$key.')) continue;
      final name = table.substring(key.length + 1);
      if (name.contains('.')) continue; // [mcp_servers.x.env]
      final entry = <String, dynamic>{};
      for (final line in lines.skip(1)) {
        final eq = line.indexOf('=');
        if (eq < 0) continue;
        try {
          entry[line.substring(0, eq).trim()] = jsonDecode(
            line.substring(eq + 1).trim(),
          );
        } on FormatException {
          // A value JSON can't read (a 'literal' string, an inline table).
          entry[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
        }
      }
      servers[name] = entry;
    }
    return servers;
  }

  /// [_editServers] for Codex's TOML: the `[mcp_servers.<name>]` table is
  /// added or replaced as text, everything else stays byte for byte.
  static String _editToml(
    String project,
    McpClient client,
    String name,
    Map<String, Object> entry,
    String Function(Map<String, dynamic> servers) change,
  ) {
    final file = File(p.join(project, client.configPath));
    final text = file.existsSync() ? file.readAsStringSync() : '';
    final servers = _tomlServers(text, client.serversKey);
    final before = jsonEncode(servers[name]);
    final result = change(servers);
    if (jsonEncode(servers[name]) == before) return result;
    final table = '${client.serversKey}.$name';
    final kept = [
      for (final (table: t, :lines) in _tomlTables(text))
        if (t != table && !(t?.startsWith('$table.') ?? false)) ...lines,
    ];
    while (kept.isNotEmpty && kept.last.trim().isEmpty) {
      kept.removeLast();
    }
    // JSON strings and lists of strings are valid TOML as they are.
    final added = [
      '[$table]',
      for (final MapEntry(:key, :value) in entry.entries)
        '$key = ${jsonEncode(value)}',
    ];
    file
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${[...kept, if (kept.isNotEmpty) '', ...added].join('\n')}\n',
      );
    return result;
  }

  /// What starts FlutterPilot in [client]'s config under [project]: null
  /// when the file or the entry isn't there. Throws a [FormatException]
  /// for a file that can't be read (JSONC).
  static ServerLaunch? installedLaunch(String project, McpClient client) {
    final file = File(p.join(project, client.configPath));
    if (!file.existsSync()) return null;
    final text = file.readAsStringSync();
    final Object? servers = client.isToml
        ? _tomlServers(text, client.serversKey)
        : (jsonDecode(text) as Map)[client.serversKey];
    final entry = servers is Map ? servers['flutterpilot'] : null;
    if (entry is! Map) return null;
    final command = entry['command'];
    final args = (entry['args'] as List?)?.whereType<String>().toList() ?? [];
    // opencode: one list, the executable first.
    if (command is List && command.isNotEmpty) {
      final all = command.whereType<String>().toList();
      return (command: all.first, args: all.sublist(1));
    }
    return command is String ? (command: command, args: args) : null;
  }

  /// The flutterpilot_server package: from --local, or next to this CLI's
  /// own package (a checkout, or the clone `pub global activate` made);
  /// null when the CLI came from pub.dev and has no server beside it.
  static Future<String?> _serverPackage(String? local) async {
    String dir;
    if (local != null) {
      dir = p.join(p.absolute(local), 'packages', 'flutterpilot_server');
    } else {
      final lib = await Isolate.resolvePackageUri(
        Uri.parse('package:flutterpilot_cli/flutterpilot_cli.dart'),
      );
      if (lib == null) return null;
      dir = p.normalize(
        p.join(p.dirname(lib.toFilePath()), '..', '..', 'flutterpilot_server'),
      );
      if (!File(p.join(dir, 'bin', 'flutterpilot_server.dart')).existsSync()) {
        return null;
      }
    }
    if (!File(p.join(dir, 'bin', 'flutterpilot_server.dart')).existsSync()) {
      throw UsageException(
        'No FlutterPilot server at $dir; pass --local <FlutterPilot checkout>.',
        '',
      );
    }
    return dir;
  }

  /// Where a pub.dev install keeps the server it builds:
  /// `~/.flutterpilot` (or `$FLUTTERPILOT_HOME`).
  static String get homeDir {
    final env = Platform.environment;
    return env['FLUTTERPILOT_HOME'] ??
        p.join(env['HOME'] ?? env['USERPROFILE'] ?? '.', '.flutterpilot');
  }

  /// A small package depending on flutterpilot_server (this release from
  /// pub.dev, or [serverPath]) whose executable is the server — for a CLI
  /// installed from pub.dev, which has no server beside it.
  static String _hostPackage(String? serverPath) {
    final dir = p.join(homeDir, 'server');
    final dependency = serverPath == null
        ? '^$flutterpilotVersion'
        : '\n    path: ${jsonEncode(p.absolute(serverPath))}';
    File(p.join(dir, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'name: flutterpilot_server_host\n'
        'publish_to: none\n'
        'environment:\n  sdk: ^3.11.0\n'
        'dependencies:\n  flutterpilot_server: $dependency\n',
      );
    File(p.join(dir, 'bin', 'flutterpilot_server.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'package:flutterpilot_server/flutterpilot_server.dart';\n\n"
        'Future<void> main(List<String> args) => runFlutterPilotServer(args);\n',
      );
    // Its pubspec may name a new version: resolve again.
    final config = File(p.join(dir, '.dart_tool', 'package_config.json'));
    if (config.existsSync()) config.deleteSync();
    return dir;
  }

  /// Compiles the server to `build/flutterpilot_server` — again on every
  /// install, so an update never leaves a stale executable.
  static Future<void> _dart(String dir, List<String> args) async {
    final dart = Platform.resolvedExecutable;
    final r = await Process.run(dart, args, workingDirectory: dir);
    if (r.exitCode != 0) {
      throw ProcessException(
        dart,
        args,
        'dart ${args.join(' ')} failed in $dir:\n${r.stdout}${r.stderr}',
        r.exitCode,
      );
    }
  }

  /// Fetches the server's dependencies if they aren't yet.
  static Future<void> _resolve(String serverDir) async {
    if (!File(
      p.join(serverDir, '.dart_tool', 'package_config.json'),
    ).existsSync()) {
      stdout.writeln('Fetching server dependencies…');
      await _dart(serverDir, ['pub', 'get']);
    }
  }

  static Future<ServerLaunch> _compile(String serverDir) async {
    final exe = p.join(
      serverDir,
      'build',
      Platform.isWindows ? 'flutterpilot_server.exe' : 'flutterpilot_server',
    );
    Directory(p.dirname(exe)).createSync(recursive: true);
    stdout.writeln('Compiling the FlutterPilot server (about a minute)…');
    await _dart(serverDir, [
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
