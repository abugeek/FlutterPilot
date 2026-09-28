part of '../../flutterpilot_server.dart';

/// DevTools-equivalent deep inspection tools that use the VM Service Protocol.
mixin _DevtoolsToolsMixin on _FlutterPilotServerBase {
  /// Tools profile_action may run: the ones that act on the app.
  static const _profilableTools = {
    'tap_widget',
    'enter_text',
    'press_key',
    'scroll_into_view',
    'swipe_widget',
    'drag_widget',
    'pinch_zoom',
    'fill_form',
    'execute_action_chain',
    'toggle_checkbox',
    'set_slider_value',
    'navigate_to',
    'hot_reload',
  };

  /// The isolate running the Flutter UI: the one with `ext.flutter.*`.
  Future<String?> _uiIsolateId(VmService vm, String? cached) async {
    if (cached != null) return cached;
    String? first;
    for (final ref in (await vm.getVM()).isolates ?? const <IsolateRef>[]) {
      final id = ref.id;
      if (id == null) continue;
      first ??= id;
      final rpcs = (await vm.getIsolate(id)).extensionRPCs ?? const [];
      if (rpcs.any((r) => r.startsWith('ext.flutter.'))) return id;
    }
    return first;
  }

  /// App code = the root library's package (and its directory).
  Future<CodeClassifier> _codeClassifier(VmService vm, String isolateId) async {
    final packages = <String>{};
    String? root;
    try {
      var uri = (await vm.getIsolate(isolateId)).rootLib?.uri;
      if (uri != null && uri.startsWith('package:')) {
        packages.add(uri.substring(8).split('/').first);
        uri = (await vm.lookupResolvedPackageUris(isolateId, [
          uri,
        ])).uris?.first;
      }
      if (uri != null && uri.startsWith('file:')) {
        final path = Uri.parse(uri).path;
        final lib = path.lastIndexOf('/lib/');
        if (lib > 0) root = path.substring(0, lib);
      }
      if (root != null) {
        final pubspec = File('$root/pubspec.yaml');
        if (pubspec.existsSync()) {
          final name = RegExp(
            r'^name:\s*([\w]+)',
            multiLine: true,
          ).firstMatch(pubspec.readAsStringSync())?.group(1);
          if (name != null) packages.add(name);
        }
      }
    } catch (_) {}
    // The package map the app was built with, found above its root.
    for (
      var dir = root == null ? null : Directory(root);
      dir != null;
      dir = dir.parent.path == dir.path ? null : dir.parent
    ) {
      final config = File('${dir.path}/.dart_tool/package_config.json');
      if (!config.existsSync()) continue;
      try {
        return CodeClassifier.fromPackageConfig(
          appPackages: packages,
          appRoot: root,
          json: jsonDecode(config.readAsStringSync()) as Map<String, dynamic>,
          configUri: config.absolute.uri,
        );
      } catch (_) {
        break;
      }
    }
    return CodeClassifier(appPackages: packages, appRoot: root);
  }

  /// The line [function] starts on, from its script's token table.
  Future<int?> _lineOf(VmService vm, String isolateId, Object? function) async {
    if (function is! FuncRef) return null;
    final location = function.location;
    if (location == null) return null;
    if (location.line != null) return location.line;
    final scriptId = location.script?.id;
    final pos = location.tokenPos;
    if (scriptId == null || pos == null) return null;
    try {
      final script = await vm.getObject(isolateId, scriptId);
      if (script is Script) return script.getLineNumberFromTokenPos(pos);
    } catch (_) {}
    return null;
  }

  void _registerDevtoolsTools() {
    Future<CallToolResult> allocationProfile(
      Map<String, dynamic> params,
    ) async {
      final vmService = await _vmServiceForParameters(params);
      if (vmService == null) {
        return CallToolResult(
          content: [TextContent(text: 'No VM Service connection.')],
        );
      }
      final limit = ((params['limit'] as int?) ?? 30).clamp(1, 500);
      try {
        final vm = await vmService.getVM();
        final isolateId = vm.isolates?.firstOrNull?.id;
        if (isolateId == null) {
          return CallToolResult(
            content: [TextContent(text: 'No isolate available.')],
          );
        }
        final profile = await vmService.getAllocationProfile(isolateId);
        final members = profile.members ?? [];
        members.sort(
          (a, b) => (b.bytesCurrent ?? 0).compareTo(a.bytesCurrent ?? 0),
        );
        final top = members.take(limit);
        final buf = StringBuffer(
          'Top $limit classes by heap usage (from ${members.length} total):\n'
          '${'Class'.padRight(40)} ${'Bytes'.padLeft(12)} ${'Instances'.padLeft(12)}\n'
          '${'-' * 66}\n',
        );
        for (final c in top) {
          if ((c.bytesCurrent ?? 0) == 0) continue;
          final name = (c.classRef?.name ?? '?').padRight(40);
          final bytes = ((c.bytesCurrent ?? 0) / 1024)
              .toStringAsFixed(1)
              .padLeft(11);
          final instances = '${c.instancesCurrent ?? 0}'.padLeft(12);
          buf.writeln('$name ${bytes}KB $instances');
        }
        return CallToolResult(content: [TextContent(text: buf.toString())]);
      } catch (e) {
        return CallToolResult(
          content: [TextContent(text: 'Allocation profile failed: $e')],
          isError: true,
        );
      }
    }

    // -- get_memory_details ---------------------------------------------------
    _tool(
      'get_memory_details',
      description:
          'Heap used/capacity and external (native) memory per isolate. '
          'classes:true lists the top Dart classes by heap bytes and instance '
          'count instead (the DevTools Memory tab) — compare before/after a '
          'screen to find leaks.',
      inputSchema: ToolInputSchema(
        properties: {
          'classes': JsonSchema.boolean(
            description: 'List the top classes by heap usage.',
          ),
          'limit': JsonSchema.integer(
            description: 'Number of classes (default 30).',
          ),
        },
      ),
      callback: (params, extra) async {
        if (params['classes'] == true) return allocationProfile(params);
        final vmService = await _vmServiceForParameters(params);
        if (vmService == null) {
          return CallToolResult(
            content: [TextContent(text: 'No VM Service connection.')],
          );
        }
        try {
          final vm = await vmService.getVM();
          final buf = StringBuffer('Memory details:\n');
          int totalHeapUsed = 0;
          int totalHeapCapacity = 0;
          int totalExternal = 0;
          for (final iso in vm.isolates ?? []) {
            if (iso.id == null) continue;
            try {
              final m = await vmService.getMemoryUsage(iso.id!);
              final heapUsedMb = ((m.heapUsage ?? 0) / (1024 * 1024))
                  .toStringAsFixed(2);
              final heapCapMb = ((m.heapCapacity ?? 0) / (1024 * 1024))
                  .toStringAsFixed(2);
              final extMb = ((m.externalUsage ?? 0) / (1024 * 1024))
                  .toStringAsFixed(2);
              buf.writeln(
                '  ${iso.name ?? iso.id}: heap=$heapUsedMb/$heapCapMb MB  external=$extMb MB',
              );
              totalHeapUsed += m.heapUsage ?? 0;
              totalHeapCapacity += m.heapCapacity ?? 0;
              totalExternal += m.externalUsage ?? 0;
            } catch (e) {
              _log.fine('Failed to query isolate: $e');
            }
          }
          buf.writeln(
            '\nTotals: heap=${((totalHeapUsed) / (1024 * 1024)).toStringAsFixed(2)}/'
            '${((totalHeapCapacity) / (1024 * 1024)).toStringAsFixed(2)} MB  '
            'external=${((totalExternal) / (1024 * 1024)).toStringAsFixed(2)} MB',
          );
          return CallToolResult(content: [TextContent(text: buf.toString())]);
        } catch (e) {
          return CallToolResult(
            content: [TextContent(text: 'Memory query failed: $e')],
            isError: true,
          );
        }
      },
    );

    // -- profile_action -------------------------------------------------------
    _tool(
      'profile_action',
      description:
          'CPU profile of one action: runs tool (tap_widget, scroll_into_view, '
          'enter_text, execute_action_chain, ...) with arguments while '
          'sampling the UI isolate, then lists the app\'s functions by self '
          'and total time with file:line, and the hottest framework functions '
          'with the app code that called them. durationMs keeps sampling '
          'after the action (results that load later); without tool it '
          'samples whatever the app does. Use to find why an interaction is '
          'slow.',
      inputSchema: ToolInputSchema(
        properties: {
          'tool': JsonSchema.string(
            description:
                'The action tool to run, e.g. "tap_widget" or '
                '"execute_action_chain".',
          ),
          'arguments': JsonSchema.object(
            description: 'Its arguments, e.g. {"key": "Load more"}.',
          ),
          'durationMs': JsonSchema.integer(
            description:
                'Keep sampling this long after the action returns, for work '
                'that lands later (a network response, an animation). '
                'Without tool: how long to sample (default 1000, max 10000).',
          ),
        },
      ),
      callback: (params, extra) async {
        CallToolResult fail(String text) =>
            CallToolResult(isError: true, content: [TextContent(text: text)]);
        final tool = params['tool'] as String?;
        final arguments = params['arguments'] is Map
            ? Map<String, dynamic>.from(params['arguments'] as Map)
            : <String, dynamic>{};
        if (tool != null && !_profilableTools.contains(tool)) {
          return fail(
            'profile_action runs an action tool: '
            '${(_profilableTools.where(_toolCallbacks.containsKey).toList()..sort()).join(', ')}. '
            'Got "$tool".',
          );
        }
        final action = tool == null ? null : _toolCallbacks[tool];
        if (tool != null && action == null) {
          return fail('Tool "$tool" is not available.');
        }
        final context = await _deviceContextForParameters(params);
        final vm = context?.service;
        if (vm == null) {
          return fail(
            'No active Flutter app connection. Start your app with '
            '"flutter run" or call connect_app.',
          );
        }
        final isolateId = await _uiIsolateId(vm, context?.cachedMainIsolateId);
        if (isolateId == null) return fail('No Flutter isolate found.');

        final flags = (await vm.getFlagList()).flags ?? const <Flag>[];
        String? flag(String name) =>
            flags.where((f) => f.name == name).firstOrNull?.valueAsString;
        if (flag('profiler') == 'false') {
          return fail(
            'The Dart VM profiler is off in this app (started with '
            '--no-profiler?). Relaunch with "flutter run".',
          );
        }
        // Finer samples for short actions; restored afterwards.
        final period = flag('profile_period');
        var finer = false;
        try {
          await vm.setFlag('profile_period', '250');
          finer = true;
        } catch (_) {}

        final CpuSamples cpu;
        final watch = Stopwatch()..start();
        CallToolResult? actionResult;
        try {
          final start = (await vm.getVMTimelineMicros()).timestamp!;
          if (action != null) actionResult = await action(arguments, extra);
          final extraMs = (params['durationMs'] as num?)?.toInt();
          final ms = (extraMs ?? (action == null ? 1000 : 0)).clamp(0, 10000);
          if (ms > 0) await Future<void>.delayed(Duration(milliseconds: ms));
          final end = (await vm.getVMTimelineMicros()).timestamp!;
          watch.stop();
          cpu = await vm.getCpuSamples(isolateId, start, end - start);
        } catch (e) {
          return fail('CPU profiling failed: $e');
        } finally {
          if (finer && period != null) {
            try {
              await vm.setFlag('profile_period', period);
            } catch (_) {}
          }
        }

        final classifier = await _codeClassifier(vm, isolateId);
        final profile = ActionProfile.analyze(cpu, classifier);
        final lines = <int, int?>{};
        Future<String> where(FunctionCost f) async {
          final url = f.url;
          if (url == null) return '';
          final line = lines.containsKey(f.index)
              ? lines[f.index]
              : lines[f.index] = await _lineOf(
                  vm,
                  isolateId,
                  cpu.functions![f.index].function,
                );
          return '${classifier.display(url)}${line == null ? '' : ':$line'}';
        }

        String ms(int samples) => profile.ms(samples).toStringAsFixed(1);
        final label = tool == null
            ? 'Sampled the app for ${watch.elapsedMilliseconds} ms'
            : 'Profiled $tool(${jsonEncode(arguments)}): '
                  '${watch.elapsedMilliseconds} ms wall';
        final buf = StringBuffer(
          '$label, '
          '${ms(profile.dartSamples)} ms running Dart on the UI isolate '
          '(${cpu.samplePeriod} µs samples).\n'
          'App code: ${ms(profile.appSamples)} ms · framework and packages: '
          '${ms(profile.dartSamples - profile.appSamples)} ms · '
          'GC/VM/native: ${ms(profile.nativeSamples)} ms'
          '${profile.flutterpilotSamples > 0 ? ' · FlutterPilot reading the screen (left out): ${ms(profile.flutterpilotSamples)} ms' : ''}.\n',
        );
        final app = profile.topApp(classifier);
        if (app.isEmpty) {
          buf.writeln(
            'No app function was sampled: the app\'s own code did not run '
            'long enough to be seen (each sample is ${cpu.samplePeriod} µs).',
          );
        } else {
          buf.writeln('App functions (self / total ms):');
          for (final f in app) {
            buf.writeln(
              '  ${ms(f.self)} / ${ms(f.total)}  ${f.name}  ${await where(f)}',
            );
          }
        }
        final hot = profile.topSelf();
        if (hot.isNotEmpty) {
          buf.writeln('Hottest functions by self time:');
          for (final f in hot) {
            final caller = f.topAppCaller;
            final by = caller == null
                ? ''
                : ' ← ${profile.functions[caller].name} '
                      '${await where(profile.functions[caller])}';
            buf.writeln(
              '  ${ms(f.self)}  ${f.name} (${f.url == null ? 'native' : classifier.display(f.url!)})$by',
            );
          }
        }
        if (actionResult != null) {
          final text = actionResult.content
              .whereType<TextContent>()
              .map((c) => c.text)
              .join('\n');
          final firstLines = text.split('\n').take(3).join('\n');
          buf.write(
            '\n$tool ${actionResult.isError == true ? 'failed' : 'result'}: '
            '$firstLines',
          );
        }
        return CallToolResult(
          isError: actionResult?.isError == true,
          content: [TextContent(text: buf.toString().trim())],
        );
      },
    );

    // -- get_http_profile -----------------------------------------------------
    _tool(
      'get_http_profile',
      description:
          'HTTP requests the app made through any dart:io client (the DevTools '
          'Network tab): method, URL, status, duration, request/response size, '
          'most recent first. clear:true empties the list for a '
          'clean baseline.',
      inputSchema: ToolInputSchema(
        properties: {
          'clear': JsonSchema.boolean(
            description: 'Clear the recorded requests instead of listing them.',
          ),
          'limit': JsonSchema.integer(
            description:
                'Maximum number of requests to return, most recent first (default: 50).',
          ),
          'status_filter': JsonSchema.integer(
            description:
                'Optional HTTP status code filter (e.g. 404, 500). Omit to return all requests.',
          ),
        },
      ),
      callback: (params, extra) async {
        if (params['clear'] == true) {
          await _enableHttpProfiling(params);
          final res = await _callExtensionRaw(
            'ext.dart.io.clearHttpProfile',
            {},
          );
          return CallToolResult(
            isError: res.isError,
            content: [
              TextContent(
                text: res.isError
                    ? 'Clear failed: ${res.errorMessage}'
                    : 'HTTP profile cleared.',
              ),
            ],
          );
        }
        final limit = ((params['limit'] as int?) ?? 50).clamp(1, 500);
        final statusFilter = params['status_filter'] as int?;
        // The VM records nothing until profiling is on; it resets on restart.
        final wasOff = await _enableHttpProfiling(params);
        final res = await _callExtensionRaw('ext.dart.io.getHttpProfile', {});
        if (res.isError) {
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'HTTP profile unavailable: ${res.errorMessage}\n'
                    'Note: dart:io HTTP profiling is only available in debug builds.',
              ),
            ],
          );
        }
        final requests = (res.data?['requests'] as List<dynamic>?) ?? [];
        var filtered = requests.whereType<Map<String, dynamic>>().toList();
        if (statusFilter != null) {
          filtered = filtered
              .where(
                (r) => (r['response'] as Map?)?['statusCode'] == statusFilter,
              )
              .toList();
        }
        if (filtered.isEmpty) {
          return CallToolResult(
            content: [
              TextContent(
                text: wasOff
                    ? 'HTTP profiling was off and is now enabled. Repeat the action, then call this again.'
                    : 'No HTTP requests recorded yet.',
              ),
            ],
          );
        }
        final shown = filtered.reversed.take(limit);
        final buf = StringBuffer(
          '${filtered.length} HTTP requests (showing last $limit):\n',
        );
        for (final req in shown) {
          final method = req['method'] ?? '?';
          final uri = req['uri'] ?? '?';
          final status =
              (req['response'] as Map?)?['statusCode']?.toString() ?? '...';
          final start = req['startTime'] as int? ?? 0;
          final end = req['endTime'] as int? ?? 0;
          final durationMs = end > 0
              ? '${((end - start) / 1000).round()}ms'
              : 'pending';
          final reqSize = ((req['request'] as Map?)?['contentLength'] ?? 0)
              .toString();
          final respSize = ((req['response'] as Map?)?['contentLength'] ?? 0)
              .toString();
          buf.writeln(
            '[$status] $method $uri  ⏱$durationMs  ↑${reqSize}B ↓${respSize}B',
          );
        }
        return CallToolResult(content: [TextContent(text: buf.toString())]);
      },
    );
  }

  /// Turns on dart:io HTTP profiling (what DevTools' Network tab does).
  /// Returns true if it was off.
  Future<bool> _enableHttpProfiling(Map<String, dynamic> params) async {
    final state = await _callExtensionRaw(
      'ext.dart.io.httpEnableTimelineLogging',
      {},
    );
    if (state.data?['enabled'] == true) return false;
    await _callExtensionRaw('ext.dart.io.httpEnableTimelineLogging', {
      'enabled': 'true',
    });
    return true;
  }
}
