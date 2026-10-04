part of '../../flutterpilot_server.dart';

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
          'params': JsonSchema.object(),
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
          'location, permissions, Bluetooth), which a simulator or CI has '
          'not. channel + method + result (or error): the app\'s calls to '
          'that method get the value, or a PlatformException. channel + '
          'event: delivers an event to the app\'s EventChannel listeners, '
          'e.g. a scanned barcode. No argument lists the mocks and the '
          'calls the app made (channel, method, arguments, whether a plugin '
          'answered): how to find the names. clear:true removes mocks. '
          'Pigeon APIs: the whole channel name, no method.',
      inputSchema: ToolInputSchema(
        properties: {
          'channel': JsonSchema.string(
            description:
                'Channel name, e.g. "dev.fluttercommunity.plus/battery".',
          ),
          'method': JsonSchema.string(
            description: 'The method the app invokes, e.g. "getBatteryLevel".',
          ),
          'result': JsonSchema.fromJson({
            'description':
                'What the call returns: any JSON (null for a void method; '
                '{"\$bytes": "<base64>"} is a byte array).',
          }),
          'error': JsonSchema.string(
            description:
                'Fail the call with a PlatformException of this code, e.g. '
                '"PERMISSION_DENIED".',
          ),
          'errorMessage': JsonSchema.string(),
          'event': JsonSchema.fromJson({
            'description': 'The event to deliver on an EventChannel: any JSON.',
          }),
          'clear': JsonSchema.boolean(
            description:
                'Remove the mocks of channel (and method), or all of them.',
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
        final target = p['target'] ?? p['key'];
        final _ExtensionResult res;
        if (p['text'] != null) {
          res = await _callExtensionRaw('ext.flutterpilot.assertTextVisible', {
            'text': p['text'].toString(),
            if (p['exact'] != null) 'exact': p['exact'].toString(),
          });
        } else if (p['type'] != null && p['count'] != null) {
          res = await _callExtensionRaw('ext.flutterpilot.assertWidgetCount', {
            'type': p['type'].toString(),
            'count': p['count'].toString(),
          });
        } else if (target != null && p['enabled'] != null) {
          res = await _callExtensionRaw(
            p['enabled'] == true
                ? 'ext.flutterpilot.assertWidgetEnabled'
                : 'ext.flutterpilot.assertWidgetDisabled',
            {'key': target.toString()},
          );
        } else if (target != null) {
          res = await _callExtensionRaw(
            'ext.flutterpilot.assertWidgetVisible',
            {'key': target.toString()},
          );
        } else {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'Say what to check: text, key (optionally with enabled), '
                    'or type with count.',
              ),
            ],
          );
        }
        return res.toCallToolResult();
      },
    );
  }
}
