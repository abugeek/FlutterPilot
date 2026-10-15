import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What `flutterpilot smoke` does with an app: visit its screens, check each
/// for layout and accessibility problems and errors, write a report. These
/// are the parts that need no running app.

/// The route paths of a `get_navigation_stack(routes: true)` answer that can
/// be visited as they are: go_router's table (nested paths joined), without
/// parameters (`:id`) or wildcards. Empty when there is no table.
///
/// The JSON to read is the one after the `Routes: ` label. The same answer
/// prints `Path params: {id: 1}` (and `Query params: {…}`) first, and those
/// braces are not JSON, so scanning for the first `{` found no table on any
/// route with parameters (field test #344). The list is always growable: the
/// caller adds the current route to it.
List<String> routePaths(String toolText) {
  final line = RegExp(
    r'(?:^|\n)[ \t]*Routes:[ \t]*(\{.*)',
  ).firstMatch(toolText);
  Object? json;
  try {
    json = jsonDecode(line?.group(1) ?? '');
  } catch (_) {
    return <String>[];
  }
  final out = <String>[];
  void walk(Object? routes, String parent) {
    if (routes is! List) return;
    for (final r in routes.whereType<Map>()) {
      final path = r['path'];
      var full = parent;
      if (path is String) {
        full = path.startsWith('/')
            ? path
            : (parent.endsWith('/') ? '$parent$path' : '$parent/$path');
        if (!full.contains(':') && !full.contains('*') && !out.contains(full)) {
          out.add(full);
        }
      }
      walk(r['children'], full);
    }
  }

  if (json is Map) {
    walk(json['routes'] ?? (json['config'] as Map?)?['routes'], '');
  }
  return out;
}

/// The route in `• Route: /x (Depth: 1)` of a get_app_summary answer.
String? currentRoute(String summary) =>
    RegExp(r'• Route: (\S+)').firstMatch(summary)?.group(1);

/// The number in `• Uncaught Errors (3): …`.
int uncaughtErrors(String summary) =>
    int.tryParse(
      RegExp(r'Uncaught Errors \((\d+)\)').firstMatch(summary)?.group(1) ?? '',
    ) ??
    0;

/// What was found on one screen.
///
/// A screen is audited twice by default: at the app's current text scale and
/// at [textScale2]. Large text reflows a screen — a row that fits at 1.0 can
/// overflow at 2.0 — so both passes are kept apart in the report.
class ScreenResult {
  ScreenResult(
    this.route, {
    this.audit = '',
    this.auditLarge,
    this.errors = '',
    this.shot,
  });
  final String route;

  /// The audit_screen_health answer at the app's current text scale.
  final String audit;

  /// The audit_screen_health answer at [textScale2], null when that pass was
  /// not run (--no-text-scale, or an app that cannot set the scale).
  final String? auditLarge;

  /// The get_errors answer (empty when there are none).
  final String errors;

  /// Screenshot file name in the report folder.
  final String? shot;

  /// The text scale the second pass uses.
  static const double textScale2 = 2;

  bool get baseAuditClean => audit.startsWith('No layout overflows');
  bool get largeAuditClean =>
      auditLarge == null || auditLarge!.startsWith('No layout overflows');
  bool get auditClean => baseAuditClean && largeAuditClean;
  bool get hasErrors => errors.isNotEmpty;
  bool get ok => auditClean && !hasErrors;
}

/// The report: a table, then each screen with its findings.
///
/// [textScalePass] says the screens were audited at [ScreenResult.textScale2]
/// as well, so the reader knows why a screen can have findings in the second
/// block only.
String smokeReport(
  List<ScreenResult> screens, {
  required DateTime at,
  String? device,
  String? app,
  String? note,
  bool textScalePass = false,
}) {
  final bad = screens.where((s) => !s.ok).length;
  final scale = ScreenResult.textScale2.toInt();
  final b = StringBuffer()
    ..writeln('# FlutterPilot smoke — ${app ?? 'app'}')
    ..writeln()
    ..writeln(
      '${at.toIso8601String()}${device == null ? '' : ' · $device'} · '
      '${textScalePass ? 'text scale 1 and $scale · ' : ''}'
      '${screens.length} screen${screens.length == 1 ? '' : 's'}, '
      '${bad == 0 ? 'all clean' : '$bad with findings'}',
    )
    ..writeln();
  if (note != null)
    b
      ..writeln(note)
      ..writeln();
  b
    ..writeln('| Screen | Layout & accessibility | Errors |')
    ..writeln('|---|---|---|');
  for (final s in screens) {
    // 'findings at 2x' tells the two passes apart: the screen is fine at the
    // app's own scale but not with large text.
    final layout = s.auditClean
        ? 'clean'
        : s.baseAuditClean
        ? 'findings at ${scale}x'
        : 'findings';
    b.writeln('| `${s.route}` | $layout | ${s.hasErrors ? 'yes' : 'none'} |');
  }
  for (final s in screens.where((s) => !s.ok)) {
    b
      ..writeln()
      ..writeln('## `${s.route}`')
      ..writeln();
    if (s.shot != null)
      b
        ..writeln('![${s.route}](${s.shot})')
        ..writeln();
    if (!s.baseAuditClean) {
      // With a second pass, name this one so the blocks below are readable.
      if (s.auditLarge != null) b.writeln("At the app's text scale:");
      b
        ..writeln(_capped(s.audit.trim()))
        ..writeln();
    }
    if (!s.largeAuditClean)
      b
        ..writeln('At text scale $scale:')
        ..writeln(_capped(s.auditLarge!.trim()))
        ..writeln();
    if (s.hasErrors)
      b
        ..writeln('Errors:')
        ..writeln(_capped(s.errors.trim()));
  }
  return b.toString();
}

/// The folder-safe name of a route (`/a/b` -> `a_b`, `/` -> `root`).
String routeFileName(String route) {
  final cleaned = route.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  final trimmed = cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
  return trimmed.isEmpty ? 'root' : trimmed;
}

/// A tool call's answer.
class McpAnswer {
  McpAnswer(this.isError, this.text, this.images);
  final bool isError;
  final String text;
  final List<List<int>> images;
}

/// A FlutterPilot server child process spoken to over MCP stdio.
class McpSession {
  McpSession._(this._process);
  final Process _process;
  StreamSubscription<String>? _stderr;
  final _pending = <int, Completer<Map>>{};
  var _id = 0;

  static Future<McpSession> start(
    String executable,
    List<String> args, {
    String? workingDirectory,
    IOSink? log,
  }) async {
    final process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
    );
    final s = McpSession._(process);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          try {
            final m = jsonDecode(line) as Map;
            s._pending.remove(m['id'])?.complete(m);
          } catch (_) {}
        });
    s._stderr = process.stderr.transform(utf8.decoder).listen((t) {
      try {
        log?.write(t);
      } catch (_) {
        // The log was closed: the session is over.
      }
    });
    await s._rpc('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'flutterpilot-smoke', 'version': '1'},
    }, const Duration(seconds: 120));
    process.stdin.writeln(
      jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
    );
    return s;
  }

  Future<Map> _rpc(String method, Map params, Duration timeout) {
    final c = _pending[++_id] = Completer<Map>();
    _process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': _id,
        'method': method,
        'params': params,
      }),
    );
    return c.future.timeout(
      timeout,
      onTimeout: () => {
        'error': {'message': 'no answer to $method in ${timeout.inSeconds} s'},
      },
    );
  }

  Future<McpAnswer> call(
    String tool,
    Map<String, Object?> arguments, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final res = await _rpc('tools/call', {
      'name': tool,
      'arguments': arguments,
    }, timeout);
    if (res['error'] != null) {
      return McpAnswer(true, '${(res['error'] as Map)['message']}', const []);
    }
    final result = res['result'] as Map? ?? const {};
    final text = StringBuffer();
    final images = <List<int>>[];
    for (final c in (result['content'] as List? ?? const []).whereType<Map>()) {
      if (c['type'] == 'image') {
        images.add(base64.decode('${c['data']}'));
      } else {
        text.writeln(c['text']);
      }
    }
    return McpAnswer(result['isError'] == true, text.toString().trim(), images);
  }

  Future<void> close() async {
    await _stderr?.cancel();
    try {
      await _process.stdin.close();
    } catch (_) {}
    _process.kill();
  }
}

/// A screen's findings can run to pages (a reading order of 30 controls).
String _capped(String text, {int max = 4000}) => text.length <= max
    ? text
    : '${text.substring(0, max)}\n… (${text.length - max} more characters)';
