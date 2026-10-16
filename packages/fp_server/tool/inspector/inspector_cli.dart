// Official MCP Inspector interoperability check (task 03).
//
// Runs the **pinned** official Inspector CLI (`@modelcontextprotocol/inspector`
// 2.11.0, pinned in `tool/inspector/package-lock.json`) against the FlutterPilot
// server over stdio, and asserts the discovery / call / refusal surface a real,
// independently maintained client sees. The raw suite
// (`test/mcp_protocol_compliance_test.dart`) keeps the framing and
// persistent-session checks; this wrapper is the independent-client smoke.
//
// The Inspector is a Node tool. Nothing here is required to build, ship or run
// the Dart server: Node is only needed for this development check.
//
// Run it from `packages/fp_server` after installing the pinned tool:
//
//   cd packages/fp_server/tool/inspector && npm ci --no-audit --no-fund
//   cd packages/fp_server && dart run tool/inspector/inspector_cli.dart
//
// Exit code is 0 when every probe passes, 1 otherwise.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../support/process_tree.dart';

/// The Inspector release this check is written against. It must match
/// `package.json` / `package-lock.json` in `tool/inspector`; a mismatch is a
/// setup error, not a server failure.
const inspectorVersion = '2.11.0';

/// The Node engine floor the pinned Inspector declares (`engines.node`).
const inspectorNodeFloor = '22.19.0';

/// The protocol era the check negotiates. FlutterPilot answers the classic
/// `initialize` handshake (newest `2025-11-25`), so we ask for `legacy` rather
/// than letting the Inspector default to a newer stateless profile.
const requestedEra = 'legacy';

/// The exit classes the pinned CLI documents (`clients/cli/README.md`).
enum InspectorExit {
  success(0, 'success'),
  usage(1, 'usage'),
  noApp(2, 'no_app'),
  authRequired(3, 'auth_required'),
  unreachable(4, 'unreachable'),
  toolError(5, 'tool_error'),
  schemaUnportable(6, 'schema_unportable'),
  unknown(-1, 'unknown');

  const InspectorExit(this.code, this.label);
  final int code;
  final String label;

  static InspectorExit of(int code) => InspectorExit.values.firstWhere(
    (value) => value.code == code,
    orElse: () => InspectorExit.unknown,
  );
}

/// One Inspector CLI invocation's observable outcome.
class InspectorResult {
  InspectorResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.truncated,
    required this.timedOut,
    required this.durationMs,
    required this.envelope,
    required this.errorEnvelope,
    required this.stdoutIsJson,
  });

  final int exitCode;
  final String stdout;

  /// The last non-empty stderr line, which the Inspector promises is a one-line
  /// `{ "error": { "code": … } }` envelope on a non-zero exit.
  final String stderr;
  final bool truncated;
  final bool timedOut;
  final int durationMs;

  /// The `{"result": …}` (or `{"appInfo": …}`) envelope parsed from stdout, when
  /// stdout carried exactly one JSON object.
  final Map<String, dynamic>? envelope;

  /// The parsed `{"error": {…}}` envelope from stderr, when the last stderr line
  /// is one.
  final Map<String, dynamic>? errorEnvelope;

  /// Whether stdout was the machine-readable envelope it should be. False means
  /// the run is not trustworthy regardless of exit code.
  final bool stdoutIsJson;

  InspectorExit get exitClass => InspectorExit.of(exitCode);

  /// The `result` member of the stdout envelope, if any.
  Map<String, dynamic>? get result =>
      (envelope?['result'] as Map?)?.cast<String, dynamic>();

  /// The failure code the CLI reported on stderr (`unreachable`, `tool_error`,
  /// …), or null when it reported none.
  String? get errorCode => '${(errorEnvelope?['error'] as Map?)?['code']}';

  bool get ok => exitCode == 0 && stdoutIsJson && !timedOut && !truncated;
}

/// Runs the pinned Inspector CLI as one process per probe, with explicit
/// argument arrays, an isolated read-only config, an isolated secret store, and
/// a bounded deadline whose expiry kills the whole process tree.
class InspectorRunner {
  InspectorRunner({
    required this.nodeExecutable,
    required this.launcherEntry,
    required this.configPath,
    this.serverName = 'flutterpilot',
    this.connectTimeout = const Duration(seconds: 20),
    this.deadline = const Duration(seconds: 90),
    this.maxOutputBytes = 256 * 1024,
    Map<String, String>? environment,
  }) : environment = environment ?? const {};

  /// `node` (or, in tests, any executable that accepts the launcher entry as its
  /// first argument).
  final String nodeExecutable;

  /// The pinned launcher bundle, e.g.
  /// `tool/inspector/node_modules/@modelcontextprotocol/inspector/clients/launcher/build/index.js`.
  final String launcherEntry;
  final String configPath;
  final String serverName;
  final Duration connectTimeout;

  /// The hard per-probe wall clock. On expiry the tree is killed and the result
  /// reports [InspectorResult.timedOut].
  final Duration deadline;

  /// Captured stdout/stderr are capped here so a runaway server cannot exhaust
  /// memory; [InspectorResult.truncated] records that the cap was hit.
  final int maxOutputBytes;

  /// Extra environment entries merged over the parent environment. The caller
  /// passes the store isolation here.
  final Map<String, String> environment;

  /// The argv (after the node executable and launcher entry) for one probe.
  List<String> argv(List<String> methodArgs) => [
    '--cli',
    '--config',
    configPath,
    '--server',
    serverName,
    '--connect-timeout',
    '${connectTimeout.inMilliseconds}',
    '-q',
    ...methodArgs,
  ];

  /// Runs one probe. Never throws for a non-zero exit, a timeout, or malformed
  /// output: those are reported on the result.
  Future<InspectorResult> run(List<String> methodArgs) async {
    final stopwatch = Stopwatch()..start();
    final process = await Process.start(
      nodeExecutable,
      [launcherEntry, ...argv(methodArgs)],
      workingDirectory: Directory.current.path,
      environment: environment,
      includeParentEnvironment: true,
    );

    var truncated = false;
    final out = BytesBuilder(copy: false);
    final err = BytesBuilder(copy: false);
    void keep(BytesBuilder sink, List<int> chunk) {
      if (sink.length >= maxOutputBytes) {
        truncated = true;
        return;
      }
      if (sink.length + chunk.length > maxOutputBytes) {
        truncated = true;
        sink.add(chunk.sublist(0, maxOutputBytes - sink.length));
        return;
      }
      sink.add(chunk);
    }

    final stdoutDone = process.stdout.forEach((chunk) => keep(out, chunk));
    final stderrDone = process.stderr.forEach((chunk) => keep(err, chunk));
    final exitDone = process.exitCode;

    var timedOut = false;
    var exitValue = -1;
    try {
      exitValue = await exitDone.timeout(deadline);
    } on TimeoutException {
      timedOut = true;
      await killProcessTree(process);
      // Let the streams drain after the kill so we keep whatever arrived.
      exitValue = await exitDone;
    }
    await Future.wait([stdoutDone, stderrDone]).catchError((_) => <void>[]);
    stopwatch.stop();

    final stdout = utf8.decode(out.takeBytes(), allowMalformed: true);
    final stderr = utf8.decode(err.takeBytes(), allowMalformed: true);
    final (envelope, stdoutIsJson) = _parseEnvelope(stdout);
    return InspectorResult(
      exitCode: exitValue,
      stdout: stdout,
      stderr: _lastNonEmptyLine(stderr),
      truncated: truncated,
      timedOut: timedOut,
      durationMs: stopwatch.elapsedMilliseconds,
      envelope: envelope,
      errorEnvelope: _parseError(_lastNonEmptyLine(stderr)),
      stdoutIsJson: stdoutIsJson,
    );
  }

  /// Parses the single JSON envelope the Inspector writes under
  /// `-q --format json`. A banner, a second object, or any trailing output makes
  /// the run untrustworthy: stdout must be exactly one JSON object.
  static (Map<String, dynamic>?, bool) _parseEnvelope(String stdout) {
    final text = stdout.trim();
    if (text.isEmpty) return (null, false);
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return (null, false);
    }
    if (decoded is! Map) return (null, false);
    return (decoded.cast<String, dynamic>(), true);
  }

  static Map<String, dynamic>? _parseError(String line) {
    if (line.isEmpty) return null;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map && decoded['error'] is Map) {
        return decoded.cast<String, dynamic>();
      }
    } on FormatException {
      // Not an envelope.
    }
    return null;
  }

  static String _lastNonEmptyLine(String text) {
    final lines = const LineSplitter().convert(text);
    for (final line in lines.reversed) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return '';
  }
}

// ---------------------------------------------------------------------------
// The check itself
// ---------------------------------------------------------------------------

/// One probe: a human label and the argv after the launcher entry.
class Probe {
  const Probe(this.label, this.args);
  final String label;
  final List<String> args;
}

/// Every probe the check runs, in order. Read-only and safe to repeat: none of
/// them needs a running Flutter app (a connected run is a separate, manual
/// fixture — see `README.md`).
const probes = <Probe>[
  Probe('initialize (connect-only handshake)', [
    '--method',
    'initialize',
    '--format',
    'json',
  ]),
  Probe('tools/list', ['--method', 'tools/list', '--format', 'json']),
  Probe('resources/list', ['--method', 'resources/list', '--format', 'json']),
  Probe('resources/templates/list', [
    '--method',
    'resources/templates/list',
    '--format',
    'json',
  ]),
  Probe('prompts/list', ['--method', 'prompts/list', '--format', 'json']),
  Probe('tools/list --strict (no error-severity)', [
    '--method',
    'tools/list',
    '--strict',
    '--format',
    'json',
  ]),
  Probe('tools/call list_connected_devices (safe, no app)', [
    '--method',
    'tools/call',
    '--tool-name',
    'list_connected_devices',
    '--format',
    'json',
  ]),
  Probe('resources/read (disconnected)', [
    '--method',
    'resources/read',
    '--uri',
    'flutterpilot://app/summary',
    '--format',
    'json',
  ]),
  Probe('prompts/get flutterpilot_guide', [
    '--method',
    'prompts/get',
    '--prompt-name',
    'flutterpilot_guide',
    '--format',
    'json',
  ]),
];

/// A well-formed-looking model that must be refused. It is the negative
/// counterpart: a call the server must reject, naming the argument.
const refusalProbe = Probe('tools/call execute_action_chain (missing steps)', [
  '--method',
  'tools/call',
  '--tool-name',
  'execute_action_chain',
  '--tool-args-json',
  '{}',
  '--format',
  'json',
]);

Future<void> main(List<String> args) async {
  final asJson = args.contains('--json');
  final reportPath = _valueOf(args, '--report');
  final nodeExecutable = _valueOf(args, '--node') ?? 'node';

  final packageRoot = Directory.current;
  final entry = File('bin/fp_server.dart');
  if (!entry.existsSync()) {
    stderr.writeln(
      'inspector_cli: run this from packages/fp_server '
      '(no bin/fp_server.dart in ${packageRoot.path}).',
    );
    exitCode = 1;
    return;
  }
  final launcher = File(
    'tool/inspector/node_modules/@modelcontextprotocol/inspector/'
    'clients/launcher/build/index.js',
  );
  if (!launcher.existsSync()) {
    stderr.writeln(
      'inspector_cli: the pinned Inspector is not installed.\n'
      '  cd tool/inspector && npm ci --no-audit --no-fund\n'
      'Expected ${launcher.path}',
    );
    exitCode = 1;
    return;
  }

  final scratch = Directory.systemTemp.createTempSync('fp_inspector_');
  final report = <String, dynamic>{
    'inspector': {
      'package': '@modelcontextprotocol/inspector',
      'version': inspectorVersion,
      'nodeFloor': inspectorNodeFloor,
      'node': await _firstLine(['node', '--version'], fallback: 'unknown'),
    },
    'dart': await _firstLine([
      Platform.resolvedExecutable,
      '--version',
    ], fallback: 'unknown'),
    'server': {
      'revision': await _firstLine([
        'git',
        'rev-parse',
        '--short',
        'HEAD',
      ], fallback: 'unknown'),
      'entrypoint': entry.path,
    },
    'protocol': {'requestedEra': requestedEra, 'negotiated': null},
    'strictFindings': null,
    'probes': <Map<String, dynamic>>[],
  };

  try {
    final configPath = '${scratch.path}${Platform.pathSeparator}mcp.json';
    File(configPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_serverConfig(packageRoot)),
    );

    final runner = InspectorRunner(
      nodeExecutable: nodeExecutable,
      launcherEntry: launcher.path,
      configPath: configPath,
      environment: {
        // Isolate the OAuth/secret store so a smoke run never reads or rotates
        // a developer's real tokens, and never opens a browser.
        'MCP_STORAGE_DIR': scratch.path,
        'MCP_INSPECTOR_OAUTH_STATE_PATH':
            '${scratch.path}${Platform.pathSeparator}oauth.json',
        'MCP_AUTO_OPEN_ENABLED': 'false',
      },
    );

    var failed = false;
    for (final probe in probes) {
      final result = await runner.run(probe.args);
      final checks = _checksFor(probe, result, report);
      report['probes'] = [
        ...(report['probes'] as List),
        {
          'label': probe.label,
          'exit': result.exitCode,
          'class': result.exitClass.label,
          'durationMs': result.durationMs,
          'timedOut': result.timedOut,
          'stdoutIsJson': result.stdoutIsJson,
          'errorCode': result.errorCode,
          'checks': checks,
        },
      ];
      if (checks.values.any((ok) => ok != true)) failed = true;
    }

    // The negative probe: a call the server must refuse, by name.
    final refusal = await runner.run(refusalProbe.args);
    final refusalText = _textOf(refusal.result);
    final refusalChecks = <String, bool>{
      'exit is 5 (tool_error)': refusal.exitCode == 5,
      'stdout is the machine envelope': refusal.stdoutIsJson,
      'isError is true': refusal.result?['isError'] == true,
      'names the missing argument "steps"': refusalText.contains('steps'),
    };
    report['probes'] = [
      ...(report['probes'] as List),
      {
        'label': refusalProbe.label,
        'exit': refusal.exitCode,
        'class': refusal.exitClass.label,
        'errorCode': refusal.errorCode,
        'checks': refusalChecks,
      },
    ];
    if (refusalChecks.values.any((ok) => !ok)) failed = true;

    // A malformed call must leave the server usable — proven by a good probe
    // after the refusal.
    final after = await runner.run(probes.first.args);
    final recovered = after.exitCode == 0 && after.stdoutIsJson;
    report['recoveredAfterRefusal'] = recovered;
    if (!recovered) failed = true;

    report['ok'] = !failed;
    if (reportPath != null) {
      File(
        reportPath,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    }
    if (asJson) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    } else {
      _printHuman(report);
    }
    exitCode = failed ? 1 : 0;
  } finally {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// The read-only session config the Inspector connects to. A `--config` file is
/// never written by the Inspector, so the bytes stay ours.
Map<String, dynamic> _serverConfig(Directory packageRoot) => {
  'mcpServers': {
    'flutterpilot': {
      'type': 'stdio',
      // The real Dart executable, not the `dart` shell/batch shim: the Inspector
      // spawns the command directly (no shell), and a `.bat` cannot be executed
      // without one.
      'command': Platform.resolvedExecutable,
      'args': [
        'run',
        'bin/fp_server.dart',
        '--log-level',
        'severe',
        '--no-call-log',
      ],
      'cwd': packageRoot.absolute.path,
      'env': {'FLUTTERPILOT_LIST_ALL_TOOLS': '1'},
      'protocolEra': requestedEra,
      'connectionTimeout': 20000,
    },
  },
};

/// The assertions for a discovery probe, keyed by a human description.
Map<String, bool> _checksFor(
  Probe probe,
  InspectorResult result,
  Map<String, dynamic> report,
) {
  final checks = <String, bool>{
    'exit is 0': result.exitCode == 0,
    'stdout is the machine envelope': result.stdoutIsJson,
  };
  final resultBody = result.result;
  switch (probe.args[1]) {
    case 'initialize':
      final info = (resultBody?['serverInfo'] as Map?)?.cast<String, dynamic>();
      report['protocol'] = {
        'requestedEra': requestedEra,
        'negotiated': resultBody?['protocolVersion'],
        'serverName': info?['name'],
        'serverVersion': info?['version'],
      };
      checks['identifies as FlutterPilot'] = info?['name'] == 'FlutterPilot';
      checks['negotiates a protocol version'] =
          '${resultBody?['protocolVersion']}'.isNotEmpty;
    case 'tools/list':
      final tools = (resultBody?['tools'] as List?) ?? const [];
      final names = [
        for (final tool in tools)
          if (tool is Map) '${tool['name']}',
      ];
      checks['lists tools'] = tools.isNotEmpty;
      // A representative entry, so "non-empty" cannot be satisfied by a stray
      // object: the safe tool the call probe uses must be present.
      checks['lists list_connected_devices'] = names.contains(
        'list_connected_devices',
      );
      if (probe.args.contains('--strict')) {
        // Only error-severity findings change the exit code (6). A warning-only
        // list still exits 0; record the finding count for the report.
        checks['no error-severity schema findings (exit != 6)'] =
            result.exitCode != 6;
        report['strictFindings'] = _strictSummary(result.stderr);
      }
    case 'resources/list':
      final resources = (resultBody?['resources'] as List?) ?? const [];
      final uris = [
        for (final resource in resources)
          if (resource is Map) '${resource['uri']}',
      ];
      checks['lists resources'] = resources.isNotEmpty;
      checks['lists a representative resource'] = uris.contains(
        'flutterpilot://app/summary',
      );
    case 'resources/templates/list':
      checks['lists resource templates'] =
          ((resultBody?['resourceTemplates'] as List?) ?? const []).isNotEmpty;
    case 'prompts/list':
      checks['lists prompts'] =
          ((resultBody?['prompts'] as List?) ?? const []).isNotEmpty;
    case 'tools/call':
      checks['isError is not true'] = resultBody?['isError'] != true;
      checks['has content'] = _textOf(resultBody).isNotEmpty;
    case 'resources/read':
      final contents = (resultBody?['contents'] as List?) ?? const [];
      checks['returns contents'] = contents.isNotEmpty;
    case 'prompts/get':
      checks['returns messages'] =
          ((resultBody?['messages'] as List?) ?? const []).isNotEmpty;
  }
  return checks;
}

/// The `N errors, M warnings across K tools.` line the strict report ends with.
String? _strictSummary(String stderr) {
  final match = RegExp(
    r'\d+ errors?, \d+ warnings? across \d+ tools?\.',
  ).firstMatch(stderr);
  return match?.group(0);
}

String _textOf(Map<String, dynamic>? result) {
  final content = result?['content'];
  if (content is! List) return '';
  return content
      .whereType<Map>()
      .map((part) => '${part['text'] ?? ''}')
      .join('\n');
}

Future<String> _firstLine(
  List<String> command, {
  required String fallback,
}) async {
  try {
    final result = await Process.run(command.first, command.sublist(1));
    // `dart --version` writes to stderr; `node --version` and `git` to stdout.
    final text = '${result.stdout}${result.stderr}'.trim();
    return text.isEmpty ? fallback : text.split('\n').first.trim();
  } catch (_) {
    return fallback;
  }
}

String? _valueOf(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

void _printHuman(Map<String, dynamic> report) {
  final inspector = report['inspector'] as Map<String, dynamic>;
  stdout.writeln(
    'MCP Inspector ${inspector['version']} '
    '(node ${inspector['node']}) vs FlutterPilot '
    '${(report['server'] as Map)['revision']}',
  );
  final protocol = report['protocol'] as Map<String, dynamic>;
  stdout.writeln(
    'protocol: requested ${protocol['requestedEra']}, '
    'negotiated ${protocol['negotiated']}',
  );
  if (report['strictFindings'] != null) {
    stdout.writeln('strict schema findings: ${report['strictFindings']}');
  }
  for (final probe in report['probes'] as List) {
    final map = probe as Map<String, dynamic>;
    final checks = (map['checks'] as Map).values.every((ok) => ok == true);
    stdout.writeln(
      '${checks ? 'ok  ' : 'FAIL'} ${map['label']} '
      '(exit ${map['exit']})',
    );
    if (!checks) {
      for (final entry in (map['checks'] as Map).entries) {
        if (entry.value != true) stdout.writeln('      - ${entry.key}');
      }
    }
  }
  stdout.writeln(report['ok'] == true ? 'inspector OK' : 'inspector FAILED');
}
