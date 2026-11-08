part of '../../fp_server.dart';

/// Integration tests from what the agent did (ROADMAP §6): record from a
/// fresh start, write the test, run it, and only call it done if it passes.
mixin _TestGenerationToolsMixin
    on _FlutterPilotServerBase, _DevtoolsToolsMixin {
  void _registerTestGenerationTools() {
    _tool(
      'locate_source_ast',
      description:
          'Locates widget constructor call in source code (file:line, code '
          'snippet, named arguments, start/end file offsets).',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key, selector or visible text of the widget.',
          ),
          'file': JsonSchema.string(
            description: 'File in the app, e.g. "lib/ui/tile.dart".',
          ),
          'line': JsonSchema.integer(description: '1-based line, with file.'),
          'column': JsonSchema.integer(
            description: '1-based column where the call starts, with file.',
          ),
        },
      ),
      callback: (p, e) async {
        CallToolResult fail(String s) =>
            CallToolResult(isError: true, content: [TextContent(text: s)]);
        var file = p['file']?.toString();
        var line = (p['line'] as num?)?.toInt();
        var column = (p['column'] as num?)?.toInt();
        String? type;
        var isStaticFallback = false;
        if (file == null) {
          if (p['key'] == null) return fail('Give key, or file and line.');
          final keyStr = p['key'].toString();
          final res = await _callExtensionRaw(
            'ext.flutterpilot.inspectWidget',
            {'key': keyStr},
          );
          final source = !res.isError && res.data?['source'] is Map
              ? res.data!['source'] as Map
              : null;
          final loc = source?['loc']?.toString();
          final m = loc == null
              ? null
              : RegExp(r'^(.*):(\d+):(\d+)$').firstMatch(loc);
          if (m != null) {
            type = source?['type']?.toString();
            file = m[1]!;
            line = int.parse(m[2]!);
            column = int.parse(m[3]!);
          } else {
            // Live widget not mounted in current viewport / tree:
            // Fall back to scanning the app's lib/ directory statically.
            final vm = (await _deviceContextForParameters(const {}))?.service;
            final isolateId = vm == null ? null : await _uiIsolateId(vm, null);
            final root = isolateId == null
                ? null
                : (await _appEntrypoint(vm!, isolateId))?.root;
            final appRoot = root ?? Directory.current.path;
            final searchDir = Directory(path_pkg.join(appRoot, 'lib'));
            final match =
                await findWidgetConstructorInProject(searchDir, keyStr);
            if (match != null) {
              file = path_pkg.relative(match.file, from: appRoot);
              line = match.line;
              column = match.column;
              type = match.type;
              isStaticFallback = true;
            } else {
              if (res.isError) return res.toCallToolResult();
              return fail(
                'No source location for "$keyStr": it is not created by '
                "the app's code, or this is not a debug build.",
              );
            }
          }
        }
        if (line == null) return fail('Give line with file.');

        // Locations are relative to the app's folder, not the server's.
        var path = file;
        if (path.startsWith('file://')) path = Uri.parse(path).toFilePath();
        if (!path_pkg.isAbsolute(path)) {
          final vm = (await _deviceContextForParameters(const {}))?.service;
          final isolateId = vm == null ? null : await _uiIsolateId(vm, null);
          final root = isolateId == null
              ? null
              : (await _appEntrypoint(vm!, isolateId))?.root;
          path = path_pkg.join(root ?? Directory.current.path, path);
        }
        final f = File(path);
        if (!f.existsSync()) return fail('Not found on disk: $path');
        final text = f.readAsStringSync();
        final span = constructorSpanAt(text, line, column ?? 1);
        if (span == null) {
          return fail(
            'No widget constructor call starts at $file:$line:${column ?? 1}'
            '${column == null ? ' (give the column where it starts)' : ''}.',
          );
        }
        var snippet = text.substring(span.offset, span.end);
        final lines = snippet.split('\n');
        final cut = lines.length > 80;
        if (cut) snippet = '${lines.take(80).join('\n')}\n…';
        final endLine = line + lines.length - 1;
        final args = span.namedArgs.isEmpty
            ? 'none'
            : span.namedArgs.join(', ');
        return CallToolResult(
          content: [
            TextContent(
              text:
                  '${type ?? 'Call'} at $file:$line-$endLine '
                  '(offset ${span.offset}–${span.end}). Named arguments: '
                  '$args.${cut ? ' Showing 80 of ${lines.length} lines.' : ''}'
                  '${isStaticFallback ? ' (resolved via offline AST fallback: unmounted/off-screen)' : ''}'
                  '\n```dart\n$snippet\n```',
            ),
          ],
          structuredContent: {
            'file': file,
            'line': line,
            'endLine': endLine,
            'offset': span.offset,
            'end': span.end,
            'namedArgs': span.namedArgs,
            'widget': ?type,
          },
        );
      },
    );

    _tool(
      'apply_patch_and_verify',
      description:
          'Surgically patches widget in source (wrap, unwrap, replaceCall), '
          'hot-reloads, audits health, and auto-rolls back if reload fails.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key, selector or visible text of the widget.',
          ),
          'file': JsonSchema.string(
            description: 'File in the app, e.g. "lib/main.dart".',
          ),
          'line': JsonSchema.integer(
            description: '1-based line of the widget.',
          ),
          'column': JsonSchema.integer(
            description: '1-based column where the call starts.',
          ),
          'wrapWith': JsonSchema.string(
            description:
                'Widget to wrap target in (e.g. "Expanded", "SingleChildScrollView", "SafeArea", "Padding").',
          ),
          'unwrap': JsonSchema.boolean(
            description:
                'Remove this widget, replacing it with its child argument.',
          ),
          'replaceCall': JsonSchema.string(
            description: 'Direct replacement snippet for the constructor call.',
          ),
          'waitFor': JsonSchema.string(
            description:
                'Optional widget key to wait for on screen after reload.',
          ),
          'patches': JsonSchema.array(
            description:
                'Batch of patch objects to apply atomically in 1 reload.',
          ),
        },
      ),
      callback: (p, e) async {
        CallToolResult fail(String s) =>
            CallToolResult(isError: true, content: [TextContent(text: s)]);

        Future<({_ResolvedPatch? patch, String? error})> resolveOne(
          Map<String, dynamic> item,
        ) async {
          var file = item['file']?.toString();
          var line = (item['line'] as num?)?.toInt();
          var column = (item['column'] as num?)?.toInt();
          String? type;
          var isStaticFallback = false;

          if (file == null) {
            if (item['key'] == null) {
              return (patch: null, error: 'Give key, or file and line.');
            }
            final keyStr = item['key'].toString();
            final res = await _callExtensionRaw(
              'ext.flutterpilot.inspectWidget',
              {'key': keyStr},
            );
            final source = !res.isError && res.data?['source'] is Map
                ? res.data!['source'] as Map
                : null;
            final loc = source?['loc']?.toString();
            final m = loc == null
                ? null
                : RegExp(r'^(.*):(\d+):(\d+)$').firstMatch(loc);
            if (m != null) {
              type = source?['type']?.toString();
              file = m[1]!;
              line = int.parse(m[2]!);
              column = int.parse(m[3]!);
            } else {
              final vm = (await _deviceContextForParameters(const {}))?.service;
              final isolateId =
                  vm == null ? null : await _uiIsolateId(vm, null);
              final root = isolateId == null
                  ? null
                  : (await _appEntrypoint(vm!, isolateId))?.root;
              final appRoot = root ?? Directory.current.path;
              final searchDir = Directory(path_pkg.join(appRoot, 'lib'));
              final match =
                  await findWidgetConstructorInProject(searchDir, keyStr);
              if (match != null) {
                file = path_pkg.relative(match.file, from: appRoot);
                line = match.line;
                column = match.column;
                type = match.type;
                isStaticFallback = true;
              } else {
                if (res.isError) {
                  return (patch: null, error: res.data?['error']?.toString() ?? 'Widget inspection failed');
                }
                return (
                  patch: null,
                  error: 'No source location for "$keyStr": not found in live tree or offline AST.',
                );
              }
            }
          }
          if (line == null) {
            return (patch: null, error: 'Give line with file ($file).');
          }

          var path = file;
          if (path.startsWith('file://')) path = Uri.parse(path).toFilePath();
          if (!path_pkg.isAbsolute(path)) {
            final vm = (await _deviceContextForParameters(const {}))?.service;
            final isolateId = vm == null ? null : await _uiIsolateId(vm, null);
            final root = isolateId == null
                ? null
                : (await _appEntrypoint(vm!, isolateId))?.root;
            path = path_pkg.join(root ?? Directory.current.path, path);
          }
          final f = File(path);
          if (!f.existsSync()) {
            return (patch: null, error: 'Not found on disk: $path');
          }
          final text = f.readAsStringSync();
          final span = constructorSpanAt(text, line, column ?? 1);
          if (span == null) {
            return (
              patch: null,
              error: 'No widget constructor call starts at $file:$line:${column ?? 1}.',
            );
          }

          final originalCall = text.substring(span.offset, span.end);
          String newCall;
          int patchOffset = span.offset;
          int patchEnd = span.end;

          if (item['replaceCall'] != null) {
            newCall = item['replaceCall'].toString();
          } else if (item['unwrap'] == true) {
            final parent = enclosingConstructorSpan(
              text,
              span.offset,
              span.end,
              hintLine: line,
            );
            if (parent != null &&
                text
                    .substring(parent.offset, span.offset)
                    .contains(RegExp(r'\bchild\s*:'))) {
              patchOffset = parent.offset;
              patchEnd = parent.end;
              newCall = originalCall;
            } else {
              final childMatch =
                  RegExp(r'\bchild\s*:\s*').firstMatch(originalCall);
              if (childMatch != null) {
                var depth = 0;
                var startIdx = childMatch.end;
                var endIdx = originalCall.length - 1;
                for (var i = startIdx; i < originalCall.length; i++) {
                  final c = originalCall[i];
                  if (c == '(' || c == '[' || c == '{') {
                    depth++;
                  } else if (c == ')' || c == ']' || c == '}') {
                    if (depth == 0) {
                      endIdx = i;
                      break;
                    }
                    depth--;
                  } else if (depth == 0 && c == ',') {
                    endIdx = i;
                    break;
                  }
                }
                newCall = originalCall.substring(startIdx, endIdx).trim();
              } else {
                return (
                  patch: null,
                  error: 'Cannot unwrap ${type ?? 'widget'}: no child parameter found.',
                );
              }
            }
          } else if (item['wrapWith'] != null) {
            final wrapper = item['wrapWith'].toString().trim();
            if (wrapper == 'Padding') {
              newCall =
                  'Padding(\n  padding: const EdgeInsets.all(16.0),\n  child: $originalCall,\n)';
            } else if (wrapper.contains('(')) {
              final lastParen = wrapper.lastIndexOf(')');
              if (lastParen > 0) {
                final prefix = wrapper.substring(0, lastParen).trim();
                final hasArgs = prefix.contains(RegExp(r'\(\s*\S'));
                final separator = hasArgs ? ', ' : '';
                newCall = '$prefix$separator child: $originalCall\n)';
              } else {
                newCall = '$wrapper(\n  child: $originalCall,\n)';
              }
            } else {
              newCall = '$wrapper(\n  child: $originalCall,\n)';
            }
          } else {
            return (
              patch: null,
              error: 'Specify wrapWith, unwrap, or replaceCall.',
            );
          }

          return (
            patch: _ResolvedPatch(
              file: file,
              filePath: path,
              line: line,
              column: column ?? 1,
              originalCall: originalCall,
              newCall: newCall,
              patchOffset: patchOffset,
              patchEnd: patchEnd,
              isStaticFallback: isStaticFallback,
            ),
            error: null,
          );
        }

        final List<Map<String, dynamic>> patchList = p['patches'] is List
            ? (p['patches'] as List)
                .whereType<Map>()
                .map((m) => m.cast<String, dynamic>())
                .toList()
            : [p];
        if (patchList.isEmpty) return fail('No patches specified.');

        final resolved = <_ResolvedPatch>[];
        for (final item in patchList) {
          final res = await resolveOne(item);
          if (res.error != null) return fail(res.error!);
          resolved.add(res.patch!);
        }

        final filePatches = <String, List<_ResolvedPatch>>{};
        for (final r in resolved) {
          filePatches.putIfAbsent(r.filePath, () => []).add(r);
        }

        final originalFiles = <String, String>{};
        for (final path in filePatches.keys) {
          originalFiles[path] = File(path).readAsStringSync();
        }

        for (final entry in filePatches.entries) {
          final path = entry.key;
          final patches = entry.value;
          patches.sort((a, b) => b.patchOffset.compareTo(a.patchOffset));

          var content = originalFiles[path]!;
          for (final patch in patches) {
            content = content.substring(0, patch.patchOffset) +
                patch.newCall +
                content.substring(patch.patchEnd);
          }
          File(path).writeAsStringSync(content);
          try {
            await Process.run('dart', ['format', path]);
          } catch (_) {}
        }

        final reload = _toolCallbacks['hot_reload'];
        final reloadRes = reload != null
            ? await reload(const {}, e)
            : CallToolResult(content: [TextContent(text: 'Reload skipped')]);
        final reloadFailed = reloadRes.isError == true;

        if (reloadFailed) {
          for (final entry in originalFiles.entries) {
            File(entry.key).writeAsStringSync(entry.value);
            try {
              await Process.run('dart', ['format', entry.key]);
            } catch (_) {}
          }
          if (reload != null) await reload(const {}, e);
          final err = reloadRes.content
              .whereType<TextContent>()
              .map((c) => c.text)
              .join('\n');
          return fail(
            'Hot reload failed after applying patch:\n$err\n'
            'Rolled back changes across ${originalFiles.length} file(s).',
          );
        }

        await Future<void>.delayed(const Duration(milliseconds: 150));
        final audit =
            await _callExtensionRaw('ext.flutterpilot.auditScreenHealth', {});
        final auditData = audit.data ?? const <String, dynamic>{};
        final overflows = (auditData['overflows'] as List?) ?? const [];
        final a11y = (auditData['accessibilityIssues'] as List?) ?? const [];

        final buf = StringBuffer();
        if (resolved.length == 1) {
          final single = resolved.first;
          buf.writeln(
            '✓ Patched ${single.file}:${single.line} via hot reload'
            '${single.isStaticFallback ? ' (resolved via offline AST)' : ''}:',
          );
          buf.writeln(
            '```dart\n// Replaced:\n${single.originalCall}\n\n// With:\n${single.newCall}\n```',
          );
        } else {
          buf.writeln(
            '✓ Applied ${resolved.length} patches atomically across ${originalFiles.length} file(s) via 1 hot reload:',
          );
          for (var i = 0; i < resolved.length; i++) {
            final r = resolved[i];
            buf.writeln('  ${i + 1}. ${r.file}:${r.line} (${r.newCall.split('\n').first})');
          }
        }
        buf.writeln('Post-reload screen health:');
        buf.writeln('  • Overflows: ${overflows.length}');
        buf.writeln('  • Accessibility issues: ${a11y.length}');

        final waitFor = p['waitFor']?.toString();
        if (waitFor != null && waitFor.isNotEmpty) {
          final waitRes = await _callExtensionRaw(
            'ext.flutterpilot.waitForWidget',
            {
              'key': waitFor,
              'timeoutMs': '3000',
            },
          );
          if (waitRes.isError) {
            buf.writeln(
              '✗ Expected widget "$waitFor" was not found: ${waitRes.errorMessage}',
            );
          } else {
            buf.writeln('✓ Expected widget "$waitFor" is visible.');
          }
        }

        return CallToolResult(
          content: [TextContent(text: buf.toString().trim())],
          structuredContent: {
            'patchCount': resolved.length,
            'fileCount': originalFiles.length,
            'reloaded': true,
            'overflowCount': overflows.length,
            'accessibilityIssueCount': a11y.length,
            'health': auditData,
          },
        );
      },
    );

    _tool(
      'replay_flow',
      description:
          'Replays recorded user interactions live on the connected app '
          'without writing a test binary.',
      inputSchema: ToolInputSchema(
        properties: {
          'delayMs': JsonSchema.integer(
            description: 'Delay between steps in ms (default: 300).',
          ),
          'assertRoute': JsonSchema.string(
            description: 'Assert that the flow ends on this route.',
          ),
          'assertWidget': JsonSchema.string(
            description: 'Assert that this widget key/text is visible after replay.',
          ),
        },
      ),
      callback: (p, e) async {
        CallToolResult fail(String s) =>
            CallToolResult(isError: true, content: [TextContent(text: s)]);

        final recRes = await _callExtensionRaw(
          'ext.flutterpilot.testRecording',
          {'action': 'read'},
        );
        if (recRes.isError) return recRes.toCallToolResult();
        final rawSteps = (recRes.data?['steps'] as List? ?? const []);
        final steps = [
          for (final s in rawSteps)
            if (s is Map) s.cast<String, dynamic>(),
        ];

        if (steps.isEmpty) {
          return fail(
            'No recorded steps to replay. Call generate_test(start: true) and '
            'interact with the app first.',
          );
        }

        final delay = (p['delayMs'] as num?)?.toInt() ?? 300;
        final assertRoute = p['assertRoute']?.toString();

        var replayedCount = 0;
        for (final step in steps) {
          final type = step['type']?.toString();
          if (type == 'tap' || type == 'tapAt') {
            final key = step['key']?.toString();
            final text = step['text']?.toString();
            if (key != null) {
              await _callExtensionRaw(
                'ext.flutterpilot.tapWidget',
                {'key': key},
              );
            } else if (text != null) {
              await _callExtensionRaw(
                'ext.flutterpilot.tapWidget',
                {'text': text},
              );
            } else if (step['x'] != null && step['y'] != null) {
              await _callExtensionRaw('ext.flutterpilot.tapWidget', {
                'x': step['x'].toString(),
                'y': step['y'].toString(),
              });
            }
          } else if (type == 'enterText') {
            final key = step['key']?.toString();
            final input = step['text']?.toString() ?? '';
            await _callExtensionRaw('ext.flutterpilot.enterText', {
              'key': ?key,
              'text': input,
            });
          } else if (type == 'scrollTo') {
            final key = step['key']?.toString();
            if (key != null) {
              await _callExtensionRaw(
                'ext.flutterpilot.scrollIntoView',
                {'key': key},
              );
            }
          }
          replayedCount++;
          if (delay > 0) {
            await Future<void>.delayed(Duration(milliseconds: delay));
          }
        }

        await _callExtensionRaw(
          'ext.flutterpilot.waitForAnimation',
          {'timeoutMs': '1000'},
        );

        final navRes =
            await _callExtensionRaw('ext.flutterpilot.getNavigationStack', {});
        final currentRoute = navRes.data?['current']?.toString() ??
            (navRes.data?['stack'] as List?)?.lastOrNull?.toString() ??
            '/';

        final healthRes =
            await _callExtensionRaw('ext.flutterpilot.auditScreenHealth', {});
        final health = healthRes.data ?? const <String, dynamic>{};
        final overflows = (health['overflowCount'] as num?)?.toInt() ?? 0;

        final routeMatches = assertRoute == null || currentRoute == assertRoute;
        final isClean = overflows == 0 && routeMatches;

        final buf =
            StringBuffer('Replayed $replayedCount step(s) in active app:\n');
        buf.writeln(
          '- Final Route: $currentRoute${assertRoute != null ? ' (expected: $assertRoute)' : ''}',
        );
        buf.writeln('- Overflows: $overflows');
        if (!routeMatches) {
          buf.writeln(
            '✗ Route mismatch: expected "$assertRoute" but ended on "$currentRoute".',
          );
        }
        if (overflows > 0) {
          buf.writeln('✗ Screen has $overflows layout overflow(s).');
        }
        if (isClean) {
          buf.writeln('✓ Flow completed successfully with clean screen health.');
        }

        final assertWidget = p['assertWidget']?.toString();
        if (assertWidget != null && assertWidget.isNotEmpty) {
          final waitRes = await _callExtensionRaw(
            'ext.flutterpilot.waitForWidget',
            {
              'key': assertWidget,
              'timeoutMs': '3000',
            },
          );
          if (waitRes.isError) {
            return fail(
              'Replayed $replayedCount step(s), but expected widget "$assertWidget" '
              'was not visible: ${waitRes.errorMessage}',
            );
          }
          buf.writeln('✓ Expected widget "$assertWidget" is visible.');
        }

        return CallToolResult(
          isError: !isClean,
          content: [TextContent(text: buf.toString().trim())],
          structuredContent: {
            'replayedSteps': replayedCount,
            'finalRoute': currentRoute,
            'overflowCount': overflows,
            'routeMatches': routeMatches,
            'isClean': isClean,
          },
        );
      },
    );

    _tool(
      'generate_test',
      description:
          'Records user interactions and writes executable integration_test '
          'files (start:true begins recording; name writes and runs test).',
      inputSchema: ToolInputSchema(
        properties: {
          'start': JsonSchema.boolean(),
          'fromCrash': JsonSchema.boolean(
            description: 'Write repro test from recent crash.',
          ),
          'name': JsonSchema.string(description: 'Letters, digits and _.'),
          'run': JsonSchema.boolean(
            description: 'Run the written test (default true).',
          ),
        },
      ),
      callback: (params, extra) async {
        CallToolResult text(String s, {bool error = false}) => CallToolResult(
          isError: error,
          content: [TextContent(text: s)],
        );
        if (params['start'] == true) return _startTestRecording(extra);
        final name = params['name']?.toString() ?? '';
        if (params['fromCrash'] == true) {
          final testName = name.isEmpty ? 'repro_crash' : name;
          return _generateCrashReproTest(testName);
        }
        if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
          return text(
            'Pass start:true to begin recording, fromCrash:true to repro crash, '
            'or name: in lower_snake_case (e.g. "login_flow") to write and run it.',
            error: true,
          );
        }
        return _writeAndRunTest(name, run: params['run'] != false);
      },
    );

    _tool(
      'synthesize_golden_test',
      description:
          'Writes and runs golden widget tests for a screen across phone, '
          'tablet, and desktop viewports.',
      inputSchema: ToolInputSchema(
        properties: {
          'screen': JsonSchema.string(
            description: 'Class ("FeedScreen") or call ("StoryScreen(id: 1)").',
          ),
          'name': JsonSchema.string(
            description: 'lower_snake_case (default from screen).',
          ),
          'viewports': JsonSchema.array(
            items: JsonSchema.string(
              enumValues: ['phone', 'tablet', 'desktop'],
            ),
            description: 'Default all three.',
          ),
          'run': JsonSchema.boolean(description: 'Default true.'),
        },
        required: ['screen'],
      ),
      callback: (p, e) async {
        CallToolResult fail(String s) =>
            CallToolResult(isError: true, content: [TextContent(text: s)]);
        final screen = '${p['screen'] ?? ''}'.trim();
        final className = RegExp(r'^[A-Za-z_]\w*').stringMatch(screen);
        if (className == null) {
          return fail('screen must be a class name or a constructor call.');
        }
        final name =
            p['name']?.toString() ??
            className
                .replaceAllMapped(
                  RegExp(r'(?<=[a-z0-9])([A-Z])'),
                  (m) => '_${m[1]}',
                )
                .toLowerCase();
        if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
          return fail('name must be lower_snake_case.');
        }
        final sizes = {
          'phone': (390, 844),
          'tablet': (768, 1024),
          'desktop': (1280, 800),
        };
        final viewports = [
          for (final v in (p['viewports'] as List?) ?? sizes.keys)
            if (sizes.containsKey(v)) '$v',
        ];

        final vm = (await _deviceContextForParameters(const {}))?.service;
        final isolateId = vm == null ? null : await _uiIsolateId(vm, null);
        final app = isolateId == null
            ? null
            : await _appEntrypoint(vm!, isolateId);
        if (app == null) return fail('No running app to write the test in.');
        final package = RegExp(
          r'^package:([^/]+)/',
        ).firstMatch(app.mainImport)?[1];
        final declaring = findClassFile(
          Directory('${app.root}/lib'),
          className,
        );
        if (package == null || declaring == null) {
          return fail('No "class $className" in ${app.root}/lib.');
        }
        final import =
            'package:$package/${path_pkg.relative(declaring.path, from: '${app.root}/lib').replaceAll(r'\', '/')}';
        final pubspec = File('${app.root}/pubspec.yaml');
        final riverpod =
            pubspec.existsSync() &&
            RegExp(
              r'^\s+(flutter_riverpod|hooks_riverpod):',
              multiLine: true,
            ).hasMatch(pubspec.readAsStringSync());
        final code = goldenTestSource(
          name: name,
          import: import,
          widget: screen.contains('(') ? screen : '$className()',
          viewports: {for (final v in viewports) v: sizes[v]!},
          riverpod: riverpod,
        );
        final relative = 'test/${name}_golden_test.dart';
        final file = File('${app.root}/$relative')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(code);
        await runProgram(['dart', 'format', file.path]);
        if (p['run'] == false) {
          return CallToolResult(
            content: [
              TextContent(
                text:
                    'Wrote $relative. Make the images: flutter test '
                    '$relative --update-goldens',
              ),
            ],
          );
        }
        final ProcessResult result;
        try {
          result = await Process.run(
            'flutter',
            ['test', relative, '--update-goldens'],
            workingDirectory: app.root,
            runInShell: Platform.isWindows,
          ).timeout(const Duration(minutes: 10));
        } on TimeoutException {
          return fail('Wrote $relative; running it took over 10 minutes.');
        }
        final images = [
          for (final v in viewports)
            if (File('${app.root}/test/goldens/${name}_$v.png').existsSync())
              '${app.root}/test/goldens/${name}_$v.png',
        ];
        if (result.exitCode != 0) {
          final output = '${result.stdout}\n${result.stderr}'.trim();
          final tail = output.split('\n');
          return fail(
            'Wrote $relative, but it fails (often: the screen needs '
            'arguments, providers or a router the test does not give it — '
            'edit the test):\n'
            '${tail.skip(tail.length > 40 ? tail.length - 40 : 0).join('\n')}',
          );
        }
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Wrote $relative and its images (look at them before '
                  'committing):\n${images.join('\n')}\nIn a widget test '
                  'requests fail, text is drawn as boxes (the test font) and '
                  'the theme is the default one, not the app\'s: edit the '
                  'test to give it mocks, fonts or the theme. Check later: '
                  'flutter test $relative (fails when the screen changes).',
            ),
          ],
          structuredContent: {'file': relative, 'images': images},
        );
      },
    );
  }

  Future<CallToolResult> _startTestRecording(RequestHandlerExtra? extra) async {
    CallToolResult fail(String s) =>
        CallToolResult(isError: true, content: [TextContent(text: s)]);
    // The test starts the app from main(): so does the recording.
    final restart = _toolCallbacks['hot_reload'];
    if (restart != null && extra != null) {
      final res = await restart({'restart': true}, extra);
      if (res.isError == true) {
        return fail(
          'Could not restart the app to record from its start: '
          '${res.content.whereType<TextContent>().map((c) => c.text).join(' ')}',
        );
      }
    }
    // The restarted app registers its extensions again in a moment.
    _ExtensionResult? res;
    for (var i = 0; i < 20; i++) {
      res = await _callExtensionRaw('ext.flutterpilot.testRecording', {
        'action': 'start',
      });
      if (!res.isError) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (res == null || res.isError) {
      return fail(
        'The app did not start recording (does it use fp_sdk?): '
        '${res?.errorMessage}',
      );
    }
    _recordingTest = true;
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Recording from a fresh start of the app. Act and check as '
              'usual (tap_widget, enter_text, assert_widget, wait_for, '
              'mock_http_response…); then generate_test(name: "…") writes '
              'and runs the test. A hot restart before then loses the '
              'recording.',
        ),
      ],
    );
  }

  /// Writes the steps the app recorded before its latest error as an
  /// integration test, runs it, and says whether it fails with that error:
  /// reproduced means the test is a regression test that passes once fixed.
  Future<CallToolResult> _generateCrashReproTest(String name) async {
    CallToolResult fail(String s) =>
        CallToolResult(isError: true, content: [TextContent(text: s)]);
    final res = await _callExtensionRaw('ext.flutterpilot.getErrors', {});
    if (res.isError) return res.toCallToolResult();
    final errors = [
      for (final e in (res.data?['errors'] as List? ?? const []))
        if (e is Map && (e['recentInteractions'] as List?)?.isNotEmpty == true)
          e,
    ];
    if (errors.isEmpty) {
      return fail(
        'No error with recorded steps before it. The app records the last 20 '
        'taps, text entries and keys FlutterPilot made; an error raised '
        'before any (at startup), or after a restart cleared them, has none.',
      );
    }
    final error = errors.last;
    final message = '${error['exception'] ?? ''}'.split('\n').first.trim();
    final recent = (error['recentInteractions'] as List).cast<Map>();
    final steps = [
      for (final r in recent)
        if (r['type'] != null)
          {
            for (final MapEntry(:key, :value) in r.entries)
              if (key != 'timestamp') '$key': value,
          },
    ];
    final out = await _writeAndRunSteps(name, steps, const [], run: true);
    final output = out.output;
    if (output == null) return out.result;
    final notes = [
      for (final c in out.result.content)
        if (c is TextContent) c.text,
    ].join('\n');
    final probe = message.length > 60 ? message.substring(0, 60) : message;
    final reproduced = out.result.isError == true && output.contains(probe);
    final full = recent.length >= 20
        ? ' Only the last 20 steps were kept, so earlier ones are missing.'
        : '';
    return CallToolResult(
      isError: !reproduced,
      content: [
        TextContent(
          text: reproduced
              ? 'Reproduced "$message": integration_test/${name}_test.dart '
                    'fails with it. Keep it as the regression test; it passes '
                    'once the bug is fixed.\n$notes'
              : 'NOT reproduced "$message" by replaying ${steps.length} '
                    'step(s).$full What the steps do not carry: settings set '
                    'with set_app_settings (text scale, window size, theme), '
                    'mocks, and the data the app had. Edit the test to set '
                    'those up, or record the flow with generate_test(start: '
                    'true).\n$notes',
        ),
      ],
      structuredContent: {
        'reproduced': reproduced,
        'error': message,
        'steps': steps.length,
      },
    );
  }

  Future<CallToolResult> _writeAndRunTest(
    String name, {
    required bool run,
  }) async {
    CallToolResult fail(String s) =>
        CallToolResult(isError: true, content: [TextContent(text: s)]);
    final res = await _callExtensionRaw('ext.flutterpilot.testRecording', {
      'action': 'stop',
    });
    if (res.isError) return res.toCallToolResult();
    final wasRecording = _recordingTest;
    _recordingTest = false;
    final data = res.data!;
    final steps = [
      for (final s in (data['steps'] as List? ?? const []))
        (s as Map).cast<String, dynamic>(),
    ];
    final secrets = (data['secrets'] as List? ?? const []).cast<String>();
    if (steps.isEmpty) {
      return fail(
        wasRecording
            ? 'Nothing was recorded: the app restarted since '
                  'generate_test(start: true), or nothing was done. Start '
                  'again.'
            : 'Not recording: call generate_test(start: true) first, then '
                  'do the flow.',
      );
    }

    return (await _writeAndRunSteps(name, steps, secrets, run: run)).result;
  }

  /// Writes [steps] as integration_test/[name]_test.dart in the app and, when
  /// [run], runs it on a matching device. [output] is the test run's output,
  /// null when it did not run.
  Future<({CallToolResult result, String? output})> _writeAndRunSteps(
    String name,
    List<Map<String, dynamic>> steps,
    List<String> secrets, {
    required bool run,
  }) async {
    ({CallToolResult result, String? output}) fail(String s) => (
      result: CallToolResult(isError: true, content: [TextContent(text: s)]),
      output: null,
    );
    ({CallToolResult result, String? output}) done(List<String> notes) => (
      result: CallToolResult(content: [TextContent(text: notes.join('\n'))]),
      output: null,
    );
    final context = await _deviceContextForParameters(const {});
    final vm = context?.service;
    if (vm == null) return fail('No running app.');
    final isolateId = await _uiIsolateId(vm, null);
    if (isolateId == null) return fail('No UI isolate.');
    final app = await _appEntrypoint(vm, isolateId);
    if (app == null) {
      return fail(
        "Could not tell the app's folder and entrypoint from its root "
        'library.',
      );
    }

    final test = writeIntegrationTest(
      name: name,
      mainImport: app.mainImport,
      steps: steps,
    );
    final file = File('${app.root}/integration_test/${name}_test.dart');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(test.source);
    await runProgram(['dart', 'format', file.path]);
    final formatted = file.readAsStringSync();
    final relative = 'integration_test/${name}_test.dart';

    final notes = <String>[
      'Wrote $relative (${steps.length} steps).',
      if (test.skipped.isNotEmpty)
        'Not replayed (no test equivalent): ${test.skipped.join('; ')}.',
      if (test.unstable.isNotEmpty)
        'Found by position, so fragile: ${test.unstable.join('; ')} '
            '(a Key on those widgets makes the test stable).',
    ];
    final added = await _ensureIntegrationTestDependency(app.root);
    if (added != null) notes.add(added);
    if (!run) return done(notes);

    final device = await _testDevice(context!.operatingSystem);
    if (device == null) {
      notes.add(
        'Not run: integration tests need a desktop, simulator or emulator '
        'target (this app runs on ${context.operatingSystem}).',
      );
      return done(notes);
    }
    final started = DateTime.now();
    // Obscured text goes in a file only this user can read, not on the
    // command line where any process list shows it (security review).
    Directory? secretDir;
    File? secretFile;
    if (secrets.isNotEmpty) {
      secretDir = Directory.systemTemp.createTempSync('fp_secrets_');
      secretFile = File('${secretDir.path}/defines.json')
        ..writeAsStringSync(
          jsonEncode({
            for (var i = 0; i < secrets.length; i++)
              'FP_SECRET_${i + 1}': secrets[i],
          }),
        );
      if (!Platform.isWindows) {
        await Process.run('chmod', ['700', secretDir.path]);
        await Process.run('chmod', ['600', secretFile.path]);
      }
    }
    final ProcessResult result;
    try {
      result = await Process.run(
        'flutter',
        [
          'test',
          relative,
          '-d',
          device,
          if (secretFile != null) '--dart-define-from-file=${secretFile.path}',
        ],
        workingDirectory: app.root,
        runInShell: Platform.isWindows,
      ).timeout(const Duration(minutes: 15));
    } on TimeoutException {
      return fail('${notes.join('\n')}\nThe test run took over 15 minutes.');
    } finally {
      try {
        secretDir?.deleteSync(recursive: true);
      } catch (_) {}
    }
    final seconds = DateTime.now().difference(started).inSeconds;
    final output = '${result.stdout}\n${result.stderr}';
    final passed = result.exitCode == 0;
    notes.add(
      passed
          ? 'Ran it on $device: passed ($seconds s).'
          : 'Ran it on $device: FAILED ($seconds s). Fix the test (or the '
                'app) and run: flutter test $relative -d $device\n'
                '${describeTestFailure(output, formatted, '${name}_test.dart')}',
    );
    if (context.operatingSystem != 'macos' &&
        context.operatingSystem != 'linux' &&
        context.operatingSystem != 'windows') {
      notes.add(
        'The test installed its own build of the app on the device: start '
        'the app again (flutter run) to keep driving it.',
      );
    }
    return (
      result: CallToolResult(
        isError: !passed,
        content: [TextContent(text: notes.join('\n'))],
      ),
      output: output,
    );
  }

  /// Adds `integration_test` to dev_dependencies when missing; says so.
  Future<String?> _ensureIntegrationTestDependency(String root) async {
    final pubspec = File('$root/pubspec.yaml').readAsStringSync();
    if (RegExp(r'^\s+integration_test:', multiLine: true).hasMatch(pubspec)) {
      return null;
    }
    final r = await Process.run(
      'flutter',
      [
        'pub',
        'add',
        // No quotes inside: on Windows this goes through cmd to flutter.bat.
        'dev:integration_test:{sdk: flutter}',
      ],
      workingDirectory: root,
      runInShell: Platform.isWindows,
    );
    return r.exitCode == 0
        ? 'Added integration_test (sdk: flutter) to dev_dependencies.'
        : 'Could not add integration_test to dev_dependencies: ${r.stderr}';
  }

  /// The `flutter test -d` id of the device the app runs on.
  Future<String?> _testDevice(String? operatingSystem) async {
    switch (operatingSystem) {
      case 'macos' || 'linux' || 'windows':
        return operatingSystem;
      case 'ios':
        return _crashTarget?.simulatorUdid;
      case 'android':
        try {
          final r = await runProgram(['flutter', 'devices', '--machine']);
          final devices = (jsonDecode(r.stdout as String) as List)
              .cast<Map<String, dynamic>>();
          return devices
              .where((d) => '${d['targetPlatform']}'.startsWith('android'))
              .map((d) => d['id'] as String?)
              .firstOrNull;
        } catch (_) {
          return null;
        }
    }
    return null;
  }
}

class _ResolvedPatch {
  _ResolvedPatch({
    required this.file,
    required this.filePath,
    required this.line,
    required this.column,
    required this.originalCall,
    required this.newCall,
    required this.patchOffset,
    required this.patchEnd,
    required this.isStaticFallback,
  });

  final String file;
  final String filePath;
  final int line;
  final int column;
  final String originalCall;
  final String newCall;
  final int patchOffset;
  final int patchEnd;
  final bool isStaticFallback;
}
