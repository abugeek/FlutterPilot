part of '../../fp_server.dart';

/// Tools for app-specific custom tools and assertions about what is on
/// screen.
mixin _TestingToolsMixin on _FlutterPilotServerBase {
  static const _channelMocksNotInstalled =
      'This app created its binding before FlutterPilot started, so its '
      'plugin calls can\'t be answered or listed. Make '
      'FlutterPilot.initialize() the first line of main(), before '
      'WidgetsFlutterBinding.ensureInitialized(), then hot restart. '
      'Events (event:) work without it.';

  /// The plugin channels the app has a handler on (not Flutter's own).
  static List<String> _listeners(Map<String, dynamic> data) => [
    for (final c in (data['listeners'] as List? ?? const [])) '$c',
  ];

  void _registerTestingTools() {
    _tool(
      'call_custom_tool',
      description:
          'Runs a tool the app registered with '
          'FlutterPilot.registerCustomTool(). Without name, lists them.',
      inputSchema: ToolInputSchema(
        properties: {
          'name': JsonSchema.string(
            description: 'The custom tool name. Omit to list the tools.',
          ),
          'params': JsonSchema.object(
            description: 'The custom tool\'s parameters.',
          ),
        },
      ),
      callback: (p, e) async {
        if (p['name'] == null) {
          final res = await _callExtensionRaw(
            'ext.flutterpilot.listCustomTools',
            {},
          );
          if (res.isError) return res.toCallToolResult();
          final tools = res.data?['tools'] as List? ?? const [];
          return CallToolResult(
            content: [
              TextContent(
                text: tools.isEmpty
                    ? 'The app registers no custom tools.'
                    : 'Custom tools: ${tools.join(', ')}',
              ),
            ],
          );
        }
        final res = await _callExtensionRaw(
          'ext.flutterpilot.callCustomTool',
          p,
        );
        return res.toCallToolResult();
      },
    );

    _tool(
      'mock_platform_channel',
      description:
          'Stands in for the native side of a plugin (camera, scanner, '
          'permissions, Bluetooth). No argument: lists mocks and recent calls. '
          'channel + method + result (or error) answers a MethodChannel call; '
          'channel + event delivers to an EventChannel. clear:true resets.',
      inputSchema: ToolInputSchema(
        properties: {
          'channel': JsonSchema.string(
            description: 'Channel name, e.g. "plus/battery".',
          ),
          'method': JsonSchema.string(
            description: 'Method name, e.g. "getBatteryLevel".',
          ),
          'result': JsonSchema.fromJson({
            'description': 'Result JSON (null for void; {"\$bytes": "<b64>"}).',
          }),
          'error': JsonSchema.string(
            description: 'Fail with PlatformException code.',
          ),
          'errorMessage': JsonSchema.string(description: 'With error.'),
          'event': JsonSchema.fromJson({
            'description': 'Event to deliver on EventChannel: any JSON.',
          }),
          'clear': JsonSchema.boolean(
            description: 'Remove mocks of channel or all.',
          ),
        },
      ),
      callback: (p, e) async {
        final channel = p['channel']?.toString();
        final method = p['method']?.toString();
        final action = p['clear'] == true
            ? 'clear'
            : p.containsKey('event')
            ? 'emit'
            : channel != null
            ? 'mock'
            : 'list';
        if (action != 'list' && action != 'clear' && channel == null) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Pass the channel name.')],
          );
        }
        if (action == 'mock' &&
            method == null &&
            !p.containsKey('result') &&
            p['error'] == null) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'Pass method and result (or error) to answer calls on '
                    '$channel, or event to deliver one. No argument lists '
                    'the calls the app made.',
              ),
            ],
          );
        }
        // What the app looked like before: a mock set too late is no use.
        final before = action == 'mock'
            ? await _callExtensionRaw('ext.flutterpilot.platformChannel', {})
            : null;
        if (before != null &&
            !before.isError &&
            before.data?['installed'] != true) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: _channelMocksNotInstalled)],
          );
        }
        final res =
            await _callExtensionRaw('ext.flutterpilot.platformChannel', {
              'action': action,
              'channel': ?channel,
              'method': ?method,
              if (action == 'mock' && p['error'] == null)
                'result': jsonEncode(p['result']),
              if (action == 'emit') 'event': jsonEncode(p['event']),
              if (p['error'] != null) 'errorCode': p['error'].toString(),
              if (p['errorMessage'] != null)
                'errorMessage': p['errorMessage'].toString(),
            });
        if (res.isError) return res.toCallToolResult();
        final data = res.data ?? const {};
        final installed = data['installed'] == true;
        final calls = [
          for (final c in (data['calls'] as List? ?? const []))
            (c as Map).cast<String, Object?>(),
        ];
        final lines = <String>[];
        switch (action) {
          case 'mock':
            final called = calls.any(
              (c) =>
                  c['channel'] == channel &&
                  (method == null || c['method'] == method),
            );
            lines.add(
              'Mocked $channel${method == null ? '' : ' $method'}: '
              '${p['error'] != null ? 'throws PlatformException(${p['error']})' : 'returns ${jsonEncode(p['result'])}'}.'
              '${called ? '' : ' The app has not called it since it started: check the name against the calls it made (no argument).'}',
            );
            await _noteTestStep({
              'type': 'skipped',
              'what': 'mock_platform_channel $channel ${method ?? ''}'.trim(),
            });
          case 'emit':
            lines.add(switch (data['listening']) {
              true => 'Delivered the event to $channel.',
              false =>
                'Nothing in the app listens to $channel yet: the event '
                    'waits for the first listener.'
                    '${_listeners(data).isEmpty ? '' : ' Listened to now: ${_listeners(data).join(', ')}.'}',
              _ =>
                'Sent the event to $channel. Whether the app listens to it '
                    'can\'t be told: FlutterPilot.initialize() is not the '
                    'first line of its main().',
            });
            await _noteTestStep({
              'type': 'skipped',
              'what': 'mock_platform_channel event on $channel',
            });
          case 'clear':
            lines.add('Removed ${data['cleared']} mock(s).');
          default:
            if (!installed) lines.add(_channelMocksNotInstalled);
        }
        if (action == 'list' || action == 'clear') {
          final mocks = data['mocks'] as List? ?? const [];
          lines.add(
            mocks.isEmpty
                ? 'No mocks.'
                : 'Mocks:\n${mocks.map((m) {
                    m as Map;
                    return '- ${m['channel']}${m['method'] == null ? '' : ' ${m['method']}'} → ${m['errorCode'] != null ? 'PlatformException(${m['errorCode']})' : jsonEncode(m['result'])}';
                  }).join('\n')}',
          );
        }
        if (action == 'list' && installed) {
          lines.add(
            calls.isEmpty
                ? 'The app has made no plugin calls since it started.'
                : 'Calls the app made (channel method — outcome):\n'
                      '${calls.map((c) => '- ${c['channel']}${c['method'] == null ? '' : ' ${c['method']}'}'
                          '${(c['times'] as int? ?? 1) > 1 ? ' ×${c['times']}' : ''} — '
                          '${c['outcome'] == 'no plugin' ? 'no plugin on this platform (MissingPluginException)' : c['outcome']}'
                          '${'${c['arguments']}'.isEmpty ? '' : ' ${c['arguments']}'}').join('\n')}',
          );
          if (_listeners(data).isNotEmpty) {
            lines.add(
              'Channels the app listens to (event): '
              '${_listeners(data).join(', ')}',
            );
          }
        }
        return CallToolResult(content: [TextContent(text: lines.join('\n'))]);
      },
    );

    _tool(
      'assert_widget',
      description:
          'Checks the screen in the running app in milliseconds; an error '
          'result is a failed assertion. One check per call: text — that text '
          'is visible (substring unless exact); key — that widget is on '
          'screen, or with enabled true/false that it is enabled/disabled; '
          'type + count — exactly that many widgets of the type. Only what '
          'the user can see counts (not covered routes or hidden tabs).',
      inputSchema: ToolInputSchema(
        properties: {
          'text': JsonSchema.string(description: 'Text expected on screen.'),
          'exact': JsonSchema.boolean(
            description: 'Require an exact text match (default substring).',
          ),
          'key': JsonSchema.string(
            description: 'Key, selector or label of the widget.',
          ),
          'enabled': JsonSchema.boolean(
            description:
                'With key: expect enabled (true) or disabled (false), i.e. '
                'onPressed/onTap/onChanged set or null.',
          ),
          'type': JsonSchema.string(
            description: 'Widget type to count (e.g. "ListTile").',
          ),
          'count': JsonSchema.integer(description: 'Expected count of type.'),
        },
      ),
      callback: (p, e) async {
        const nothingToCheck =
            'Say what to check: text, key (optionally with enabled), '
            'or type with count.';
        final target = p['target'] ?? p['key'];
        final _ExtensionResult res;
        // What the check is, and what it saw: a text, key or enabled check
        // sees one widget when it passes, and a count check reads the count
        // back from the payload its text is built from too.
        late final String check;
        String? expected;
        int? found;
        if (p['text'] != null) {
          check = 'text';
          expected = p['text'].toString();
          found = 1;
          res = await _callExtensionRaw('ext.flutterpilot.assertTextVisible', {
            'text': p['text'].toString(),
            if (p['exact'] != null) 'exact': p['exact'].toString(),
            if (p['autoScroll'] == true) 'autoScroll': 'true',
          });
        } else if (p['type'] != null && p['count'] != null) {
          check = 'count';
          expected = '${p['count']} ${p['type']}';
          res = await _callExtensionRaw('ext.flutterpilot.assertWidgetCount', {
            'type': p['type'].toString(),
            'count': p['count'].toString(),
          });
          found = (res.data?['count'] as num?)?.toInt();
        } else if (target != null && p['enabled'] != null) {
          check = p['enabled'] == true ? 'enabled' : 'disabled';
          expected = target.toString();
          found = 1;
          res = await _callExtensionRaw(
            p['enabled'] == true
                ? 'ext.flutterpilot.assertWidgetEnabled'
                : 'ext.flutterpilot.assertWidgetDisabled',
            {'key': target.toString()},
          );
        } else if (target != null) {
          check = 'key';
          expected = target.toString();
          found = 1;
          res = await _callExtensionRaw(
            'ext.flutterpilot.assertWidgetVisible',
            {
              'key': target.toString(),
              if (p['autoScroll'] == true) 'autoScroll': 'true',
            },
          );
        } else {
          return withVerdict(
            CallToolResult(
              isError: true,
              content: [TextContent(text: nothingToCheck)],
            ),
            assertWidgetVerdict(
              check: 'none',
              passed: false,
              reason: nothingToCheck,
            ),
          );
        }
        return withVerdict(
          res.toCallToolResult(),
          assertWidgetVerdict(
            check: check,
            expected: expected,
            passed: !res.isError,
            found: res.isError ? null : found,
            reason: res.isError ? res.errorMessage : null,
          ),
        );
      },
    );

    _tool(
      'export_network_mocks',
      description:
          'Turns the responses the app received (Dio) into mock_http_response '
          'steps, one per URL, ready for execute_action_chain; apply: true '
          'installs them now so the app runs offline on recorded data '
          '(scenario save keeps them). Says which bodies the log cut.',
      inputSchema: ToolInputSchema(
        properties: {
          'filter': JsonSchema.string(
            description: 'Only URLs containing this.',
          ),
          'statusCode': JsonSchema.integer(
            description: 'Use this status instead of the recorded one.',
          ),
          'apply': JsonSchema.boolean(
            description: 'Install the mocks now instead of only listing them.',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.getNetworkLogs',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        final filter = p['filter']?.toString();
        final status = (p['statusCode'] as num?)?.toInt();
        // Latest real (not mocked) response per URL.
        final byUrl = <String, Map>{};
        for (final log
            in (res.data?['logs'] as List? ?? const []).whereType<Map>()) {
          final uri = log['uri']?.toString();
          if (log['type'] != 'response' ||
              log['mocked'] == true ||
              uri == null) {
            continue;
          }
          if (filter != null && !uri.contains(filter)) continue;
          byUrl[uri] = log;
        }
        if (byUrl.isEmpty) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'No recorded responses${filter != null ? ' matching "$filter"' : ''}. '
                    'Drive the app so it makes the requests first (get_network_logs '
                    'lists what it made).',
              ),
            ],
          );
        }
        final steps = <Map<String, dynamic>>[];
        final cut = <String>[];
        for (final MapEntry(key: uri, value: log) in byUrl.entries) {
          final u = Uri.tryParse(uri);
          // mock_http_response matches URLs that contain the pattern.
          final pattern = u == null
              ? uri
              : '${u.host}${u.path}${u.hasQuery ? '?${u.query}' : ''}';
          final body = log['body'];
          if (log['bodyCut'] == true) cut.add(pattern);
          steps.add({
            'tool': 'mock_http_response',
            'arguments': {
              'urlPattern': pattern,
              'statusCode':
                  status ?? (log['statusCode'] as num?)?.toInt() ?? 200,
              'body': body is String ? body : jsonEncode(body ?? ''),
            },
          });
        }
        final buf = StringBuffer('${steps.length} URL(s) recorded.');
        if (cut.isNotEmpty) {
          buf.write(
            '\n${cut.length} bodies are not the whole response (the log keeps '
            '20 list items and 4 KB of text, and masks credential fields): '
            '${cut.take(5).join(', ')}${cut.length > 5 ? ', …' : ''}. A mock of '
            'those answers less than the server did.',
          );
        }
        if (p['apply'] == true) {
          final mock = _toolCallbacks['mock_http_response']!;
          var failed = 0;
          for (final step in steps) {
            final r = await mock(
              Map<String, dynamic>.from(step['arguments'] as Map),
              e,
            );
            if (r.isError == true) failed++;
          }
          buf.write(
            '\nInstalled ${steps.length - failed} mock(s)'
            '${failed > 0 ? ', $failed refused' : ''}. '
            'mock_http_response(clear: true) removes them.',
          );
        } else {
          final json = jsonEncode(steps);
          buf.write(
            json.length <= 6000
                ? '\nSteps for execute_action_chain:\n$json'
                : '\nThe steps are ${json.length} characters: apply: true '
                      'installs them without listing them, or narrow with '
                      'filter. URLs: ${byUrl.keys.take(10).join(', ')}'
                      '${byUrl.length > 10 ? ', …' : ''}',
          );
        }
        return CallToolResult(
          content: [TextContent(text: buf.toString())],
          structuredContent: {
            'count': steps.length,
            'cut': cut,
            'applied': p['apply'] == true,
          },
        );
      },
    );
  }
}
