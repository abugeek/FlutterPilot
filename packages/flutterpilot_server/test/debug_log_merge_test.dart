import 'package:flutterpilot_server/src/debug_log_merge.dart';
import 'package:test/test.dart';

Map<String, dynamic> log(
  String timestamp,
  String message, {
  String level = 'info',
  String logger = 'debugPrint',
}) => {
  'timestamp': timestamp,
  'level': level,
  'logger': logger,
  'message': message,
};

void main() {
  group('preConnectionLogs', () {
    test('adds a startup line the server never saw', () {
      // What a fresh connection to a running app looks like: the SDK buffered
      // the line at app start, the server's stdout capture starts later.
      final merged = preConnectionLogs(
        sdkLogs: [
          log('2026-10-14T15:00:00.000Z', 'FlutterPilot initialized 🚀'),
        ],
        serverLogs: [
          log(
            '2026-10-14T15:00:09.000Z',
            'flutter: after connecting',
            logger: 'stdout',
          ),
        ],
      );
      expect(merged, hasLength(1));
      expect(merged.single['message'], 'FlutterPilot initialized 🚀');
    });

    test(
      'drops a line the server already captured, prefix and logger apart',
      () {
        final merged = preConnectionLogs(
          sdkLogs: [
            log('2026-10-14T15:00:08.000Z', 'FlutterPilot initialized 🚀'),
          ],
          serverLogs: [
            log(
              '2026-10-14T15:00:09.000Z',
              'flutter: FlutterPilot initialized 🚀',
              logger: 'stdout',
            ),
          ],
        );
        expect(merged, isEmpty);
      },
    );

    test('keeps the dedupe one line per copy, not per message', () {
      final merged = preConnectionLogs(
        sdkLogs: [
          log('2026-10-14T15:00:00.000Z', 'retrying'),
          log('2026-10-14T15:00:01.000Z', 'retrying'),
        ],
        serverLogs: [
          log('2026-10-14T15:00:09.000Z', 'flutter: later', logger: 'stdout'),
        ],
      );
      expect(merged, hasLength(2));
    });

    test('a line newer than the oldest server line is left out', () {
      // The server's stdout capture started at 15:00:05; an SDK line after it
      // is one the server has (or will have) itself.
      final merged = preConnectionLogs(
        sdkLogs: [
          log('2026-10-14T15:00:04.000Z', 'before'),
          log('2026-10-14T15:00:06.000Z', 'after'),
        ],
        serverLogs: [
          log('2026-10-14T15:00:05.000Z', 'flutter: first', logger: 'stdout'),
        ],
      );
      expect(merged.map((e) => e['message']), ['before']);
    });

    test('without server lines every SDK line counts as pre-connection', () {
      final merged = preConnectionLogs(
        sdkLogs: [
          log('2026-10-14T15:00:00.000Z', 'one'),
          log('2026-10-14T15:00:01.000Z', 'two'),
        ],
        serverLogs: const [],
      );
      expect(merged.map((e) => e['message']), ['one', 'two']);
    });

    test('an empty SDK buffer adds nothing', () {
      expect(
        preConnectionLogs(
          sdkLogs: const [],
          serverLogs: [log('2026-10-14T15:00:05.000Z', 'flutter: x')],
        ),
        isEmpty,
      );
    });

    test('a line with no timestamp is left out rather than guessed at', () {
      final merged = preConnectionLogs(
        sdkLogs: [
          {'level': 'info', 'message': 'no timestamp'},
        ],
        serverLogs: [log('2026-10-14T15:00:05.000Z', 'flutter: x')],
      );
      expect(merged, isEmpty);
    });

    test('the merged entries are copies', () {
      final sdk = log('2026-10-14T15:00:00.000Z', 'startup');
      final merged = preConnectionLogs(sdkLogs: [sdk], serverLogs: const []);
      merged.single['message'] = 'changed';
      expect(sdk['message'], 'startup');
    });
  });

  group('withoutStdoutPrefix', () {
    test('strips the prefix the server sees on stdout', () {
      expect(withoutStdoutPrefix('flutter: hello'), 'hello');
      expect(withoutStdoutPrefix('flutter:hello'), 'flutter:hello');
      expect(withoutStdoutPrefix('  flutter: hello\n'), 'hello');
      expect(withoutStdoutPrefix('hello'), 'hello');
    });
  });
}
