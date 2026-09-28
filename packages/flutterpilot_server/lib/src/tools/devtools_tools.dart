part of '../../flutterpilot_server.dart';

/// DevTools-equivalent deep inspection tools that use the VM Service Protocol.
mixin _DevtoolsToolsMixin on _FlutterPilotServerBase {
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
