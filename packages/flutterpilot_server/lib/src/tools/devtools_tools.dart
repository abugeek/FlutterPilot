part of '../../flutterpilot_server.dart';

/// DevTools-equivalent deep inspection tools that use the VM Service Protocol.
mixin _DevtoolsToolsMixin on _FlutterPilotServerBase {
  void _registerDevtoolsTools() {
    // -- get_memory_details ---------------------------------------------------
    server.registerTool(
      'get_memory_details',
      description:
          'Returns a detailed memory breakdown of the running app: heap used, '
          'heap capacity, external (native) memory, and RSS for every Dart isolate. '
          'Use this to detect memory leaks or unexpected growth. '
          'Heap > 200 MB or external > 50 MB usually warrants investigation.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        if (_vmService == null) {
          return CallToolResult(
            content: [TextContent(text: 'No VM Service connection.')],
          );
        }
        try {
          final vm = await _vmService!.getVM();
          final buf = StringBuffer('Memory details:\n');
          int totalHeapUsed = 0;
          int totalHeapCapacity = 0;
          int totalExternal = 0;
          for (final iso in vm.isolates ?? []) {
            if (iso.id == null) continue;
            try {
              final m = await _vmService!.getMemoryUsage(iso.id!);
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

    // -- get_allocation_profile -----------------------------------------------
    server.registerTool(
      'get_allocation_profile',
      description:
          'Returns the top Dart classes by current heap allocation (like the '
          'DevTools Memory tab class list). Use this to find memory leaks — '
          'look for classes with unexpectedly high instance counts or byte sizes. '
          'Accepts optional limit (default 30) for number of classes to show.',
      inputSchema: ToolInputSchema(
        properties: {
          'limit': JsonSchema.integer(
            description:
                'Number of top classes to show, sorted by heap bytes (default: 30).',
          ),
        },
      ),
      callback: (params, extra) async {
        if (_vmService == null) {
          return CallToolResult(
            content: [TextContent(text: 'No VM Service connection.')],
          );
        }
        final limit = (params['limit'] as int?) ?? 30;
        try {
          final vm = await _vmService!.getVM();
          final isolateId = vm.isolates?.firstOrNull?.id;
          if (isolateId == null) {
            return CallToolResult(
              content: [TextContent(text: 'No isolate available.')],
            );
          }
          final profile = await _vmService!.getAllocationProfile(isolateId);
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
      },
    );

    // -- get_http_profile -----------------------------------------------------
    server.registerTool(
      'get_http_profile',
      description:
          'Returns all HTTP requests made by the app — URL, method, status code, '
          'duration, and request/response size. This is the DevTools Network tab '
          'in your AI agent. Use this to debug API calls, check for slow requests '
          '(>2s), or confirm the app actually sent a request. '
          'Optional limit (default 50) caps the number of requests shown.',
      inputSchema: ToolInputSchema(
        properties: {
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
        final limit = (params['limit'] as int?) ?? 50;
        final statusFilter = params['status_filter'] as int?;
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
        var filtered =
            requests.whereType<Map<String, dynamic>>().toList();
        if (statusFilter != null) {
          filtered = filtered
              .where(
                (r) => (r['response'] as Map?)?['statusCode'] == statusFilter,
              )
              .toList();
        }
        if (filtered.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: 'No HTTP requests recorded yet.')],
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

    // -- clear_http_profile ---------------------------------------------------
    server.registerTool(
      'clear_http_profile',
      description:
          'Clears the HTTP request history so you get a clean baseline '
          'before triggering a specific API call. Pair with get_http_profile.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        final res = await _callExtensionRaw('ext.dart.io.clearHttpProfile', {});
        if (res.isError) {
          return CallToolResult(
            content: [TextContent(text: 'Clear failed: ${res.errorMessage}')],
          );
        }
        return CallToolResult(
          content: [TextContent(text: 'HTTP profile cleared.')],
        );
      },
    );

    // -- get_render_tree ------------------------------------------------------
    server.registerTool(
      'get_render_tree',
      description:
          'Dumps the render object tree — the layout/paint layer beneath the '
          'widget tree. Use this to debug layout issues, overflow errors, or '
          'understand exactly how Flutter is sizing and positioning widgets. '
          'This is the DevTools Layout Explorer equivalent for AI agents.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        final res = await _callExtensionRaw(
          'ext.flutter.debugDumpRenderTree',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        final tree =
            res.data?['data']?.toString() ??
            res.data?['result']?.toString() ??
            jsonEncode(res.data);
        final out = tree.length > _Constants.renderTreeMaxLen
            ? '${tree.substring(0, _Constants.renderTreeMaxLen)}\n... (truncated, ${tree.length - _Constants.renderTreeMaxLen} chars omitted)'
            : tree;
        return CallToolResult(content: [TextContent(text: out)]);
      },
    );

    // -- get_layer_tree -------------------------------------------------------
    server.registerTool(
      'get_layer_tree',
      description:
          'Dumps the compositing layer tree — the GPU-level representation of '
          'the scene. Use this to debug performance issues caused by unnecessary '
          'repaint layers, or to understand why widgets are not composited efficiently.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        final res = await _callExtensionRaw(
          'ext.flutter.debugDumpLayerTree',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        final tree =
            res.data?['data']?.toString() ??
            res.data?['result']?.toString() ??
            jsonEncode(res.data);
        final out = tree.length > _Constants.layerTreeMaxLen
            ? '${tree.substring(0, _Constants.layerTreeMaxLen)}\n... (truncated)'
            : tree;
        return CallToolResult(content: [TextContent(text: out)]);
      },
    );

    // -- get_vm_info ----------------------------------------------------------
    server.registerTool(
      'get_vm_info',
      description:
          'Returns Dart VM version, process ID, all running isolates and their '
          'pause/run state. Use this to confirm which Dart version the app is '
          'running on, or to check isolate health.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        if (_vmService == null) {
          return CallToolResult(
            content: [TextContent(text: 'No VM Service connection.')],
          );
        }
        try {
          final vm = await _vmService!.getVM();
          final buf = StringBuffer();
          buf.writeln('VM version: ${vm.version ?? 'unknown'}');
          buf.writeln('PID: ${vm.pid ?? 'unknown'}');
          buf.writeln('Isolates (${vm.isolates?.length ?? 0}):');
          for (final iso in vm.isolates ?? []) {
            buf.writeln('  ${iso.name ?? iso.id} (id=${iso.id})');
          }
          return CallToolResult(content: [TextContent(text: buf.toString())]);
        } catch (e) {
          return CallToolResult(
            content: [TextContent(text: 'VM info failed: $e')],
            isError: true,
          );
        }
      },
    );

    // -- toggle_repaint_rainbow -----------------------------------------------
    server.registerTool(
      'toggle_repaint_rainbow',
      description:
          'Enables or disables the repaint rainbow overlay (each layer '
          'that repaints cycles through colors). Use this to visually identify '
          'which parts of the UI are repainting more than expected — '
          'a classic Flutter performance debugging technique.',
      inputSchema: ToolInputSchema(
        properties: {
          'enabled': JsonSchema.boolean(
            description:
                'true to enable the repaint rainbow overlay, false to disable.',
          ),
        },
        required: ['enabled'],
      ),
      callback: (params, extra) async {
        final enabled = params['enabled'] as bool? ?? true;
        final res = await _callExtensionRaw('ext.flutter.repaintRainbow', {
          'enabled': enabled.toString(),
        });
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Repaint rainbow ${enabled ? 'enabled' : 'disabled'}. '
                  '${enabled ? 'Look for rapidly cycling colors on screen — those widgets repaint every frame.' : ''}',
            ),
          ],
        );
      },
    );

    // -- toggle_debug_paint ---------------------------------------------------
    server.registerTool(
      'toggle_debug_paint',
      description:
          'Enables or disables debug paint — shows layout padding (blue), '
          'widget boundaries (orange), baselines (green), and pointer hit areas. '
          'Use this to debug layout issues like unexpected padding or misaligned widgets.',
      inputSchema: ToolInputSchema(
        properties: {
          'enabled': JsonSchema.boolean(
            description:
                'true to show debug paint boundaries and padding, false to hide.',
          ),
        },
        required: ['enabled'],
      ),
      callback: (params, extra) async {
        final enabled = params['enabled'] as bool? ?? true;
        final res = await _callExtensionRaw('ext.flutter.debugPaint', {
          'enabled': enabled.toString(),
        });
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: 'Debug paint ${enabled ? 'enabled' : 'disabled'}.',
            ),
          ],
        );
      },
    );

    // -- toggle_slow_animations -----------------------------------------------
    server.registerTool(
      'toggle_slow_animations',
      description:
          'Slows all animations to 1/5 speed (timeDilation=5) or restores '
          'normal speed (timeDilation=1). Use this to visually inspect animation '
          'curves, catch jank frames, or verify transition correctness. '
          'Set enabled=false to restore normal speed.',
      inputSchema: ToolInputSchema(
        properties: {
          'enabled': JsonSchema.boolean(
            description:
                'true to slow animations to 1/5 speed (timeDilation=5), false to restore normal speed.',
          ),
        },
        required: ['enabled'],
      ),
      callback: (params, extra) async {
        final enabled = params['enabled'] as bool? ?? true;
        final dilation = enabled ? '5.0' : '1.0';
        final res = await _callExtensionRaw('ext.flutter.timeDilation', {
          'timeDilation': dilation,
        });
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: enabled
                  ? 'Animations slowed to 1/5 speed. Call again with enabled=false to restore.'
                  : 'Animations restored to normal speed.',
            ),
          ],
        );
      },
    );

    // -- enable_widget_rebuild_tracking ---------------------------------------
    server.registerTool(
      'enable_widget_rebuild_tracking',
      description:
          'Enables or disables per-widget rebuild counting '
          '(equivalent to DevTools "Track Widget Builds"). '
          'After enabling, interact with the app, then call get_debug_logs '
          'to see rebuild events, or check the performance overlay via '
          'get_perf_metrics. Set enabled=false to stop tracking.',
      inputSchema: ToolInputSchema(
        properties: {
          'enabled': JsonSchema.boolean(
            description:
                'true to start tracking per-widget rebuild counts, false to stop.',
          ),
        },
        required: ['enabled'],
      ),
      callback: (params, extra) async {
        final enabled = params['enabled'] as bool? ?? true;
        final res = await _callExtensionRaw('ext.flutter.profileWidgetBuilds', {
          'enabled': enabled.toString(),
        });
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Widget rebuild tracking ${enabled ? 'enabled' : 'disabled'}. '
                  '${enabled ? 'Interact with the app, then use get_debug_logs or capture_screenshot to observe rebuild activity.' : ''}',
            ),
          ],
        );
      },
    );

    // -- get_gc_stats ---------------------------------------------------------
    server.registerTool(
      'get_gc_stats',
      description:
          'Returns garbage collection statistics for all Dart isolates: '
          'number of GC rounds, total bytes collected, and current heap pressure. '
          'High GC frequency (>5/sec) can cause jank.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (params, extra) async {
        if (_vmService == null) {
          return CallToolResult(
            content: [TextContent(text: 'No VM Service connection.')],
          );
        }
        try {
          final vm = await _vmService!.getVM();
          final buf = StringBuffer('GC statistics:\n');
          for (final iso in vm.isolates ?? []) {
            if (iso.id == null) continue;
            try {
              final profile = await _vmService!.getAllocationProfile(
                iso.id!,
                gc: false,
              );
              final newSpace = profile.memoryUsage;
              if (newSpace != null) {
                final used = ((newSpace.heapUsage ?? 0) / (1024 * 1024))
                    .toStringAsFixed(2);
                final cap = ((newSpace.heapCapacity ?? 0) / (1024 * 1024))
                    .toStringAsFixed(2);
                buf.writeln('  ${iso.name ?? iso.id}: heap=$used/$cap MB');
              }
            } catch (e) {
              _log.fine('Failed to query isolate: $e');
            }
          }
          buf.writeln(
            '\nTip: use get_allocation_profile to see which classes are '
            'consuming heap, or get_memory_details for a live snapshot.',
          );
          return CallToolResult(content: [TextContent(text: buf.toString())]);
        } catch (e) {
          return CallToolResult(
            content: [TextContent(text: 'GC stats failed: $e')],
            isError: true,
          );
        }
      },
    );
  }
}
