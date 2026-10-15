/// Jank explanation (ROADMAP §5.3): from the VM timeline of a profiled
/// window, each frame's UI time split into build/layout/paint/..., its
/// raster time, and which app widgets rebuilt in it.
library;

/// One sync span on a thread, with its children.
class _Span {
  _Span(this.name, this.start);

  final String name;
  final int start;
  int end = 0;
  final List<_Span> children = [];
  Map<String, dynamic> args = const {};

  int get micros => end - start;
}

/// A frame drawn during the window.
class FrameReport {
  FrameReport(this.number, this.startMicros, this.uiMicros);

  final int? number;
  final int startMicros;

  /// `Animator::BeginFrame`: everything the UI thread did for the frame.
  final int uiMicros;

  /// `GPURasterizer::Draw` for the frame, when found.
  int? rasterMicros;

  /// Phase name (build, layout, paint, ...) -> micros.
  final Map<String, int> phases = {};

  /// Widget type -> (rebuild count, self micros): the builds nested under
  /// BUILD, minus the time of widgets built inside them.
  final Map<String, ({int count, int micros})> rebuilt = {};

  double get uiMs => uiMicros / 1000;
  double? get rasterMs => rasterMicros == null ? null : rasterMicros! / 1000;

  bool overBudget(double budgetMs) =>
      uiMs > budgetMs || (rasterMs ?? 0) > budgetMs;
}

/// Framework phase spans -> the short name shown to the agent.
const _phases = {
  'BUILD': 'build',
  'LAYOUT (root)': 'layout',
  'LAYOUT': 'layout',
  'UPDATING COMPOSITING BITS (root)': 'compositing bits',
  'UPDATING COMPOSITING BITS': 'compositing bits',
  'PAINT (root)': 'paint',
  'PAINT': 'paint',
  'COMPOSITING': 'compositing',
  'SEMANTICS (root)': 'semantics',
  'SEMANTICS': 'semantics',
  'FINALIZE TREE': 'finalize',
  'POST_FRAME': 'post-frame callbacks',
  'Animate': 'animate',
};

/// VM garbage collection spans that can run inside a frame.
bool _isGc(String name) =>
    name.startsWith('Collect') || name == 'Scavenge' || name.contains('GC');

/// Frames in [events] (Chrome trace format from `getVMTimeline`), in order.
List<FrameReport> framesFromTimeline(List<Map<String, dynamic>> events) {
  // Threads by what runs on them: the UI thread begins frames, the raster
  // thread draws them (on macOS and iOS the UI thread is the platform one).
  int? uiTid;
  int? rasterTid;
  for (final e in events) {
    if (e['ph'] != 'B' && e['ph'] != 'X') continue;
    if (e['name'] == 'Animator::BeginFrame') uiTid ??= e['tid'] as int?;
    if (e['name'] == 'GPURasterizer::Draw') rasterTid ??= e['tid'] as int?;
  }
  if (uiTid == null) return const [];

  // Engine spans nest (VsyncProcessCallback > Animator::BeginFrame), so
  // frames are found anywhere in the tree.
  final ui = _named(_spans(events, uiTid), 'Animator::BeginFrame');
  final raster = rasterTid == null
      ? const <_Span>[]
      : _named(_spans(events, rasterTid), 'GPURasterizer::Draw');

  final frames = <FrameReport>[];
  var nextRaster = 0;
  for (final span in ui) {
    final frame = FrameReport(
      span.args['frame_number'] is int
          ? span.args['frame_number'] as int
          : int.tryParse('${span.args['frame_number']}'),
      span.start,
      span.micros,
    );
    // Raster starts once the UI thread hands the layer tree over, which
    // can be just before BeginFrame's span closes.
    while (nextRaster < raster.length &&
        raster[nextRaster].start < span.start) {
      nextRaster++;
    }
    if (nextRaster < raster.length) {
      frame.rasterMicros = raster[nextRaster++].micros;
    }
    for (final child in span.children) {
      final phase = _phases[child.name] ?? (_isGc(child.name) ? 'GC' : null);
      if (phase != null) {
        frame.phases[phase] = (frame.phases[phase] ?? 0) + child.micros;
      }
      if (child.name == 'BUILD') _collectRebuilds(child, frame.rebuilt);
    }
    // A LayoutBuilder builds during layout: its BUILD sits under LAYOUT.
    void nestedBuilds(_Span s) {
      for (final c in s.children) {
        if (c.name == 'BUILD') {
          _collectRebuilds(c, frame.rebuilt);
        } else {
          nestedBuilds(c);
        }
      }
    }

    for (final child in span.children.where((c) => c.name != 'BUILD')) {
      nestedBuilds(child);
    }
    frames.add(frame);
  }
  return frames;
}

/// Widget build spans under a BUILD span, with self time.
void _collectRebuilds(
  _Span build,
  Map<String, ({int count, int micros})> into,
) {
  void visit(_Span s) {
    final nested = s.children.where((c) => !_phases.containsKey(c.name));
    final self = s.micros - nested.fold<int>(0, (sum, c) => sum + c.micros);
    final prior = into[s.name];
    into[s.name] = (
      count: (prior?.count ?? 0) + 1,
      micros: (prior?.micros ?? 0) + (self < 0 ? 0 : self),
    );
    for (final c in nested) {
      visit(c);
    }
  }

  for (final c in build.children) {
    if (_phases.containsKey(c.name) || _isGc(c.name)) continue;
    visit(c);
  }
}

/// Spans called [name] anywhere under [roots] (not inside each other), in
/// start order.
List<_Span> _named(List<_Span> roots, String name) {
  final found = <_Span>[];
  void visit(_Span s) {
    if (s.name == name) {
      found.add(s);
    } else {
      s.children.forEach(visit);
    }
  }

  roots.forEach(visit);
  return found;
}

/// Sync spans (B/E pairs and X events) of thread [tid], nested, top level
/// returned in start order.
List<_Span> _spans(List<Map<String, dynamic>> events, int tid) {
  final own =
      events
          .where(
            (e) =>
                e['tid'] == tid &&
                (e['ph'] == 'B' || e['ph'] == 'E' || e['ph'] == 'X'),
          )
          .toList()
        ..sort((a, b) {
          final t = (a['ts'] as int).compareTo(b['ts'] as int);
          // At equal timestamps close spans before opening new ones.
          if (t != 0) return t;
          return (a['ph'] == 'E' ? 0 : 1).compareTo(b['ph'] == 'E' ? 0 : 1);
        });
  final roots = <_Span>[];
  final stack = <_Span>[];
  void attach(_Span s) =>
      stack.isEmpty ? roots.add(s) : stack.last.children.add(s);
  for (final e in own) {
    final ts = e['ts'] as int;
    switch (e['ph']) {
      case 'B':
        final s = _Span('${e['name']}', ts)
          ..args = (e['args'] as Map?)?.cast<String, dynamic>() ?? const {};
        attach(s);
        stack.add(s);
      case 'E':
        // An E whose B came before the window has no open span: skip it
        // rather than closing an unrelated one.
        final name = e['name'];
        final at = name == null
            ? stack.length - 1
            : stack.lastIndexWhere((s) => s.name == name);
        if (at < 0) continue;
        while (stack.length > at) {
          stack.removeLast().end = ts;
        }
      case 'X':
        final s = _Span('${e['name']}', ts)
          ..end = ts + ((e['dur'] as num?)?.toInt() ?? 0)
          ..args = (e['args'] as Map?)?.cast<String, dynamic>() ?? const {};
        attach(s);
    }
  }
  // Spans still open when the window ended.
  for (final s in stack) {
    if (s.end == 0) s.end = s.start;
  }
  return roots;
}

/// The frames section of profile_action's answer.
String explainFrames(
  List<FrameReport> frames, {
  required double budgetMs,
  int maxJanky = 3,
}) {
  if (frames.isEmpty) {
    return 'Frames: none drawn in the window (nothing on screen changed).';
  }
  String ms(num micros) => (micros / 1000).toStringAsFixed(1);
  String rebuilt(Map<String, ({int count, int micros})> map, {int top = 5}) {
    final list = map.entries.toList()
      ..sort((a, b) => b.value.micros.compareTo(a.value.micros));
    return list
        .take(top)
        .map((e) => '${e.key} ×${e.value.count} ${ms(e.value.micros)} ms')
        .join(', ');
  }

  final janky = frames.where((f) => f.overBudget(budgetMs)).toList();
  final budget = budgetMs.toStringAsFixed(1);
  final buf = StringBuffer();
  if (janky.isEmpty) {
    final slowest = frames.reduce((a, b) => a.uiMicros >= b.uiMicros ? a : b);
    final raster = frames
        .map((f) => f.rasterMicros ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    buf.writeln(
      'Frames: ${frames.length}, none over the $budget ms budget '
      '(slowest ${ms(slowest.uiMicros)} ms UI, ${ms(raster)} ms raster).',
    );
  } else {
    buf.writeln(
      'Frames: ${frames.length}, ${janky.length} over the $budget ms budget'
      '${janky.length > maxJanky ? ' (slowest $maxJanky shown)' : ''}:',
    );
    final shown =
        (janky.toList()..sort((a, b) => b.uiMicros.compareTo(a.uiMicros))).take(
          maxJanky,
        );
    for (final f in shown) {
      final phases =
          (f.phases.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .where((e) => e.value >= 100)
              .map((e) => '${e.key} ${ms(e.value)}')
              .join(' · ');
      buf.writeln(
        '- frame${f.number == null ? '' : ' ${f.number}'}: '
        '${ms(f.uiMicros)} ms UI${phases.isEmpty ? '' : ' ($phases)'}, '
        '${f.rasterMicros == null ? 'raster not seen' : '${ms(f.rasterMicros!)} ms raster'}'
        '${f.uiMs > budgetMs ? '' : ' ← raster thread (painting cost: layers, clips, shadows, images)'}',
      );
      if (f.rebuilt.isNotEmpty) {
        buf.writeln('  rebuilt: ${rebuilt(f.rebuilt)}');
      }
    }
  }
  // Across the window: what rebuilt, even when no frame was late.
  final all = <String, ({int count, int micros})>{};
  for (final f in frames) {
    for (final MapEntry(key: name, value: v) in f.rebuilt.entries) {
      final prior = all[name];
      all[name] = (
        count: (prior?.count ?? 0) + v.count,
        micros: (prior?.micros ?? 0) + v.micros,
      );
    }
  }
  if (all.isNotEmpty) {
    buf.writeln('App widgets rebuilt in the window: ${rebuilt(all, top: 8)}.');
  }
  return buf.toString().trim();
}
