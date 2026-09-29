import 'package:flutterpilot_server/src/frame_timeline.dart';
import 'package:test/test.dart';

const _ui = 259;
const _raster = 45571;

Map<String, dynamic> _b(String name, int ts, {int tid = _ui, Map? args}) => {
  'name': name,
  'ph': 'B',
  'ts': ts,
  'tid': tid,
  'args': args ?? {},
};

Map<String, dynamic> _e(String name, int ts, {int tid = _ui}) => {
  'name': name,
  'ph': 'E',
  'ts': ts,
  'tid': tid,
};

/// A span [start, end) as a B/E pair, children in between.
List<Map<String, dynamic>> _span(
  String name,
  int start,
  int end, {
  int tid = _ui,
  Map? args,
  List<Map<String, dynamic>> children = const [],
}) => [
  _b(name, start, tid: tid, args: args),
  ...children,
  _e(name, end, tid: tid),
];

void main() {
  // Frame 7: 36 ms on the UI thread, 30 ms of it building 3 StoryTiles
  // (each 9 ms, 1 ms of which is its Text), plus a LayoutBuilder that builds
  // during layout. Frame 8: 3 ms. Raster 4.5 ms and 0.9 ms.
  final events = [
    // Closes a span opened before the window: must not close anything else.
    _e('DartIsolate::HandleMessage', -5),
    // As on a real engine: the frame runs inside the vsync callback.
    _b('VsyncProcessCallback', -10),
    ..._span(
      'Animator::BeginFrame',
      0,
      36000,
      args: {'frame_number': 7},
      children: [
        ..._span(
          'BUILD',
          10,
          30010,
          children: [
            for (var i = 0; i < 3; i++)
              ..._span(
                'StoryTile',
                100 + i * 9000,
                9100 + i * 9000,
                children: _span('Text', 200 + i * 9000, 1200 + i * 9000),
              ),
          ],
        ),
        ..._span(
          'LAYOUT (root)',
          30010,
          35000,
          children: _span(
            'LAYOUT',
            30010,
            35000,
            children: _span(
              'BUILD',
              31000,
              33000,
              children: _span('ResultsGrid', 31000, 33000),
            ),
          ),
        ),
        ..._span('PAINT (root)', 35000, 35800),
      ],
    ),
    _e('VsyncProcessCallback', 36010),
    ..._span('GPURasterizer::Draw', 35900, 40400, tid: _raster),
    ..._span(
      'Animator::BeginFrame',
      50000,
      53000,
      args: {'frame_number': 8},
      children: _span('BUILD', 50010, 50500),
    ),
    ..._span('GPURasterizer::Draw', 52900, 53800, tid: _raster),
    // Other threads and async events are ignored.
    {'name': 'Frame', 'ph': 'b', 'ts': 0, 'tid': _ui, 'id': '1'},
    ..._span('DartIsolate::HandleMessage', 60000, 60100, tid: 3),
  ];

  test('splits each frame into phases, raster and rebuilt widgets', () {
    final frames = framesFromTimeline(events);
    expect(frames, hasLength(2));
    final slow = frames.first;
    expect(slow.number, 7);
    expect(slow.uiMs, 36);
    expect(slow.rasterMs, 4.5);
    expect(slow.phases['build'], 30000);
    expect(slow.phases['layout'], 4990);
    expect(slow.phases['paint'], 800);
    // Self time: a StoryTile minus the Text built inside it.
    expect(slow.rebuilt['StoryTile'], (count: 3, micros: 24000));
    expect(slow.rebuilt['Text'], (count: 3, micros: 3000));
    // Built during layout (LayoutBuilder), still counted.
    expect(slow.rebuilt['ResultsGrid'], (count: 1, micros: 2000));
    expect(slow.overBudget(16.7), isTrue);

    final fast = frames.last;
    expect(fast.rasterMs, closeTo(0.9, 1e-9));
    expect(fast.overBudget(16.7), isFalse);
  });

  test('explains the janky frame and what rebuilt', () {
    final text = explainFrames(framesFromTimeline(events), budgetMs: 16.7);
    expect(text, contains('Frames: 2, 1 over the 16.7 ms budget'));
    expect(text, contains('frame 7: 36.0 ms UI (build 30.0 · layout 5.0'));
    expect(text, contains('4.5 ms raster'));
    expect(text, contains('rebuilt: StoryTile ×3 24.0 ms, Text ×3 3.0 ms'));
    expect(text, isNot(contains('raster thread')));
  });

  test('a frame late only on the raster thread says so', () {
    final text = explainFrames(
      framesFromTimeline([
        ..._span('Animator::BeginFrame', 0, 2000),
        ..._span('GPURasterizer::Draw', 1900, 31900, tid: _raster),
      ]),
      budgetMs: 16.7,
    );
    expect(text, contains('30.0 ms raster ← raster thread'));
  });

  test('no jank: one line with the slowest frame', () {
    final text = explainFrames(
      framesFromTimeline(_span('Animator::BeginFrame', 0, 5000)),
      budgetMs: 16.7,
    );
    expect(text, startsWith('Frames: 1, none over the 16.7 ms budget'));
    expect(explainFrames(const [], budgetMs: 16.7), contains('none drawn'));
  });
}
