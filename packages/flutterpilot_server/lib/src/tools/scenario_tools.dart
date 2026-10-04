part of '../../flutterpilot_server.dart';

/// Named start states (ROADMAP §7): save the app's state to a file in the
/// app, load it back with a hot restart.
mixin _ScenarioToolsMixin
    on _FlutterPilotServerBase, _DevtoolsToolsMixin, _TestGenerationToolsMixin {
  void _registerScenarioTools() {
    _tool(
      'scenario',
      description:
          'Named app states to start from, kept as '
          'flutterpilot/scenarios/<name>.json in the app (check them in, '
          'edit them). save:"name" writes the route, SharedPreferences '
          '(sensitive keys left out), the rows of registered Drift/sqflite '
          'databases and plain Hive boxes, active mocks (HTTP, platform '
          'channel) and simple Riverpod/Bloc values. load:"name" replaces '
          'the stored data, hot-restarts with the mocks in place from the '
          'first call, sets the state and goes to the route (state is set '
          'behind the widgets: a TextField keeps its own text). No '
          'argument lists them. Loading stored data needs '
          '--allow-destructive.',
      inputSchema: ToolInputSchema(
        properties: {
          'save': JsonSchema.string(description: 'Scenario name to write.'),
          'load': JsonSchema.string(description: 'Scenario name to apply.'),
          'description': JsonSchema.string(
            description: 'With save: what the scenario is for.',
          ),
        },
      ),
      callback: (params, extra) async {
        final root = await _scenarioRoot();
        if (root == null) {
          return _scenarioError(
            "No running app, or its folder can't be told from its root "
            'library.',
          );
        }
        final dir = Directory('$root/flutterpilot/scenarios');
        final save = params['save']?.toString();
        final load = params['load']?.toString();
        for (final name in [save, load]) {
          if (name != null && !RegExp(r'^[a-z0-9_-]+$').hasMatch(name)) {
            return _scenarioError(
              'Scenario names are lower_snake_case (letters, digits, _ -).',
            );
          }
        }
        if (save != null) {
          return _saveScenario(
            File('${dir.path}/$save.json'),
            params['description']?.toString(),
          );
        }
        if (load != null) {
          return _loadScenario(dir, load, extra);
        }
        return _listScenarios(dir);
      },
    );
  }

  CallToolResult _scenarioError(String s) =>
      CallToolResult(isError: true, content: [TextContent(text: s)]);

  Future<String?> _scenarioRoot() async {
    final vm = (await _deviceContextForParameters(const {}))?.service;
    if (vm == null) return null;
    final isolateId = await _uiIsolateId(vm, null);
    if (isolateId == null) return null;
    return (await _appEntrypoint(vm, isolateId))?.root;
  }

  CallToolResult _listScenarios(Directory dir) {
    final files = dir.existsSync()
        ? (dir.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.json'),
          )).toList()
        : <File>[];
    if (files.isEmpty) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'No scenarios in ${dir.path} yet. Bring the app into a state, '
                'then scenario(save: "name").',
          ),
        ],
      );
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    final lines = [
      for (final f in files)
        () {
          final name = f.uri.pathSegments.last.replaceAll('.json', '');
          try {
            final s = Scenario.fromJson(
              jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
            );
            return '- $name: ${s.description ?? s.summary}';
          } catch (e) {
            return '- $name: unreadable ($e)';
          }
        }(),
    ];
    return CallToolResult(
      content: [TextContent(text: 'Scenarios:\n${lines.join('\n')}')],
    );
  }

  Future<CallToolResult> _saveScenario(File file, String? description) async {
    final notes = <String>[];

    String? route;
    final router = await _callExtensionRaw(
      'ext.flutterpilot.getGoRouterState',
      {},
    );
    if (!router.isError) {
      route = router.data?['currentLocation']?.toString();
    }
    if (route == null) {
      final nav = await _callExtensionRaw(
        'ext.flutterpilot.getNavigationStack',
        {},
      );
      final stack = (nav.data?['stack'] as List?)?.whereType<String>();
      route = stack == null || stack.isEmpty ? null : stack.last;
    }

    Map<String, Object?>? prefs;
    final p = await _callExtensionRaw('ext.flutterpilot.getSharedPreferences', {
      'truncateLength': '100000000',
    });
    if (!p.isError) {
      prefs = {};
      final sensitive = <String>[];
      for (final MapEntry(:key, :value)
          in ((p.data?['prefs'] as Map?) ?? const {}).entries) {
        if (value is String && value.startsWith('[redacted')) {
          sensitive.add('$key');
        } else if (prefForSetter(value) != null) {
          prefs['$key'] = value;
        }
      }
      if (sensitive.isNotEmpty) {
        notes.add(
          'Left out sensitive preferences (loading keeps none of them): '
          '${sensitive.join(', ')}.',
        );
      }
    }

    final mocksRes = await _callExtensionRaw(
      'ext.flutterpilot.getHttpMocks',
      {},
    );
    final mocks = [
      for (final m in (mocksRes.data?['mocks'] as List? ?? const []))
        (m as Map).cast<String, Object?>(),
    ];

    final channels = await _callExtensionRaw(
      'ext.flutterpilot.platformChannel',
      {},
    );
    final channelMocks = [
      for (final m in (channels.data?['mocks'] as List? ?? const []))
        (m as Map).cast<String, Object?>(),
    ];

    final state = <String, Map<String, Object?>>{};
    for (final (type, ext, valueKey) in [
      ('riverpod', 'ext.flutterpilot.getRiverpodStates', 'value'),
      ('bloc', 'ext.flutterpilot.getBlocStates', 'state'),
    ]) {
      final res = await _callExtensionRaw(ext, {});
      final states = res.data?['states'];
      if (res.isError || states is! Map) continue;
      final r = restorableStates(states.cast<String, dynamic>(), valueKey);
      state[type] = r.kept;
      if (r.secret.isNotEmpty) {
        notes.add(
          'Left out (names that look like credentials): '
          '${r.secret.join(', ')}.',
        );
      }
      if (r.skipped.isNotEmpty) {
        notes.add(
          'Not saved (set_state can only restore bool/number/String): '
          '${r.skipped.join('; ')}.',
        );
      }
    }

    // Local databases, through the app's own connection.
    final databases = <String, Object?>{};
    for (final (engine, ext) in [
      ('drift', 'ext.flutterpilot.dumpDrift'),
      ('sqflite', 'ext.flutterpilot.dumpSqflite'),
    ]) {
      final res = await _callExtensionRaw(ext, {});
      final dbs = res.data?['databases'];
      if (res.isError || dbs is! Map) continue;
      for (final MapEntry(key: name, value: db) in dbs.entries) {
        if (db is! Map) continue;
        final r = scenarioTables(
          (db['tables'] as Map? ?? const {}).cast<String, Object?>(),
        );
        final skipped = [
          ...(db['skipped'] as List? ?? const []).map((s) => '$s'),
          ...r.secret.map((t) => '$t (a column looks like a credential)'),
        ];
        if (skipped.isNotEmpty) {
          notes.add(
            'Database "$name": not saved, and left as they are on load: '
            '${skipped.join('; ')}.',
          );
        }
        if (r.kept.isEmpty) continue;
        final sequences =
            (db['sequences'] as Map? ?? const {}).cast<String, Object?>()
              ..removeWhere((t, _) => !r.kept.containsKey(t));
        databases['$name'] = {
          'engine': engine,
          'tables': r.kept,
          if (sequences.isNotEmpty) 'sequences': sequences,
        };
      }
    }

    final hive = <String, Object?>{};
    final h = await _callExtensionRaw('ext.flutterpilot.dumpHive', {});
    if (!h.isError) {
      final secret = <String>[];
      for (final MapEntry(key: name, value: entries)
          in ((h.data?['boxes'] as Map?) ?? const {}).entries) {
        final kept = <Object?>[];
        for (final e in entries as List) {
          if (Redaction.sensitiveName.hasMatch('${(e as List)[0]}')) {
            secret.add('$name.${e[0]}');
          } else {
            kept.add(e);
          }
        }
        hive['$name'] = kept;
      }
      final skipped = (h.data?['skipped'] as List? ?? const []);
      if (skipped.isNotEmpty) {
        notes.add(
          'Hive boxes not saved (only plain JSON values can be put back): '
          '${skipped.join('; ')}.',
        );
      }
      if (secret.isNotEmpty) {
        notes.add(
          'Left out Hive keys that look like credentials (loading keeps '
          'none of them): ${secret.join(', ')}.',
        );
      }
    }

    final scenario = Scenario(
      description: description,
      route: route,
      prefs: prefs,
      mocks: mocks,
      channelMocks: channelMocks,
      riverpod: state['riverpod'] ?? const {},
      bloc: state['bloc'] ?? const {},
      databases: databases,
      hive: hive,
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(scenario.encode());
    return CallToolResult(
      content: [
        TextContent(
          text: [
            'Saved ${file.path}: ${scenario.summary}.',
            ...notes,
            'Edit it freely; scenario(load: '
                '"${file.uri.pathSegments.last.replaceAll('.json', '')}") '
                'restores it.',
          ].join('\n'),
        ),
      ],
    );
  }

  Future<CallToolResult> _loadScenario(
    Directory dir,
    String name,
    RequestHandlerExtra? extra,
  ) async {
    final file = File('${dir.path}/$name.json');
    if (!file.existsSync()) {
      final list = _listScenarios(dir).content.whereType<TextContent>();
      return _scenarioError(
        'No scenario "$name". ${list.map((c) => c.text).join()}',
      );
    }
    final Scenario scenario;
    try {
      scenario = Scenario.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
    } catch (e) {
      return _scenarioError('${file.path} is not valid: $e');
    }
    if (scenario.replacesStoredData && !allowDestructive) {
      final what = [
        if (scenario.prefs != null) 'SharedPreferences ("prefs")',
        if (scenario.databases.isNotEmpty) 'database rows ("databases")',
        if (scenario.hive.isNotEmpty) 'Hive boxes ("hive")',
      ];
      return _scenarioError(
        'Scenario "$name" replaces the app\'s ${what.join(', ')}: restart '
        'FlutterPilot with --allow-destructive to load it (or remove '
        '${what.length == 1 ? 'that part' : 'those parts'} from '
        '${file.path}).',
      );
    }
    final done = <String>[];
    final problems = <String>[];

    // 1. Stored data first: the restarted app reads it at startup.
    final prefs = scenario.prefs;
    if (prefs != null) {
      final cleared = await _callExtensionRaw(
        'ext.flutterpilot.clearSharedPreferences',
        {'confirm': 'CLEAR_ALL'},
      );
      if (cleared.isError) {
        problems.add('preferences: ${cleared.errorMessage}');
      } else {
        var set = 0;
        for (final MapEntry(:key, :value) in prefs.entries) {
          final typed = prefForSetter(value);
          if (typed == null) {
            problems.add('preference $key: unsupported value $value');
            continue;
          }
          final res = await _callExtensionRaw(
            'ext.flutterpilot.setSharedPreference',
            {'key': key, 'value': typed.value, 'type': typed.type},
          );
          if (res.isError) {
            problems.add('preference $key: ${res.errorMessage}');
          } else {
            set++;
          }
        }
        done.add('preferences replaced ($set)');
      }
    }

    for (final engine in ['drift', 'sqflite']) {
      final dbs = {
        for (final MapEntry(key: name, value: db) in scenario.databases.entries)
          if (db is Map && (db['engine'] ?? 'drift') == engine) name: db,
      };
      if (dbs.isEmpty) continue;
      final res = await _callExtensionRaw(
        'ext.flutterpilot.restore${engine == 'drift' ? 'Drift' : 'Sqflite'}',
        {'data': jsonEncode(dbs)},
      );
      if (res.isError) {
        problems.add('database (${dbs.keys.join(', ')}): ${res.errorMessage}');
        continue;
      }
      for (final MapEntry(key: name, value: tables)
          in ((res.data?['restored'] as Map?) ?? const {}).entries) {
        final rows = (tables as Map).values.fold<int>(
          0,
          (a, b) => a + (b as int),
        );
        done.add(
          'database "$name" replaced ($rows row(s) in ${tables.length} '
          'table(s))',
        );
      }
      for (final MapEntry(key: name, value: why)
          in ((res.data?['errors'] as Map?) ?? const {}).entries) {
        problems.add('database "$name" left unchanged: $why');
      }
    }
    if (scenario.hive.isNotEmpty) {
      final res = await _callExtensionRaw('ext.flutterpilot.restoreHive', {
        'data': jsonEncode(scenario.hive),
      });
      if (res.isError) {
        problems.add('Hive: ${res.errorMessage}');
      } else {
        final restored = (res.data?['restored'] as Map?) ?? const {};
        if (restored.isNotEmpty) {
          done.add('Hive box(es) replaced (${restored.keys.join(', ')})');
        }
        for (final MapEntry(key: name, value: why)
            in ((res.data?['errors'] as Map?) ?? const {}).entries) {
          problems.add('Hive box "$name": $why');
        }
      }
    }

    // 2. Mocks survive the restart in a file the app reads at startup.
    if (scenario.mocks.isNotEmpty || scenario.channelMocks.isNotEmpty) {
      final res = await _callExtensionRaw('ext.flutterpilot.prepareRestart', {
        'data': jsonEncode({
          if (scenario.mocks.isNotEmpty) 'httpMocks': scenario.mocks,
          if (scenario.channelMocks.isNotEmpty)
            'channelMocks': scenario.channelMocks,
        }),
      });
      if (res.isError) problems.add('mocks: ${res.errorMessage}');
    }

    // 3. Restart into it.
    final restart = _toolCallbacks['hot_reload'];
    if (restart == null || extra == null) {
      return _scenarioError('Hot restart is not available.');
    }
    final restarted = await restart({'restart': true}, extra);
    if (restarted.isError == true) {
      return _scenarioError(
        'Hot restart failed: ${restarted.content.whereType<TextContent>().map((c) => c.text).join(' ')}',
      );
    }
    for (var i = 0; i < 40; i++) {
      if (!(await _callExtensionRaw('ext.flutterpilot.ping', {})).isError) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (scenario.mocks.isNotEmpty) {
      final active = await _callExtensionRaw(
        'ext.flutterpilot.getHttpMocks',
        {},
      );
      final count = (active.data?['mocks'] as List?)?.length ?? 0;
      if (count >= scenario.mocks.length) {
        done.add('$count mocked response(s) active from the first request');
      } else {
        problems.add(
          'mocks: $count of ${scenario.mocks.length} active (the app must '
          'call DioPilotInterceptor.register() in main())',
        );
      }
    }

    if (scenario.channelMocks.isNotEmpty) {
      final active = await _callExtensionRaw(
        'ext.flutterpilot.platformChannel',
        {},
      );
      final count = (active.data?['mocks'] as List?)?.length ?? 0;
      if (active.data?['installed'] != true) {
        problems.add(
          'platform-channel mocks: FlutterPilot.initialize() must be the '
          'first line of main() for them to answer',
        );
      } else if (count >= scenario.channelMocks.length) {
        done.add(
          '$count platform-channel mock(s) active from the first plugin call',
        );
      } else {
        problems.add(
          'platform-channel mocks: $count of '
          '${scenario.channelMocks.length} active',
        );
      }
    }

    // 4. Where it was, then the in-memory state of what that screen shows.
    final route = scenario.route;
    if (route != null) {
      final go = _toolCallbacks['navigate_to'];
      final res = go == null ? null : await go({'route': route}, extra);
      if (res == null || res.isError == true) {
        problems.add(
          'route $route: ${res?.content.whereType<TextContent>().map((c) => c.text).join(' ') ?? 'navigate_to unavailable'}',
        );
      } else {
        done.add('route $route');
      }
    }
    for (final (type, states) in [
      ('riverpod', scenario.riverpod),
      ('bloc', scenario.bloc),
    ]) {
      if (states.isEmpty) continue;
      final res = await _callExtensionRaw('ext.flutterpilot.batchSetState', {
        'type': type,
        'states': jsonEncode(states),
      });
      final updated = res.data?['updatedCount'] as int? ?? 0;
      if (res.isError || updated < states.length) {
        problems.add(
          '$type state: $updated of ${states.length} set'
          '${res.isError ? ' (${res.errorMessage})' : ' (a provider not created yet on this screen is skipped)'}',
        );
      }
      if (updated > 0) done.add('$updated $type value(s)');
    }

    return CallToolResult(
      isError: problems.isNotEmpty && done.isEmpty,
      content: [
        TextContent(
          text: [
            'Loaded scenario "$name" (hot restart): ${done.join(', ')}.',
            if (problems.isNotEmpty) 'Not applied: ${problems.join('; ')}.',
          ].join('\n'),
        ),
      ],
    );
  }
}
