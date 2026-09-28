part of '../../flutterpilot_server.dart';

/// Tools for app-specific custom tools and assertions about what is on
/// screen.
mixin _TestingToolsMixin on _FlutterPilotServerBase {
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
