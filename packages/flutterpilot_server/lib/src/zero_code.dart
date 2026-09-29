/// Zero-code mode: the app runs without `flutterpilot_sdk`, so FlutterPilot
/// answers from Flutter's own debug extensions (`ext.flutter.inspector.*`,
/// `Flutter.Error` events) and the VM service. Only tools that can give a
/// true answer that way stay listed; the rest need the SDK in the app.
library;

import 'dart:convert';

import 'package:image/image.dart' as img;

/// Tools that work against an app without the SDK. Proven on a plain
/// `flutter create` app; everything else is hidden until the SDK is found.
const Set<String> zeroCodeTools = {
  // Connection and fleet.
  'connect_app',
  'list_connected_devices',
  'register_device',
  'switch_device',
  'get_capabilities',
  // Inspection (answered from the Flutter inspector).
  'get_app_summary',
  'get_widget_tree',
  'capture_screenshot',
  'compare_screenshot',
  'get_errors',
  'get_debug_logs',
  // flutter_tools services and framework debug extensions (theme and the
  // debug overlays; the other settings need the SDK and say so).
  'hot_reload',
  'set_app_settings',
  // VM service.
  'get_memory_details',
  'get_http_profile',
};

/// The message for an SDK-only tool called against an app without the SDK.
String zeroCodeUnavailable(String what) =>
    '$what needs flutterpilot_sdk in the app, and this app runs without it '
    '(zero-code mode: FlutterPilot can inspect it but not drive it). '
    'Run "flutterpilot init" in the app folder, then restart the app with '
    '"flutter run". Without the SDK these work: '
    '${(zeroCodeTools.toList()..sort()).join(', ')}.';

/// Converts `ext.flutter.inspector.getRootWidgetTree` output (the full
/// tree, not the summary one) into the SDK's summary-tree shape: widgets
/// created by the app's own code, user keys and Text, each app widget with
/// its source location. Like the SDK it leaves out what isn't on screen:
/// overlay entries (covered routes) a `_Theater` skips ([skipCounts]:
/// valueId -> skipCount) and the IndexedStack children not selected
/// ([stackIndexes]: valueId -> index). [offstageHosts] lists those nodes.
Map<String, dynamic> summaryTreeFromInspector(
  Map<String, dynamic> root, {
  int maxDepth = 50,
  Map<String, int> skipCounts = const {},
  Map<String, int> stackIndexes = const {},
}) {
  List<Map<String, dynamic>> convert(Map node, int depth) {
    final type = node['widgetRuntimeType']?.toString() ?? '';
    final local = node['createdByLocalProject'] == true;
    final description = node['description']?.toString() ?? '';
    // Framework widgets carry internal keys (GlobalKeys, slots); keep the
    // app's own keys and plain ValueKeys, like the SDK.
    final key = RegExp(r'-(\[.*\])$').firstMatch(description)?.group(1);
    final userKey =
        key != null &&
            !key.contains('GlobalKey') &&
            (local || _plainValueKey.hasMatch(key))
        ? key
        : null;
    final text = type == 'Text' ? node['textPreview']?.toString() : null;
    final keep = local || userKey != null || type == 'Text';
    final childDepth = keep ? depth + 1 : depth;
    final skip = skipCounts[node['valueId']] ?? 0;
    final shown = stackIndexes[node['valueId']];
    final children = <Map<String, dynamic>>[];
    if (childDepth <= maxDepth) {
      final all = (node['children'] as List? ?? const []).whereType<Map>();
      var i = 0;
      for (final child in all) {
        final onScreen = i >= skip && (shown == null || i == shown);
        i++;
        if (onScreen) children.addAll(convert(child, childDepth));
      }
    }
    if (!keep) return children;
    final location = local ? _location(node['creationLocation']) : null;
    return [
      {
        'type': type,
        'key': ?userKey,
        if (text != null && text.isNotEmpty) 'text': text,
        'loc': ?location,
        if (children.isNotEmpty) 'children': children,
        if (childDepth > maxDepth && node['hasChildren'] == true)
          'truncated': true,
      },
    ];
  }

  final nodes = convert(root, 0);
  return nodes.length == 1 ? nodes.first : {'type': 'Root', 'children': nodes};
}

/// `ValueKey<String>` / `ValueKey<num>` as `Key.toString()` writes them.
final _plainValueKey = RegExp(r"^\[<('.*'|-?[\d.]+)>\]$");

/// valueIds of the nodes that keep children off screen: `_Theater` (the
/// Overlay that stacks routes; its `skipCount` entries are not painted) and
/// IndexedStack (only its render object's `index` child is painted).
({List<String> theaters, List<String> indexedStacks}) offstageHosts(
  Map<String, dynamic> root,
) {
  final theaters = <String>[];
  final indexedStacks = <String>[];
  void walk(Map node) {
    final id = node['valueId']?.toString();
    if (id != null) {
      switch (node['widgetRuntimeType']) {
        case '_Theater':
          theaters.add(id);
        case '_RawIndexedStack':
          indexedStacks.add(id);
      }
    }
    for (final child in (node['children'] as List? ?? const [])) {
      if (child is Map) walk(child);
    }
  }

  walk(root);
  return (theaters: theaters, indexedStacks: indexedStacks);
}

/// Texts and keys in a tree from [summaryTreeFromInspector], in paint order.
({List<String> texts, List<String> keys}) screenContent(
  Map<String, dynamic> tree,
) {
  final texts = <String>[];
  final keys = <String>[];
  void walk(Map node) {
    final text = node['text']?.toString();
    if (text != null && text.trim().isNotEmpty) texts.add(text.trim());
    final key = node['key']?.toString();
    if (key != null) keys.add(key);
    for (final child in (node['children'] as List? ?? const [])) {
      if (child is Map) walk(child);
    }
  }

  walk(tree);
  return (texts: texts, keys: keys);
}

/// Converts a `Flutter.Error` event (the structured error Flutter posts in
/// debug builds) into the SDK's error record.
Map<String, dynamic> errorFromFlutterErrorEvent(
  Map<String, dynamic> data,
  DateTime timestamp,
) {
  final properties = (data['properties'] as List? ?? const [])
      .whereType<Map>()
      .toList();
  String? summary;
  String? widget;
  final stack = <String>[];
  for (final p in properties) {
    final name = p['name']?.toString() ?? '';
    final children = (p['children'] as List? ?? const []).whereType<Map>();
    if (summary == null && p['type'] == 'ErrorSummary') {
      summary = p['description']?.toString();
    } else if (name.contains('relevant error-causing widget')) {
      widget = children
          .map((c) => c['description']?.toString() ?? '')
          .where((d) => d.isNotEmpty)
          .map(_shortenFileUris)
          .join(' ')
          // Flutter writes "Row Row:file:///…"; keep one type name.
          .replaceFirstMapped(RegExp(r'^(\w+) \1:'), (m) => '${m[1]} ');
    } else if (name.contains('this was the stack')) {
      stack.addAll(
        children
            .map((c) => c['description']?.toString() ?? '')
            .where((d) => d.isNotEmpty)
            .take(10),
      );
    }
  }
  final library = data['description']?.toString();
  return {
    'exception': summary ?? library ?? 'Unknown error',
    'library': ?library,
    if (widget != null && widget.isNotEmpty) 'widget': widget,
    if (stack.isNotEmpty) 'stackTrace': stack.join('\n'),
    'timestamp': timestamp.toIso8601String(),
  };
}

String? _location(Object? creationLocation) {
  if (creationLocation is! Map) return null;
  final file = creationLocation['file']?.toString();
  if (file == null) return null;
  return '${_shortPath(file)}:${creationLocation['line']}';
}

/// `file:///Users/me/app/lib/ui/tile.dart` -> `lib/ui/tile.dart`.
String _shortPath(String file) {
  final path = file.startsWith('file://') ? Uri.parse(file).path : file;
  final lib = path.lastIndexOf('/lib/');
  return lib >= 0 ? path.substring(lib + 1) : path;
}

String _shortenFileUris(String text) => text.replaceAllMapped(
  RegExp(r'file://\S+'),
  (m) => _shortPath(m.group(0)!),
);

/// `get_app_summary` text for an app without the SDK.
String zeroCodeSummary(Map<String, dynamic> data) {
  // Distinct items in order, repeats counted: a list of 40 rows with the
  // same label must not push everything else out.
  String quoted(Iterable<Object?> items, int max) {
    final counts = <String, int>{};
    for (final item in items) {
      counts['$item'] = (counts['$item'] ?? 0) + 1;
    }
    final shown = counts.entries
        .take(max)
        .map((e) => '"${e.key}"${e.value > 1 ? ' (x${e.value})' : ''}')
        .join(', ');
    return counts.length > max ? '$shown … (+${counts.length - max})' : shown;
  }

  final texts = (data['texts'] as List?) ?? const [];
  final keys = (data['keys'] as List?) ?? const [];
  final errors = ((data['errors'] as List?) ?? const []).whereType<Map>();
  final out = StringBuffer()
    ..writeln(
      '• Mode: zero-code — flutterpilot_sdk is not in this app, so '
      'FlutterPilot can inspect it (tree, screenshots, errors, logs, hot '
      'reload, memory, HTTP) but not drive it: no taps, text entry, '
      'navigation, assertions or route info. Run "flutterpilot init" and '
      'restart the app to enable them.',
    )
    ..writeln('• Flutter: ${data['flutterVersion']}')
    ..writeln('• Heap: ${data['heapUsageMb']} MB');
  final counts = <String, int>{};
  for (final e in errors) {
    final widget = e['widget'] != null ? ' — ${e['widget']}' : '';
    final line = '${e['exception']}$widget';
    counts[line] = (counts[line] ?? 0) + 1;
  }
  if (counts.isEmpty) {
    out.writeln('• Errors: none');
  } else {
    out.writeln('• Errors (${counts.length}), details in get_errors:');
    for (final MapEntry(key: line, value: n) in counts.entries.take(3)) {
      out.writeln('  - $line${n > 1 ? ' (x$n)' : ''}');
    }
  }
  out.writeln(
    '• Text in the widget tree (${texts.length}): ${quoted(texts, 25)}',
  );
  if (keys.isNotEmpty) out.writeln('• Keys: ${quoted(keys, 25)}');
  return out.toString().trimRight();
}

/// The inspector screenshots a widget's subtree bounds, which include
/// content overflowing the window and routes it does not paint (a covered
/// route that a Cupertino transition parked at -1/3 width). Crops the base64
/// PNG [png] to the window ([width] x [height] logical pixels at
/// [pixelRatio]). Areas outside the window are transparent unless something
/// overflows into them, so the window is the most opaque region.
String cropToScreen(
  String png,
  double width,
  double height,
  double pixelRatio,
) {
  final w = (width * pixelRatio).round();
  final h = (height * pixelRatio).round();
  final bytes = base64Decode(png);
  final decoder = img.PngDecoder();
  final info = decoder.startDecode(bytes);
  if (info == null || (info.width <= w + 1 && info.height <= h + 1)) {
    return png;
  }
  final image = decoder.decode(bytes);
  if (image == null) return png;
  final columns = List.filled(image.width, 0.0);
  final rows = List.filled(image.height, 0.0);
  // Weighted by alpha: faint shadows at a route's edge must not outweigh the
  // opaque window.
  for (final pixel in image) {
    final alpha = pixel.aNormalized;
    if (alpha > 0) {
      columns[pixel.x] += alpha;
      rows[pixel.y] += alpha;
    }
  }
  final cropW = w.clamp(1, image.width);
  final cropH = h.clamp(1, image.height);
  final cropped = img.copyCrop(
    image,
    x: _densestWindow(columns, cropW),
    y: _densestWindow(rows, cropH),
    width: cropW,
    height: cropH,
  );
  return base64Encode(img.encodePng(cropped));
}

/// Start of the [size]-long window of [counts] with the largest sum.
int _densestWindow(List<double> counts, int size) {
  var sum = 0.0;
  for (var i = 0; i < size; i++) {
    sum += counts[i];
  }
  var best = sum;
  var bestStart = 0;
  for (var start = 1; start + size <= counts.length; start++) {
    sum += counts[start + size - 1] - counts[start - 1];
    if (sum > best) {
      best = sum;
      bestStart = start;
    }
  }
  return bestStart;
}
