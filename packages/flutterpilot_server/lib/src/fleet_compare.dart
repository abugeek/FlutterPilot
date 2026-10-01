/// run_on_devices: what one device did with the steps, and the screen it
/// ended on.
class DeviceRun {
  DeviceRun(this.device);

  final String device;

  /// Outcome of each step that ran (a device stops at its first failure).
  final steps = <({bool ok, String text})>[];

  /// Set when the device could not be reached at all.
  String? unreachable;

  /// The screen after the last step, from the app's snapshot.
  String? route;
  List<String> tappable = const [];

  /// Errors the app captured during the steps, and the newest one.
  int errors = 0;
  String? lastError;

  /// The app's error total before the steps (null: an SDK without it).
  int? _errorsBefore;

  /// Notes the error total before the first step.
  void readBaseline(Map<String, dynamic> snapshot) =>
      _errorsBefore = snapshot['errorCount'] as int?;

  /// Reads `ext.flutterpilot.getAppSnapshot`'s route, tappable elements
  /// (their label, else key, else type) and the errors since
  /// [readBaseline].
  void readSnapshot(Map<String, dynamic> snapshot) {
    route = (snapshot['route'] as Map?)?['current']?.toString();
    tappable = [
      for (final e in (snapshot['interactiveElements'] as List?) ?? const [])
        if (e is Map) '${e['text'] ?? e['key'] ?? e['type']}',
    ];
    final after = snapshot['errorCount'] as int?;
    final before = _errorsBefore;
    errors = after != null && before != null ? after - before : 0;
    lastError = errors > 0 ? snapshot['lastError']?.toString() : null;
  }
}

/// The first line of a tool's response, short enough for a table cell.
String _gist(String text) {
  var line = text
      .split('\n')
      .map((l) => l.trim())
      .firstWhere(
        (l) => l.isNotEmpty && !RegExp(r'^\(\d+ms\)$').hasMatch(l),
        orElse: () => '',
      );
  // "[extensionError] ASSERTION FAILED: …" → "ASSERTION FAILED: …"
  line = line.replaceFirst(RegExp(r'^\[\w+\] '), '');
  return line.length > 160 ? '${line.substring(0, 160)}…' : line;
}

/// The report run_on_devices returns: each step's outcome per device, then
/// how the devices' final screens differ. Devices that agree are grouped,
/// so a flow that works everywhere reads in a few lines.
String describeFleetRun(
  List<({String tool, Map<String, dynamic> arguments})> steps,
  List<DeviceRun> runs,
) {
  final out = StringBuffer(
    'Ran ${steps.length} step(s) on ${runs.length} devices '
    '(${runs.map((r) => r.device).join(', ')}).\n',
  );
  for (final r in runs.where((r) => r.unreachable != null)) {
    out.writeln('⚠️ ${r.device}: ${r.unreachable}');
  }
  final reached = runs.where((r) => r.unreachable == null).toList();
  var stepsDiffer = false;
  for (var i = 0; i < steps.length; i++) {
    final passed = [
      for (final r in reached)
        if (i < r.steps.length && r.steps[i].ok) r.device,
    ];
    final failed = [
      for (final r in reached)
        if (i < r.steps.length && !r.steps[i].ok) r,
    ];
    final skipped = [
      for (final r in reached)
        if (i >= r.steps.length) r.device,
    ];
    final cells = [
      if (passed.length == reached.length)
        '✅ all'
      else if (passed.isNotEmpty)
        '✅ ${passed.join(', ')}',
      for (final r in failed) '❌ ${r.device}: ${_gist(r.steps[i].text)}',
      if (skipped.isNotEmpty) '– ${skipped.join(', ')} (stopped earlier)',
    ];
    if (passed.length != reached.length) stepsDiffer = true;
    out.writeln(
      '${i + 1}. ${steps[i].tool} ${_args(steps[i].arguments)}: '
      '${cells.join(' · ')}',
    );
  }

  final diffs = <String>[];
  final routes = <String?, List<String>>{};
  for (final r in reached) {
    (routes[r.route] ??= []).add(r.device);
  }
  if (routes.length > 1) {
    diffs.add(
      'route: ${routes.entries.map((e) => '${e.value.join(', ')} "${e.key}"').join('; ')}',
    );
  }
  if (reached.length > 1) {
    // Elements not on every device, grouped by the devices that have them.
    final holders = <String, List<String>>{};
    for (final r in reached) {
      for (final t in r.tappable.toSet()) {
        (holders[t] ??= []).add(r.device);
      }
    }
    final byDevices = <String, List<String>>{};
    for (final MapEntry(key: label, value: devices) in holders.entries) {
      if (devices.length == reached.length) continue;
      (byDevices[devices.join(', ')] ??= []).add(label);
    }
    for (final MapEntry(key: devices, value: labels) in byDevices.entries) {
      diffs.add(
        'tappable on $devices only: '
        '${labels.take(8).map((t) => '"$t"').join(', ')}'
        '${labels.length > 8 ? ' (+${labels.length - 8} more)' : ''}',
      );
    }
  }
  final withErrors = reached.where((r) => r.errors > 0);
  if (withErrors.isNotEmpty) {
    diffs.add(
      'new errors: ${withErrors.map((r) => '${r.device} ${r.errors}${r.lastError == null ? '' : ' (last: ${_gist(r.lastError!)})'}').join(', ')} '
      '— switch_device + get_errors for details',
    );
  }
  if (diffs.isEmpty && !stepsDiffer && reached.length == runs.length) {
    out.write('All devices agree: same steps passed, same final screen.');
  } else if (diffs.isNotEmpty) {
    out.write(
      'Differences at the end:\n${diffs.map((d) => '- $d').join('\n')}',
    );
  } else {
    out.write('Final screens match.');
  }
  return out.toString();
}

/// Compact arguments: {key: "Log in"} → (key: "Log in").
String _args(Map<String, dynamic> args) {
  if (args.isEmpty) return '';
  final s = args.entries
      .map((e) => '${e.key}: ${e.value is String ? '"${e.value}"' : e.value}')
      .join(', ');
  return '(${s.length > 80 ? '${s.substring(0, 80)}…' : s})';
}
