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

  /// get_memory_details(cycle, times): runs the cycle once to warm up, then
  /// [times] rounds with a GC'd allocation profile after each; reports the
  /// classes that grew every round, where they are defined and, for the
  /// app's own, what retains one.
  Future<CallToolResult> _leakCheck(
    Map<String, dynamic> params,
    RequestHandlerExtra? extra,
  ) async {
    CallToolResult fail(String text) =>
        CallToolResult(isError: true, content: [TextContent(text: text)]);
    final context = await _deviceContextForParameters(params);
    if (context?.isWeb == true) {
      return fail(
        'get_memory_details leak check is not available on web: allocation '
        'profiles are not supported on web.',
      );
    }
    final steps = <({String tool, Map<String, dynamic> arguments})>[];
    for (final step in (params['cycle'] as List? ?? const [])) {
      final tool = step is Map ? step['tool'] : null;
      if (tool is! String ||
          !_profilableTools.contains(tool) ||
          !_toolCallbacks.containsKey(tool)) {
        return fail(
          'Each cycle step is {"tool": <action tool>, "arguments": {...}}; '
          'action tools: '
          '${(_profilableTools.where(_toolCallbacks.containsKey).toList()..sort()).join(', ')}. '
          'Got ${jsonEncode(step)}.',
        );
      }
      final args = step['arguments'];
      steps.add((
        tool: tool,
        arguments: args is Map ? Map<String, dynamic>.from(args) : {},
      ));
    }
    if (steps.isEmpty) {
      return fail(
        'cycle is empty: give the steps that open something and return, '
        'e.g. a tap then press_key back.',
      );
    }
    final times = ((params['times'] as num?)?.toInt() ?? 5).clamp(2, 20);
    final vm = context?.service;
    if (vm == null) {
      return fail(
        'No active Flutter app connection. Start your app with '
        '"flutter run" or call connect_app.',
      );
    }
    final isolateId = await _uiIsolateId(vm, context?.cachedMainIsolateId);
    if (isolateId == null) return fail('No Flutter isolate found.');
    final classifier = await _codeClassifier(vm, isolateId);

    /// Null when every step succeeded, else what failed.
    Future<String?> round(String label) async {
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        final res = await _toolCallbacks[step.tool]!(step.arguments, extra!);
        if (res.isError == true) {
          final text = res.content
              .whereType<TextContent>()
              .map((c) => c.text)
              .join(' ');
          return '$label, step ${i + 1} (${step.tool}) failed: '
              '${text.split('\n').first}';
        }
      }
      return null;
    }

    Future<Map<String, ({String name, String? library, int instances})>>
    snapshot() async {
      final AllocationProfile profile;
      try {
        profile = await vm.getAllocationProfile(isolateId, gc: true);
      } on RPCError catch (e) {
        if (e.code == -32601) {
          throw StateError(
            'get_memory_details leak check is not available on web: '
            '${e.message}.',
          );
        }
        rethrow;
      }
      return {
        for (final m in profile.members ?? const <ClassHeapStats>[])
          if (m.classRef?.id != null)
            m.classRef!.id!: (
              name: m.classRef!.name ?? '?',
              library: m.classRef!.library?.uri,
              instances: m.instancesCurrent ?? 0,
            ),
      };
    }

    Future<double> heapMb() async =>
        ((await vm.getMemoryUsage(isolateId)).heapUsage ?? 0) / (1024 * 1024);

    final label = steps
        .map((s) => '${s.tool}(${jsonEncode(s.arguments)})')
        .join(' → ');
    // Warm-up: first visits fill caches (images, fonts, lazy singletons).
    final warm = await round('Warm-up');
    if (warm != null) {
      return fail(
        '$warm\nThe cycle must work from the current screen and end back on '
        'it.',
      );
    }
    final List<Map<String, ({String name, String? library, int instances})>>
    snapshots;
    final double heapBefore;
    String? stopped;
    try {
      snapshots = [await snapshot()];
      heapBefore = await heapMb();
      for (var r = 1; r <= times; r++) {
        stopped = await round('Round $r');
        if (stopped != null) break;
        snapshots.add(await snapshot());
      }
    } on StateError catch (e) {
      return fail(e.message);
    }
    final heapAfter = await heapMb();
    final rounds = snapshots.length - 1;

    final growing = growingClasses(
      snapshots,
    ).where((c) => classifier.ownerOf(c.library) != CodeOwner.flutterpilot);
    final app = growing
        .where((c) => classifier.ownerOf(c.library) == CodeOwner.app)
        .toList();
    // Framework and package classes only when they grow by the same amount
    // every round and belong to a library: VM internals (Code, ICData)
    // grow as the debug JIT compiles, caches and lists unevenly.
    final other = growing
        .where(
          (c) =>
              classifier.ownerOf(c.library) != CodeOwner.app &&
              c.library != null &&
              c.steady,
        )
        .toList();

    Future<String> where(GrowingClass c) async {
      try {
        final cls = await vm.getObject(isolateId, c.id);
        if (cls is Class) {
          final loc = cls.location;
          final uri = loc?.script?.uri ?? c.library;
          if (uri != null) {
            final line = loc?.line;
            return ' ${classifier.display(uri)}${line == null ? '' : ':$line'}';
          }
        }
      } catch (_) {}
      return c.library == null ? '' : ' ${classifier.display(c.library!)}';
    }

    /// identityHashCode -> object id of each live instance; null when the
    /// class has too many instances to list.
    Future<Map<int, String>?> instancesOf(GrowingClass c) async {
      final limit = c.counts.last + 50;
      if (limit > 5000) return null;
      try {
        final set = await vm.getInstances(isolateId, c.id, limit);
        return {
          for (final i in set.instances ?? const <ObjRef>[])
            if (i is InstanceRef && i.identityHashCode != null && i.id != null)
              i.identityHashCode!: i.id!,
        };
      } catch (_) {
        return null;
      }
    }

    /// The path, or null; `flutterpilot` true when FlutterPilot's own
    /// objects hold it (e.g. the SDK's frame-pump deadline).
    Future<({String text, bool flutterpilot})?> retainingPath(
      String objectId,
    ) async {
      try {
        final path = await vm.getRetainingPath(isolateId, objectId, 12);
        final elements = [
          for (final e in path.elements ?? const <RetainingObject>[])
            e.toJson(),
        ];
        if (elements.isEmpty) return null;
        final owners = pathLibraries(elements).map(classifier.ownerOf).toSet();
        // Held without any app object on the way: framework bookkeeping
        // (e.g. gesture recognizers keep an entry per pointer id), not
        // something the app's code can release.
        final appHolds = owners.contains(CodeOwner.app);
        // Framework-only paths run long; their first hops say enough.
        final shown = appHolds ? elements : elements.take(6).toList();
        final text =
            '${describeRetainingPath(shown)}'
            '${shown.length < elements.length ? ' ← …' : ''}'
            '${path.gcRootType == null ? '' : ' (GC root: ${path.gcRootType})'}'
            '${appHolds ? '' : '. Held only by framework/package objects, not by the app\'s code.'}';
        return (
          text: text,
          flutterpilot: owners.contains(CodeOwner.flutterpilot),
        );
      } catch (_) {
        return null;
      }
    }

    // Confirming round: instances created in it that survive a GC were
    // leaked by it, so their retaining path is the leak's (any instance
    // could be a live one). A class with none is dropped as noise.
    final candidates = [...app.take(4), ...other.take(4)];
    final paths = <String, String>{};
    final notLeaking = <GrowingClass>{};
    final heldByPilot = <GrowingClass>{};
    String? confirmStopped;
    if (rounds >= 2 && stopped == null && candidates.isNotEmpty) {
      try {
        await vm.getAllocationProfile(isolateId, gc: true);
      } on RPCError catch (e) {
        if (e.code == -32601) {
          return fail('get_memory_details leak check is not available on web.');
        }
        rethrow;
      }
      final before = {for (final c in candidates) c.id: await instancesOf(c)};
      confirmStopped = await round('Confirming round');
      if (confirmStopped == null) {
        try {
          await vm.getAllocationProfile(isolateId, gc: true);
        } on RPCError catch (e) {
          if (e.code == -32601) {
            return fail(
              'get_memory_details leak check is not available on web.',
            );
          }
          rethrow;
        }
        for (final c in candidates) {
          final old = before[c.id];
          final now = old == null ? null : await instancesOf(c);
          if (old == null || now == null) continue;
          final fresh = now.keys.where((h) => !old.containsKey(h));
          if (fresh.isEmpty) {
            notLeaking.add(c);
            continue;
          }
          // Up to three new instances: one FlutterPilot holds is not the
          // app's leak; if all are, the class is FlutterPilot's.
          var pilotOnly = true;
          for (final hash in fresh.take(3)) {
            final path = await retainingPath(now[hash]!);
            if (path == null) {
              pilotOnly = false;
              break;
            }
            if (path.flutterpilot) continue;
            paths[c.id] = path.text;
            pilotOnly = false;
            break;
          }
          if (pilotOnly) heldByPilot.add(c);
        }
      }
    }
    bool leaks(GrowingClass c) =>
        !notLeaking.contains(c) && !heldByPilot.contains(c);
    final appLeaks = app.where(leaks).toList();
    final otherLeaks = other.where(leaks).toList();

    String growth(GrowingClass c) => '+${c.growth} (${c.counts.join(' → ')})';
    final buf = StringBuffer(
      'Leak check: $rounds round${rounds == 1 ? '' : 's'} of $label after '
      'one warm-up; heap after GC ${heapBefore.toStringAsFixed(1)} → '
      '${heapAfter.toStringAsFixed(1)} MB.\n',
    );
    if (stopped != null) buf.writeln('Stopped early: $stopped');
    if (confirmStopped != null) {
      buf.writeln(
        'Confirming round failed ($confirmStopped): paths unchecked.',
      );
    }
    if (rounds < 2) {
      buf.writeln('Too few rounds completed to tell growth from noise.');
    } else if (appLeaks.isEmpty && otherLeaks.isEmpty) {
      buf.writeln(
        'No app class leaks per round, and no framework class keeps '
        'instances from every round: nothing leaks per cycle.',
      );
    } else {
      if (appLeaks.isNotEmpty) {
        buf.writeln('App classes leaking every round:');
        for (final c in appLeaks.take(6)) {
          buf.writeln('  ${c.name}${await where(c)}  ${growth(c)}');
          if (paths[c.id] case final path?) {
            buf.writeln('    kept alive: $path');
          }
        }
      } else {
        buf.writeln('No app class leaks per round.');
      }
      if (otherLeaks.isNotEmpty) {
        buf.writeln(
          'Framework/package classes growing by the same amount every '
          'round (${otherLeaks.length}):',
        );
        for (final c in otherLeaks.take(6)) {
          buf.writeln('  ${c.name}${await where(c)}  ${growth(c)}');
          if (paths[c.id] case final path?) {
            buf.writeln('    kept alive: $path');
          }
        }
      }
    }
    if (heldByPilot.isNotEmpty) {
      buf.writeln(
        'Held by FlutterPilot itself while it drives the app (not the '
        'app\'s): ${heldByPilot.map((c) => c.name).join(', ')}.',
      );
    }
    if (notLeaking.isNotEmpty) {
      buf.writeln(
        'Grew, but kept nothing from the confirming round (not a leak): '
        '${notLeaking.map((c) => c.name).join(', ')}.',
      );
    }
    return CallToolResult(content: [TextContent(text: buf.toString().trim())]);
  }

  /// Reads (or with [set], sets) a boolean framework debug extension such
  /// as `ext.flutter.profileUserWidgetBuilds`; null when the app doesn't
  /// have it (profile/release builds).
  Future<bool?> _serviceFlag(
    VmService vm,
    String isolateId,
    String extension, {
    bool? set,
  }) async {
    try {
      final res = await vm.callServiceExtension(
        extension,
        isolateId: isolateId,
        args: {if (set != null) 'enabled': '$set'},
      );
      return res.json?['enabled'] == 'true' || res.json?['enabled'] == true;
    } catch (_) {
      return null;
    }
  }

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
      final context = await _deviceContextForParameters(params);
      if (context?.isWeb == true) {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text:
                  'get_memory_details with classes is not available on web: '
                  'allocation profiles are not supported on web.',
            ),
          ],
        );
      }
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
      } on RPCError catch (e) {
        if (e.code == -32601) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'get_memory_details with classes is not available on web: '
                    '${e.message}.',
              ),
            ],
          );
        }
        return CallToolResult(
          content: [TextContent(text: 'Allocation profile failed: $e')],
          isError: true,
        );
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
          'count instead (the DevTools Memory tab). Leak check: cycle (action '
          'tool calls that end where they started, e.g. open a screen then '
          'press back) runs times rounds; returns the classes that gained '
          'instances every round, where they are defined and what keeps one '
          'alive.',
      inputSchema: ToolInputSchema(
        properties: {
          'classes': JsonSchema.boolean(
            description: 'List the top classes by heap usage.',
          ),
          'limit': JsonSchema.integer(
            description: 'Number of classes (default 30).',
          ),
          'cycle': JsonSchema.array(
            items: JsonSchema.object(),
            description:
                'Leak check: steps [{"tool": "tap_widget", "arguments": '
                '{"key": "Open"}}, {"tool": "press_key", "arguments": '
                '{"key": "back"}}] that return to the starting screen.',
          ),
          'times': JsonSchema.integer(
            description: 'Leak check rounds after one warm-up (default 5).',
          ),
        },
      ),
      callback: (params, extra) async {
        if (params['cycle'] != null) return _leakCheck(params, extra);
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
          'Why an interaction is slow: runs tool (tap_widget, '
          'scroll_into_view, execute_action_chain, ...) with arguments while '
          'profiling the app, then returns its functions by self/total CPU '
          'time with file:line, the hottest framework functions with the app '
          'code that called them, and for frames over budget their '
          'build/layout/paint/raster times and which app widgets rebuilt. '
          'durationMs keeps profiling after the action (results that load '
          'later); without tool it profiles whatever the app does.',
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
        if (context?.isWeb == true) {
          return fail('profile_action is not available on web.');
        }
        final vm = context?.service;
        if (vm == null) {
          return fail(
            'No active Flutter app connection. Start your app with '
            '"flutter run" or call connect_app.',
          );
        }
        final isolateId = await _uiIsolateId(vm, context?.cachedMainIsolateId);
        if (isolateId == null) return fail('No Flutter isolate found.');

        try {
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

          // Frames: the timeline streams framework phases and engine frame
          // events go to, per-widget build events for the app's widgets, and
          // the AI tap overlay off (it animates on every frame). All restored.
          final streams =
              (await vm.getVMTimelineFlags()).recordedStreams ??
              const <String>[];
          final wanted = {...streams, 'Dart', 'Embedder', 'GC'}.toList();
          var tracedStreams = false;
          try {
            if (wanted.length != streams.length) {
              await vm.setVMTimelineFlags(wanted);
              tracedStreams = true;
            }
          } catch (_) {}
          final buildsBefore = await _serviceFlag(
            vm,
            isolateId,
            'ext.flutter.profileUserWidgetBuilds',
          );
          if (buildsBefore == false) {
            await _serviceFlag(
              vm,
              isolateId,
              'ext.flutter.profileUserWidgetBuilds',
              set: true,
            );
          }
          final quiet = await _callExtensionRaw('ext.flutterpilot.profiling', {
            'enabled': 'true',
          });
          final budgetMs =
              (quiet.data?['frameBudgetMs'] as num?)?.toDouble() ?? 1000 / 60;

          final CpuSamples cpu;
          List<Map<String, dynamic>> trace = const [];
          String? traceError;
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
            try {
              final timeline = await vm.getVMTimeline(
                timeOriginMicros: start,
                timeExtentMicros: end - start,
              );
              trace = [
                for (final e in timeline.traceEvents ?? const <TimelineEvent>[])
                  if (e.json != null) e.json!,
              ];
            } catch (e) {
              traceError = '$e';
            }
          } catch (e) {
            return fail('CPU profiling failed: $e');
          } finally {
            await _callExtensionRaw('ext.flutterpilot.profiling', {
              'enabled': 'false',
            });
            if (buildsBefore == false) {
              await _serviceFlag(
                vm,
                isolateId,
                'ext.flutter.profileUserWidgetBuilds',
                set: false,
              );
            }
            if (tracedStreams) {
              try {
                await vm.setVMTimelineFlags(streams);
              } catch (_) {}
            }
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
          buf.writeln(
            traceError != null
                ? 'Frames: the VM timeline could not be read ($traceError).'
                : explainFrames(framesFromTimeline(trace), budgetMs: budgetMs),
          );
          if (quiet.data?['appVisible'] == false) {
            buf.writeln(
              'The app window is hidden: FlutterPilot forced these frames, '
              'the user saw none of them.',
            );
          }
          buf.writeln(
            context?.buildMode == BuildMode.profile
                ? profileBuildNote
                : debugBuildNote,
          );
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
        } on RPCError catch (e) {
          if (e.code == -32601) {
            return fail(
              'profile_action is not available on web: ${e.message}.',
            );
          }
          return fail('profile_action failed: $e');
        }
      },
    );

    // -- get_http_profile -----------------------------------------------------
    _tool(
      'get_http_profile',
      description:
          'HTTP requests the app made through any dart:io client (HttpClient, '
          'package:http, Dio; the DevTools Network tab): #number, method, URL, '
          'status, duration, sizes, most recent first; url filters. id: '
          'one request in full — headers, bodies (JSON, secrets masked), '
          'timing, redirects, error. clear:true empties the list for a clean '
          'baseline.',
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
          'url': JsonSchema.string(
            description: 'Only requests whose URL contains this text.',
          ),
          'id': JsonSchema.integer(
            description:
                'The #number of a request in the list: its headers, bodies '
                'and timing.',
          ),
        },
      ),
      callback: (params, extra) async {
        final context = await _deviceContextForParameters(params);
        if (context?.isWeb == true) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'get_http_profile is not available on web: web apps use '
                    'browser networking rather than dart:io.',
              ),
            ],
          );
        }
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
                    'Note: dart:io HTTP profiling works in debug and profile '
                    'builds, not release.',
              ),
            ],
          );
        }
        final requests = ((res.data?['requests'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        // #number: position since the last clear (the VM's ids are 19
        // digits), stable while the list only grows.
        final numbers = {
          for (var i = 0; i < requests.length; i++) requests[i]['id']: i + 1,
        };
        final wanted = params['id'];
        if (wanted != null) {
          final n = wanted is num ? wanted.toInt() : int.tryParse('$wanted');
          if (n == null || n < 1 || n > requests.length) {
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text:
                      'No request #$wanted: ${requests.length} recorded since '
                      'the last clear (#1–#${requests.length}). List them '
                      'without id first.',
                ),
              ],
            );
          }
          final detail = await _callExtensionRaw(
            'ext.dart.io.getHttpProfileRequest',
            {'id': '${requests[n - 1]['id']}'},
          );
          if (detail.isError || detail.data == null) {
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text:
                      'Request #$n detail unavailable: ${detail.errorMessage}',
                ),
              ],
            );
          }
          return CallToolResult(
            content: [
              TextContent(text: formatRequestDetail(detail.data!, number: n)),
            ],
          );
        }
        var filtered = requests;
        final urlFilter = params['url'] as String?;
        if (urlFilter != null && urlFilter.isNotEmpty) {
          filtered = filtered
              .where((r) => '${r['uri']}'.contains(urlFilter))
              .toList();
        }
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
                    : requests.isEmpty
                    ? 'No HTTP requests recorded yet.'
                    : 'None of the ${requests.length} recorded requests match '
                          '${[if (urlFilter != null) 'url "$urlFilter"', if (statusFilter != null) 'status $statusFilter'].join(' and ')}.',
              ),
            ],
          );
        }
        final shown = filtered.reversed.take(limit);
        final buf = StringBuffer(
          '${filtered.length} HTTP requests'
          '${filtered.length > limit ? ' (last $limit shown)' : ''}; '
          'get_http_profile(id: N) for one in full:\n',
        );
        for (final req in shown) {
          final method = req['method'] ?? '?';
          final uri = Redaction.text('${req['uri'] ?? '?'}');
          final response = req['response'] as Map?;
          final status =
              response?['statusCode']?.toString() ??
              ((req['request'] as Map?)?['error'] != null ||
                      response?['error'] != null
                  ? 'failed'
                  : '...');
          final ms = durationMs(req);
          final durationText = ms == null ? 'pending' : '${ms}ms';
          final reqSize = ((req['request'] as Map?)?['contentLength'] ?? 0)
              .toString();
          final respSize = ((req['response'] as Map?)?['contentLength'] ?? 0)
              .toString();
          buf.writeln(
            '#${numbers[req['id']]} [$status] $method $uri  ⏱$durationText  '
            '↑${reqSize}B ↓${respSize}B',
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
