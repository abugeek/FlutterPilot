import 'dart:io';

import 'package:fp_server/fp_server.dart';
import 'package:fp_server/src/fleet_compare.dart';
import 'package:fp_server/src/structured_results.dart';
import 'package:fp_server/src/verification.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The machine-readable twin of the four verdict tools' text (task 06): what a
/// program reads instead of parsing prose. The text these sit next to is
/// pinned by the tools' own tests and by the frozen snapshots below.
void main() {
  group('assert_widget', () {
    test('a text check that passed says what it saw', () {
      expect(
        assertWidgetVerdict(
          check: 'text',
          expected: 'Welcome',
          passed: true,
          found: 1,
        ),
        {'passed': true, 'check': 'text', 'expected': 'Welcome', 'found': 1},
      );
    });

    test('a count check reports the count the app gave', () {
      expect(
        assertWidgetVerdict(
          check: 'count',
          expected: '3 ListTile',
          passed: true,
          found: 3,
        ),
        {
          'passed': true,
          'check': 'count',
          'expected': '3 ListTile',
          'found': 3,
        },
      );
    });

    test('a failed check carries the message, not a count read back', () {
      // The extension answers a failed assertion with its message; the actual
      // count in it is not parsed back out.
      expect(
        assertWidgetVerdict(
          check: 'count',
          expected: '3 ListTile',
          passed: false,
          reason: 'ASSERTION FAILED: expected 3 "ListTile" widgets but found 2',
        ),
        {
          'passed': false,
          'check': 'count',
          'expected': '3 ListTile',
          'reason':
              'ASSERTION FAILED: expected 3 "ListTile" widgets but found 2',
        },
      );
    });

    test('a call with nothing to check is a verdict too', () {
      expect(
        assertWidgetVerdict(
          check: 'none',
          passed: false,
          reason:
              'Say what to check: text, key (optionally with enabled), '
              'or type with count.',
        ),
        {
          'passed': false,
          'check': 'none',
          'reason':
              'Say what to check: text, key (optionally with enabled), '
              'or type with count.',
        },
      );
    });
  });

  group('wait_for', () {
    test('a met wait says how long it took', () {
      expect(
        waitForVerdict(
          condition: 'key',
          met: true,
          waitedMs: 120,
          timeoutMs: 3000,
        ),
        {'met': true, 'waitedMs': 120, 'timedOut': false, 'condition': 'key'},
      );
    });

    test('a wait that used its whole deadline timed out', () {
      expect(
        waitForVerdict(
          condition: 'route',
          met: false,
          waitedMs: 5003,
          timeoutMs: 5000,
        ),
        {
          'met': false,
          'waitedMs': 5003,
          'timedOut': true,
          'condition': 'route',
        },
      );
    });

    test('a wait that never reached the app is not a timeout', () {
      expect(
        waitForVerdict(
          condition: 'key',
          met: false,
          waitedMs: 12,
          timeoutMs: 3000,
        ),
        {'met': false, 'waitedMs': 12, 'timedOut': false, 'condition': 'key'},
      );
    });

    test('a call with no condition is not a timeout either', () {
      expect(
        waitForVerdict(
          condition: 'none',
          met: false,
          waitedMs: 0,
          timeoutMs: 0,
        ),
        {'met': false, 'waitedMs': 0, 'timedOut': false, 'condition': 'none'},
      );
    });

    test("the app's own status decides a timed-out wait when it comes", () {
      // waitForAnimation answers `status: timeout` or `settled`; that flag is
      // the app's word, so it wins over the clock (which also carries the
      // round trip to the app).
      Map<String, dynamic> verdict(bool? timedOut) => waitForVerdict(
        condition: 'animations',
        met: false,
        waitedMs: 3400,
        timeoutMs: 3000,
        timedOut: timedOut,
      );
      expect(verdict(true)['timedOut'], isTrue);
      expect(verdict(false)['timedOut'], isFalse);
      // Without one (every other condition) the clock still decides.
      expect(verdict(null)['timedOut'], isTrue);
    });
  });

  group('verify_feature', () {
    /// One passing criterion and one never checked, with a warning on the
    /// first.
    Verification start() {
      final v = Verification('Login', [
        'A wrong password shows an error',
        'A right password opens Home',
      ]);
      v.current = v.criteria[0];
      v.record(
        'assert_widget',
        {'text': 'Wrong password'},
        '{"status":"passed","text":"Wrong password"}',
        isError: false,
        structured: const {'passed': true, 'check': 'text'},
      );
      v.criteria[0].warnings.add('A RenderFlex overflowed by 3 pixels.');
      return v;
    }

    test('the text is the text verify_feature has always returned', () {
      expect(
        verifyFeatureResult(start(), '/tmp/fp/report.md').text,
        'Login: INCOMPLETE: 1 of 2 criteria passed, 1 not verified.\n'
        '1. ✅ PASS A wrong password shows an error — 1 check(s) passed, no '
        'errors.\n'
        '2. ⚠️ NOT VERIFIED A right password opens Home — Nothing was done or '
        'checked for it.\n'
        'Report: /tmp/fp/report.md (with a screenshot per criterion).',
      );
    });

    test('the structured result lists every criterion and the report', () {
      expect(verifyFeatureResult(start(), '/tmp/fp/report.md').structured, {
        'feature': 'Login',
        'criteria': [
          {
            'index': 1,
            'text': 'A wrong password shows an error',
            'verdict': 'passed',
            'warnings': 1,
          },
          {
            'index': 2,
            'text': 'A right password opens Home',
            'verdict': 'not_verified',
            'warnings': 0,
          },
        ],
        'report': '/tmp/fp/report.md',
      });
    });
  });

  group('run_on_devices', () {
    DeviceRun ran(
      String device,
      List<bool> oks, {
      String? route,
      int errors = 0,
    }) => DeviceRun(device)
      ..steps.addAll([
        for (final ok in oks)
          (
            ok: ok,
            text: ok ? '(2ms)\nDone' : '(3ms)\nFailed',
            structured: null,
          ),
      ])
      ..route = route
      ..errors = errors;

    test(
      'it reports every device, the step that failed and whether they agreed',
      () {
        final runs = [
          ran('macos', [true, true], route: '/home'),
          ran('iphone', [true, false], route: '/login', errors: 2),
        ];
        expect(fleetVerdict(runs, stepsRequested: 2, same: false), {
          'devices': [
            {
              'id': 'macos',
              'passedSteps': 2,
              'totalSteps': 2,
              'route': '/home',
              'errors': 0,
              'reached': true,
            },
            {
              'id': 'iphone',
              'passedSteps': 1,
              'totalSteps': 2,
              'failedStep': 2,
              'route': '/login',
              'errors': 2,
              'reached': true,
            },
          ],
          'same': false,
        });
      },
    );

    test('a device that was never reached reads as 0 of N, no failed step', () {
      final unreachable = DeviceRun('android')..unreachable = 'no device';
      expect(
        fleetVerdict(
          [unreachable],
          stepsRequested: 2,
          same: false,
          status: 'partial',
        ),
        {
          'devices': [
            {
              'id': 'android',
              'passedSteps': 0,
              'totalSteps': 2,
              'errors': 0,
              'reached': false,
            },
          ],
          'same': false,
          'status': 'partial',
        },
      );
    });

    test('devices that agree say so', () {
      final runs = [
        ran('macos', [true]),
        ran('iphone', [true]),
      ];
      expect(fleetVerdict(runs, stepsRequested: 1, same: true)['same'], isTrue);
    });
  });

  group('the text is unmoved', () {
    test('a failure gist reads the step\'s structured reason', () {
      // The step's text does not contain the message: it comes from the
      // structured result (fleet_compare reads it there now).
      final run = DeviceRun('iphone')
        ..steps.add((
          ok: false,
          text: '(3ms)\n(no message in the text)',
          structured: const {
            'passed': false,
            'reason': 'Widget "Welcome" not found',
          },
        ))
        ..route = '/login';
      final text = describeFleetRun(
        [(tool: 'assert_widget', arguments: const <String, dynamic>{})],
        [run],
      );
      expect(text, contains('❌ iphone: Widget "Welcome" not found'));
    });

    test('and the same reason that is also in the text reads the same', () {
      final withStructured = DeviceRun('iphone')
        ..steps.add((
          ok: false,
          text: '(3ms)\n[extensionError] Widget "Welcome" not found\nHINT: …',
          structured: const {
            'passed': false,
            'reason': 'Widget "Welcome" not found',
          },
        ));
      final withoutStructured = DeviceRun('iphone')
        ..steps.add((
          ok: false,
          text: '(3ms)\n[extensionError] Widget "Welcome" not found\nHINT: …',
          structured: null,
        ));
      final steps = [
        (tool: 'assert_widget', arguments: const <String, dynamic>{}),
      ];
      expect(
        describeFleetRun(steps, [withStructured]),
        describeFleetRun(steps, [withoutStructured]),
      );
    });
  });

  group('rebuilding a result', () {
    test('keepingStructured keeps the structured content', () {
      final original = CallToolResult(
        content: [TextContent(text: '{"passed":false}')],
        isError: true,
        structuredContent: const {'passed': false, 'check': 'key'},
      );
      final rebuilt = keepingStructured(
        original,
        isError: true,
        content: [
          ...original.content,
          TextContent(text: 'DEVICE: locked. Unlock it.'),
        ],
      );
      expect(rebuilt.structuredContent, {'passed': false, 'check': 'key'});
      expect(rebuilt.isError, isTrue);
      expect(rebuilt.content.length, 2);
    });

    test(
      'keepingStructured keeps a structured value that is not an object',
      () {
        final array = CallToolResult.fromStructuredArray([1, 2, 3]);
        final kept = keepingStructured(array, content: array.content);
        expect(kept.structuredContentJson!.toJson(), [1, 2, 3]);
      },
    );

    test('withVerdict attaches a verdict without touching the text', () {
      final failed = CallToolResult(
        content: [TextContent(text: '[extensionError] ASSERTION FAILED')],
        isError: true,
      );
      final result = withVerdict(
        failed,
        assertWidgetVerdict(check: 'key', expected: 'Log in', passed: false),
      );
      expect(result.isError, isTrue);
      expect(
        (result.content.single as TextContent).text,
        '[extensionError] ASSERTION FAILED',
      );
      expect(result.structuredContent, {
        'passed': false,
        'check': 'key',
        'expected': 'Log in',
      });
    });
  });

  test(
    'a reason that names a secret is masked like the rest of the app data',
    () {
      expect(
        assertWidgetVerdict(
          check: 'key',
          passed: false,
          reason: 'Timed out checking token=abc123',
        )['reason'],
        'Timed out checking token=<redacted>',
      );
    },
  );

  test('every shape is a registered tool and is in the generated docs', () {
    final repoRoot = p.normalize(p.join(Directory.current.path, '..', '..'));
    final tools = FlutterPilotServer(
      vmServiceUri: 'ws://localhost:8888',
    ).registeredToolNames.toSet();
    final doc = File(p.join(repoRoot, 'TOOLS.generated.md')).readAsStringSync();
    for (final entry in structuredShapes.entries) {
      expect(tools, contains(entry.key));
      expect(
        doc,
        contains(entry.value),
        reason: 'run dart run tool/generate_tools_doc.dart',
      );
    }
  });

  test('the four verdict tools build their structured result', () {
    // A drift guard: the shapes above are only reachable if each tool's
    // callback actually builds one.
    const builders = {
      'testing_tools.dart': 'assertWidgetVerdict(',
      'ui_automation_tools.dart': 'waitForVerdict(',
      'verification_tools.dart': 'verifyFeatureResult(',
      'app_inspection_tools.dart': 'fleetVerdict(',
    };
    for (final entry in builders.entries) {
      final source = File(
        p.join('lib', 'src', 'tools', entry.key),
      ).readAsStringSync();
      expect(source, contains(entry.value), reason: entry.key);
    }
  });

  test("wait_for takes the animation pass's timed-out flag from the app", () {
    // The only wait whose answer says whether it ran out its deadline: its
    // callback is not reachable without a live app, so this reads the wiring.
    final source = File(
      p.join('lib', 'src', 'tools', 'ui_automation_tools.dart'),
    ).readAsStringSync();
    expect(source, contains("timedOut: res.data?['status'] == 'timeout'"));
  });

  group('get_errors', () {
    test('a clean app is an empty list', () {
      expect(errorsVerdict(since: const [], before: const []), {
        'hasErrors': false,
        'count': 0,
        'errors': <Map<String, dynamic>>[],
      });
    });

    test('an overflow and an exception are told apart, with locations', () {
      final verdict = errorsVerdict(
        since: [
          {
            'exception': 'A RenderFlex overflowed by 12 pixels on the right.',
            'stackTrace':
                '#0 Foo (package:my_app/foo.dart:42:7)\n'
                '#1 Bar (package:flutter/src/widgets/framework.dart:1:1)',
          },
          {'exception': 'Bad state: no element'},
        ],
        before: const [],
      );
      expect(verdict['hasErrors'], isTrue);
      expect(verdict['count'], 2);
      expect(verdict['errors'], [
        {
          'kind': 'overflow',
          'message': 'A RenderFlex overflowed by 12 pixels on the right.',
          'location': 'package:my_app/foo.dart:42:7',
          'beforeReload': false,
        },
        {
          'kind': 'exception',
          'message': 'Bad state: no element',
          'beforeReload': false,
        },
      ]);
    });

    test('an error from before the last reload is marked', () {
      final verdict = errorsVerdict(
        since: const [],
        before: [
          {'exception': 'old', 'timestamp': '2026-01-01T00:00:00.000'},
        ],
      );
      expect(verdict['hasErrors'], isTrue);
      expect(verdict['count'], 1);
      expect(verdict['errors'], [
        {'kind': 'exception', 'message': 'old', 'beforeReload': true},
      ]);
    });
  });

  group('get_app_summary', () {
    test('a connected app reports its facts', () {
      expect(
        appSummaryVerdict(
          connected: true,
          device: 'iphone',
          platform: 'ios',
          route: '/home',
          errorCount: 2,
          buildMode: 'debug',
        ),
        {
          'connected': true,
          'device': 'iphone',
          'platform': 'ios',
          'route': '/home',
          'errorCount': 2,
          'buildMode': 'debug',
        },
      );
    });

    test('nothing connected is connected:false, nothing else', () {
      expect(appSummaryVerdict(connected: false), {
        'connected': false,
        'errorCount': 0,
      });
    });
  });

  group('execute_action_chain', () {
    test('a chain that ran every step says so', () {
      expect(
        actionChainVerdict(passed: true, completedSteps: 3, totalSteps: 3),
        {'passed': true, 'completedSteps': 3, 'totalSteps': 3},
      );
    });

    test('a chain that stopped at step 2 says where', () {
      expect(
        actionChainVerdict(
          passed: false,
          completedSteps: 1,
          totalSteps: 3,
          failedStep: 2,
          failureReason: 'Widget "Save" not found',
        ),
        {
          'passed': false,
          'completedSteps': 1,
          'totalSteps': 3,
          'failedStep': 2,
          'failureReason': 'Widget "Save" not found',
        },
      );
    });

    test('a rejected step fails before anything runs', () {
      expect(
        actionChainVerdict(
          passed: false,
          completedSteps: 0,
          totalSteps: 1,
          failedStep: 1,
          failureReason: 'Step 1: "no_such_tool" can\'t run in a chain.',
        ),
        {
          'passed': false,
          'completedSteps': 0,
          'totalSteps': 1,
          'failedStep': 1,
          'failureReason': 'Step 1: "no_such_tool" can\'t run in a chain.',
        },
      );
    });
  });

  group('fill_form', () {
    test('a form that filled every field', () {
      expect(fillFormVerdict(submitted: true, filledCount: 2, totalFields: 2), {
        'submitted': true,
        'filledCount': 2,
        'totalFields': 2,
      });
    });

    test('a partial fill names the first field that did not take', () {
      expect(
        fillFormVerdict(
          submitted: false,
          filledCount: 1,
          totalFields: 3,
          failedField: 'TextField["Email"]',
        ),
        {
          'submitted': false,
          'filledCount': 1,
          'totalFields': 3,
          'failedField': 'TextField["Email"]',
        },
      );
    });

    test('a form nobody filled has no failure point', () {
      expect(
        fillFormVerdict(submitted: false, filledCount: 0, totalFields: 0),
        {'submitted': false, 'filledCount': 0, 'totalFields': 0},
      );
    });
  });

  test('the four action/diagnostic tools build their structured result', () {
    // A drift guard: the shapes above are only reachable if each tool's
    // callback actually builds one.
    const builders = {
      'app_inspection_tools.dart': ['errorsVerdict('],
      'screenshot_tools.dart': ['appSummaryVerdict(', 'keepingStructured('],
      'ui_automation_tools.dart': ['actionChainVerdict(', 'fillFormVerdict('],
    };
    for (final entry in builders.entries) {
      final source = File(
        p.join('lib', 'src', 'tools', entry.key),
      ).readAsStringSync();
      for (final snippet in entry.value) {
        expect(source, contains(snippet), reason: '${entry.key}: $snippet');
      }
    }
  });

  test('fill_form reads the fields the app could not fill', () {
    // The extension reports the selectors it did not fill; the tool turns the
    // first into `failedField`, so that field is not always null.
    final server = File(
      p.join('lib', 'src', 'tools', 'ui_automation_tools.dart'),
    ).readAsStringSync();
    expect(server, contains("res.data?['failedFields']"));
    final sdk = File(
      p.join(
        Directory.current.parent.parent.path,
        'packages',
        'fp_sdk',
        'lib',
        'src',
        'extensions',
        'widget_extensions.dart',
      ),
    ).readAsStringSync();
    expect(sdk, contains("'failedFields': failedFields"));
  });

  // -------------------------------------------------------------------------
  // Task 07: executable contracts, every variant, and the pilot families.
  // -------------------------------------------------------------------------

  group('executable contracts', () {
    test('every documented shape has a contract and vice versa', () {
      expect(structuredShapes.keys.toSet(), structuredContracts.keys.toSet());
      for (final entry in structuredContracts.entries) {
        expect(
          structuredShapes[entry.key],
          contains(entry.value.describe()),
          reason: '${entry.key}: the doc is rendered from its contract',
        );
      }
    });

    test('a representative payload for every family has no problems', () {
      for (final entry in validStructuredFixtures.entries) {
        expect(
          structuredProblems(entry.key, entry.value),
          isEmpty,
          reason: entry.key,
        );
      }
    });

    test('missing, mistyped, unknown and out-of-enum fields are caught', () {
      expect(structuredProblems('assert_widget', {'check': 'text'}), [
        r'assert_widget.passed: missing',
      ]);
      expect(
        structuredProblems('get_errors', {
          'hasErrors': false,
          'count': '0',
          'errors': <Object?>[],
        }),
        contains(r'get_errors.count: expected an int, got String'),
      );
      expect(
        structuredProblems('wait_for', {
          'met': true,
          'waitedMs': 1,
          'timedOut': false,
          'condition': 'nope',
        }),
        contains(
          r'wait_for.condition: "nope" is not one of '
          'key, route, state, frames, animations, none',
        ),
      );
      expect(
        structuredProblems('assert_widget', {
          'passed': true,
          'check': 'key',
          'extra': 1,
        }),
        contains('assert_widget.extra: unexpected field'),
      );
      expect(
        structuredProblems('navigate_to', {
          'requested': '/a',
          'waitRequired': false,
          'completed': true,
          'uncertain': 'no',
        }),
        contains(r'navigate_to.uncertain: expected a bool, got String'),
      );
    });

    test('a nested element is checked at its path', () {
      expect(
        structuredProblems('get_errors', {
          'hasErrors': true,
          'count': 1,
          'errors': [
            {'kind': 'boom', 'message': 'x', 'beforeReload': false},
          ],
        }),
        contains(
          r'get_errors.errors[0].kind: "boom" is not one of '
          'exception, overflow',
        ),
      );
      expect(
        structuredProblems('run_on_devices', {
          'devices': [
            {'id': 'a', 'passedSteps': 0, 'totalSteps': 1},
          ],
          'same': false,
        }),
        contains('run_on_devices.devices[0].errors: missing'),
      );
    });

    test('an unknown family is named, not silently accepted', () {
      expect(structuredProblems('nope', const {}), ['nope: no contract']);
    });

    test('every builder\'s own output matches its contract', () {
      final outputs = <String, Map<String, dynamic>>{
        'assert_widget': assertWidgetVerdict(
          check: 'text',
          expected: 'Welcome',
          passed: false,
          reason: 'not found',
        ),
        'wait_for': waitForVerdict(
          condition: 'key',
          met: false,
          waitedMs: 3010,
          timeoutMs: 3000,
        ),
        'verify_feature': verifyFeatureResult(
          Verification('Login', ['A']),
          '/r.md',
        ).structured,
        'run_on_devices': fleetRefusalVerdict('no'),
        'get_errors': errorsVerdict(since: const [], before: const []),
        'get_app_summary': appSummaryVerdict(connected: false),
        'execute_action_chain': actionChainVerdict(
          passed: true,
          completedSteps: 1,
          totalSteps: 1,
        ),
        'fill_form': fillFormVerdict(
          submitted: true,
          filledCount: 1,
          totalFields: 1,
        ),
        'audit_screen_health': auditVerdict(
          requested: 0,
          visited: 0,
          audited: 1,
          failed: 0,
          skipped: 0,
          findings: const {},
          restored: true,
          incomplete: false,
          loading: false,
        ),
        'navigate_to': navigationVerdict(
          requested: '/home',
          current: '/home',
          waitRequired: true,
          waitStatus: 'found',
          completed: true,
        ),
      };
      for (final entry in outputs.entries) {
        expect(
          structuredProblems(entry.key, entry.value),
          isEmpty,
          reason: entry.key,
        );
      }
    });
  });

  group('variants: a false predicate is not a could-not-evaluate', () {
    test('wait_for: a timeout is evaluated, an unanswered wait is not', () {
      final timedOut = waitForVerdict(
        condition: 'route',
        met: false,
        waitedMs: 5003,
        timeoutMs: 5000,
      );
      expect(timedOut['timedOut'], isTrue);
      expect(timedOut['status'], isNull);
      expect(structuredProblems('wait_for', timedOut), isEmpty);

      final unavailable = waitForVerdict(
        condition: 'route',
        met: false,
        waitedMs: 4,
        timeoutMs: 5000,
        status: 'unavailable',
      );
      expect(unavailable['status'], 'unavailable');
      expect(structuredProblems('wait_for', unavailable), isEmpty);

      final refused = waitForVerdict(
        condition: 'none',
        met: false,
        waitedMs: 0,
        timeoutMs: 0,
        status: 'refused',
      );
      expect(refused['status'], 'refused');
      expect(structuredProblems('wait_for', refused), isEmpty);
    });

    test('get_errors: a clean app is ok; an unreadable one is unavailable', () {
      expect(
        errorsVerdict(since: const [], before: const [])['status'],
        isNull,
      );
      final unavailable = errorsVerdict(
        since: const [],
        before: const [],
        status: 'unavailable',
        reason: 'no app',
      );
      expect(unavailable['status'], 'unavailable');
      expect(unavailable['hasErrors'], isFalse);
      expect(unavailable['reason'], 'no app');
      expect(structuredProblems('get_errors', unavailable), isEmpty);
    });

    test('run_on_devices: a refusal is distinct from a partial sweep', () {
      final refused = fleetRefusalVerdict('steps[0].arguments: bad');
      expect(refused['status'], 'refused');
      expect(refused['devices'], isEmpty);
      expect(structuredProblems('run_on_devices', refused), isEmpty);

      final unreachable = DeviceRun('android')..unreachable = 'no device';
      final partial = fleetVerdict(
        [unreachable],
        stepsRequested: 1,
        same: false,
        status: 'partial',
      );
      expect(partial['status'], 'partial');
      expect(
        (partial['devices']! as List).first,
        containsPair('reached', false),
      );
      expect(structuredProblems('run_on_devices', partial), isEmpty);
    });

    test('execute_action_chain: refused and unavailable are named', () {
      for (final status in ['refused', 'unavailable']) {
        final verdict = actionChainVerdict(
          passed: false,
          completedSteps: 0,
          totalSteps: 2,
          status: status,
        );
        expect(verdict['status'], status);
        expect(structuredProblems('execute_action_chain', verdict), isEmpty);
      }
    });

    test('verify_feature: a refusal has an empty criteria list', () {
      final refusal = <String, dynamic>{
        'criteria': <Map<String, dynamic>>[],
        'status': 'refused',
        'reason': 'No verification running: start with feature and criteria.',
      };
      expect(structuredProblems('verify_feature', refusal), isEmpty);
    });

    test('audit_screen_health: one screen, partial sweep, unavailable', () {
      final single = auditVerdict(
        requested: 0,
        visited: 0,
        audited: 1,
        failed: 0,
        skipped: 0,
        findings: const {'overflows': 2},
        restored: true,
        incomplete: false,
        loading: false,
      );
      expect(single['findings'], {
        'overflows': 2,
        'tapTargets': 0,
        'unlabeled': 0,
        'lowContrast': 0,
        'readingOrderJumps': 0,
      });
      expect(structuredProblems('audit_screen_health', single), isEmpty);

      final partial = auditVerdict(
        requested: 41,
        visited: 38,
        audited: 37,
        failed: 3,
        skipped: 1,
        findings: const {},
        restored: false,
        incomplete: true,
        loading: true,
        status: 'partial',
      );
      expect(partial['status'], 'partial');
      expect(structuredProblems('audit_screen_health', partial), isEmpty);

      final unavailable = auditVerdict(
        requested: 0,
        visited: 0,
        audited: 0,
        failed: 1,
        skipped: 0,
        findings: const {},
        restored: true,
        incomplete: true,
        loading: false,
        status: 'unavailable',
        reason: 'no app',
      );
      expect(structuredProblems('audit_screen_health', unavailable), isEmpty);
    });

    test('navigate_to: confirmed, unconfirmed and unavailable', () {
      final confirmed = navigationVerdict(
        requested: '/home',
        current: '/home',
        waitRequired: false,
        completed: true,
      );
      expect(confirmed['uncertain'], isFalse);
      expect(structuredProblems('navigate_to', confirmed), isEmpty);

      final unconfirmed = navigationVerdict(
        requested: '/home',
        waitRequired: true,
        waitStatus: 'missing',
        completed: false,
        uncertain: true,
      );
      expect(unconfirmed['current'], isNull);
      expect(structuredProblems('navigate_to', unconfirmed), isEmpty);

      final unavailable = navigationVerdict(
        requested: '/home',
        waitRequired: false,
        completed: false,
        uncertain: true,
        status: 'unavailable',
      );
      expect(structuredProblems('navigate_to', unavailable), isEmpty);
    });
  });

  group('redaction', () {
    test(
      'routes, reasons and expected values are masked in structured data',
      () {
        expect(
          navigationVerdict(
            requested: '/login?token=abc123',
            waitRequired: false,
            completed: true,
          )['requested'],
          '/login?token=<redacted>',
        );
        expect(
          navigationVerdict(
            requested: '/x',
            current: '/x?api_key=abc123',
            waitRequired: false,
            completed: true,
          )['current'],
          '/x?api_key=<redacted>',
        );
        final run = DeviceRun('iphone')..route = '/home?token=abc123';
        expect(
          (fleetVerdict([run], stepsRequested: 0, same: true)['devices']!
                  as List)
              .first,
          containsPair('route', '/home?token=<redacted>'),
        );
        expect(
          fleetRefusalVerdict('bad token=abc123')['reason'],
          'bad token=<redacted>',
        );
        expect(
          errorsVerdict(
            since: const [],
            before: const [],
            status: 'unavailable',
            reason: 'token=abc123',
          )['reason'],
          'token=<redacted>',
        );
        expect(
          auditVerdict(
            requested: 0,
            visited: 0,
            audited: 0,
            failed: 1,
            skipped: 0,
            findings: const {},
            restored: true,
            incomplete: true,
            loading: false,
            reason: 'token=abc123',
          )['reason'],
          'token=<redacted>',
        );
      },
    );
  });

  group('verdict paths through the real callbacks (no app)', () {
    FlutterPilotServer server() =>
        FlutterPilotServer(vmServiceUri: 'ws://localhost:8888');

    /// Every documented verdict path that returns without a running app carries
    /// structured content whose contract holds: an empty answer must not read
    /// as a clean pass.
    test('run_on_devices refusal carries status refused', () async {
      final result = await server().callToolForTest('run_on_devices', {
        'steps': [
          {'tool': 'enter_text', 'arguments': <String, dynamic>{}},
        ],
      });
      expect(result.isError, isTrue);
      expect(result.structuredContent?['status'], 'refused');
      expect(result.structuredContent?['devices'], isEmpty);
      expect(
        structuredProblems('run_on_devices', result.structuredContent!),
        isEmpty,
      );
    });

    test('run_on_devices with too few devices is a refusal too', () async {
      final result = await server().callToolForTest('run_on_devices', {
        'steps': [
          {
            'tool': 'tap_widget',
            'arguments': {'key': 'A'},
          },
        ],
      });
      expect(result.isError, isTrue);
      expect(result.structuredContent?['status'], 'refused');
    });

    test('get_errors with no app says unavailable, not a clean app', () async {
      final result = await server().callToolForTest('get_errors', const {});
      expect(result.isError, isTrue);
      expect(result.structuredContent?['status'], 'unavailable');
      expect(
        structuredProblems('get_errors', result.structuredContent!),
        isEmpty,
      );
    });

    test('wait_for with no app is unavailable, not a timeout', () async {
      final result = await server().callToolForTest('wait_for', {'key': 'X'});
      expect(result.isError, isTrue);
      expect(result.structuredContent?['status'], 'unavailable');
      expect(result.structuredContent?['timedOut'], isFalse);
      expect(
        structuredProblems('wait_for', result.structuredContent!),
        isEmpty,
      );
    });

    test('wait_for with nothing to wait for is a refusal', () async {
      final result = await server().callToolForTest('wait_for', const {});
      expect(result.isError, isTrue);
      expect(result.structuredContent?['status'], 'refused');
    });

    test('execute_action_chain refusal names status refused', () async {
      final result = await server().callToolForTest('execute_action_chain', {
        'steps': [
          {'tool': 'enter_text', 'arguments': <String, dynamic>{}},
        ],
      });
      expect(result.isError, isTrue);
      expect(result.structuredContent?['status'], 'refused');
      expect(
        structuredProblems('execute_action_chain', result.structuredContent!),
        isEmpty,
      );
    });

    test(
      'fill_form with no app is unavailable, not a fill of nothing',
      () async {
        final result = await server().callToolForTest('fill_form', {
          'fields': {'TextField["Email"]': 'a@b.dev'},
        });
        expect(result.isError, isTrue);
        expect(result.structuredContent?['status'], 'unavailable');
        expect(
          structuredProblems('fill_form', result.structuredContent!),
          isEmpty,
        );
      },
    );

    test(
      'audit_screen_health with no app is unavailable and incomplete',
      () async {
        final result = await server().callToolForTest(
          'audit_screen_health',
          const {},
        );
        expect(result.isError, isTrue);
        expect(result.structuredContent?['status'], 'unavailable');
        expect(result.structuredContent?['incomplete'], isTrue);
        expect(
          structuredProblems('audit_screen_health', result.structuredContent!),
          isEmpty,
        );
      },
    );

    test('navigate_to with no app is unavailable and uncertain', () async {
      final result = await server().callToolForTest('navigate_to', {
        'route': '/home',
      });
      expect(result.isError, isTrue);
      expect(result.structuredContent?['status'], 'unavailable');
      expect(result.structuredContent?['uncertain'], isTrue);
      expect(
        structuredProblems('navigate_to', result.structuredContent!),
        isEmpty,
      );
    });

    test('verify_feature with nothing running is a refusal verdict', () async {
      final result = await server().callToolForTest('verify_feature', const {});
      expect(result.isError, isTrue);
      expect(result.structuredContent?['status'], 'refused');
      expect(result.structuredContent?['criteria'], isEmpty);
      expect(
        structuredProblems('verify_feature', result.structuredContent!),
        isEmpty,
      );
    });
  });

  group('wrappers preserve verdicts and metadata', () {
    test('keepingStructured keeps a marker through a rebuilt result', () {
      final original = CallToolResult(
        content: [TextContent(text: 'body')],
        isError: true,
        structuredContent: assertWidgetVerdict(
          check: 'key',
          expected: 'Log in',
          passed: false,
          reason: 'not found',
        ),
      );
      final rebuilt = keepingStructured(
        original,
        isError: true,
        content: [
          ...original.content,
          TextContent(text: 'DEVICE: locked.'),
        ],
      );
      expect(rebuilt.content.length, 2);
      expect(
        structuredProblems('assert_widget', rebuilt.structuredContent!),
        isEmpty,
      );
      expect(rebuilt.structuredContent, original.structuredContent);
    });
  });
}

/// One well-formed payload per structured family, in the shape the builders
/// produce: the contract's positive fixtures (task 07).
final validStructuredFixtures = <String, Map<String, dynamic>>{
  'assert_widget': {
    'passed': true,
    'check': 'text',
    'expected': 'Welcome',
    'found': 1,
  },
  'wait_for': {
    'met': true,
    'waitedMs': 120,
    'timedOut': false,
    'condition': 'key',
    'route': '/home',
  },
  'verify_feature': {
    'feature': 'Login',
    'criteria': [
      {'index': 1, 'text': 'A', 'verdict': 'passed', 'warnings': 0},
      {'index': 2, 'text': 'B', 'verdict': 'not_verified', 'warnings': 1},
    ],
    'report': '/tmp/fp/report.md',
  },
  'run_on_devices': {
    'devices': [
      {
        'id': 'macos',
        'passedSteps': 1,
        'totalSteps': 1,
        'errors': 0,
        'reached': true,
      },
    ],
    'same': true,
  },
  'get_errors': {
    'hasErrors': true,
    'count': 1,
    'errors': [
      {
        'kind': 'overflow',
        'message': 'A RenderFlex overflowed by 3 pixels.',
        'location': 'package:app/foo.dart:1:1',
        'beforeReload': false,
      },
    ],
  },
  'get_app_summary': {
    'connected': true,
    'device': 'iphone',
    'platform': 'ios',
    'route': '/home',
    'errorCount': 0,
    'buildMode': 'debug',
  },
  'execute_action_chain': {
    'passed': false,
    'completedSteps': 1,
    'totalSteps': 3,
    'failedStep': 2,
    'failureReason': 'Widget "Save" not found',
  },
  'fill_form': {
    'submitted': false,
    'filledCount': 1,
    'totalFields': 3,
    'failedField': 'TextField["Email"]',
  },
  'audit_screen_health': {
    'requested': 2,
    'visited': 2,
    'audited': 2,
    'failed': 0,
    'skipped': 0,
    'findings': {
      'overflows': 1,
      'tapTargets': 0,
      'unlabeled': 2,
      'lowContrast': 0,
      'readingOrderJumps': 0,
    },
    'restored': true,
    'incomplete': false,
    'loading': false,
    'status': 'ok',
  },
  'navigate_to': {
    'requested': '/home',
    'current': '/home',
    'waitRequired': true,
    'waitStatus': 'found',
    'completed': true,
    'uncertain': false,
  },
};
