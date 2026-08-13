part of '../../flutterpilot_server.dart';

/// Tools for navigating routes, waiting for widgets/animations/state,
/// and changing device orientation, locale, and theme.
mixin _NavigationToolsMixin on _FlutterPilotServerBase {
  void _registerNavigationTools() {
    server.registerTool(
      'navigate_to',
      description:
          'Programmatically pushes a named route. Useful for jumping directly to a feature screen for testing.',
      inputSchema: ToolInputSchema(
        properties: {
          'route': JsonSchema.string(
            description:
                'The named route to navigate to (e.g. "/home", "/profile/123"). Must be registered in the app router.',
          ),
        },
        required: ['route'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.navigateTo',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'jump_to_screen',
      description:
          'Directly teleports to a deep application screen with optional seed state injection (Riverpod/Bloc/storage). '
          'Bypasses lengthy manual onboarding or multi-step checkout clicks.',
      inputSchema: ToolInputSchema(
        properties: {
          'route': JsonSchema.string(
            description: 'Target route name (e.g. "/order/123", "/settings/security").',
          ),
          'state': JsonSchema.object(
            description:
                'Optional map of state seeds to inject before navigation (e.g. {"riverpod:auth": "logged_in"}).',
          ),
        },
        required: ['route'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.jumpToScreen', {
          'route': p['route'].toString(),
          if (p['state'] != null) 'state': json.encode(p['state']),
        });
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: '🚀 Teleported directly to "${p['route']}" with state injected.',
            ),
          ],
        );
      },
    );

    _registerAppTool(
      name: 'get_navigation_stack',
      description:
          'Show the current navigation history (stack). CALL THIS to understand where the user is in the application flow.',
      extension: 'ext.flutterpilot.getNavigationStack',
      formatResult: (json) =>
          'Navigation Stack: ${json['stack']?.join(' -> ') ?? 'Empty'}',
    );

    server.registerTool(
      'wait_for_widget',
      description:
          'Polls until a widget with the given Key appears in the tree, or times out. Use after navigation or async operations. Default timeout 5000ms.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The ValueKey string of the widget to wait for to appear.',
          ),
          'timeoutMs': JsonSchema.integer(
            description:
                'Maximum milliseconds to wait for the widget (default: 5000ms).',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final args = {
          'key': p['key'] as String,
          if (p['timeoutMs'] != null) 'timeoutMs': p['timeoutMs'].toString(),
        };
        return _callExtensionRaw(
          'ext.flutterpilot.waitForWidget',
          args,
        ).then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'wait_for_route',
      description:
          'Polls until the current route matches the expected route, or times out. Use instead of sleep() after navigate_to. Default timeout 5000ms.',
      inputSchema: ToolInputSchema(
        properties: {
          'route': JsonSchema.string(
            description:
                'The route name to wait for (e.g. "/dashboard", "/settings").',
          ),
          'timeoutMs': JsonSchema.integer(
            description:
                'Maximum milliseconds to wait for the route (default: 5000ms).',
          ),
        },
        required: ['route'],
      ),
      callback: (p, e) async {
        final args = {
          'route': p['route'] as String,
          if (p['timeoutMs'] != null) 'timeoutMs': p['timeoutMs'].toString(),
        };
        return _callExtensionRaw(
          'ext.flutterpilot.waitForRoute',
          args,
        ).then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'wait_for_animation',
      description:
          'Waits until all animations and frame callbacks have settled. Call this before taking screenshots or making assertions after animated transitions.',
      inputSchema: ToolInputSchema(
        properties: {
          'timeoutMs': JsonSchema.integer(
            description:
                'Maximum milliseconds to wait for all animations to settle (default: 5000ms.',
          ),
        },
      ),
      callback: (p, e) async {
        final args = {
          if (p['timeoutMs'] != null) 'timeoutMs': p['timeoutMs'].toString(),
        };
        return _callExtensionRaw(
          'ext.flutterpilot.waitForAnimation',
          args,
        ).then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'wait_for_state',
      description:
          'Polls a Riverpod provider or Bloc/Cubit until its current value string contains '
          'expectedValue, or until timeoutMs elapses. Use after triggering async operations '
          'to assert that state has settled. Requires the matching plugin to be active '
          '(RiverpodPilotObserver or BlocPilotObserver).',
      inputSchema: ToolInputSchema(
        properties: {
          'type': JsonSchema.string(enumValues: ['riverpod', 'bloc']),
          'name': JsonSchema.string(
            description:
                'State identifier. For Riverpod: the provider\'s runtimeType string '
                '(e.g. "StateProvider<int>"). For Bloc: the bloc\'s runtimeType string '
                '(e.g. "CounterCubit").',
          ),
          'expectedValue': JsonSchema.string(
            description: 'Substring expected in the state\'s toString() output',
          ),
          'timeoutMs': JsonSchema.integer(
            description:
                'Milliseconds to wait before timing out (default 5000)',
          ),
        },
        required: ['type', 'name', 'expectedValue'],
      ),
      callback: (p, e) {
        final mapped = {
          'type': p['type']?.toString(),
          'name': p['name']?.toString(),
          'expectedValue': p['expectedValue']?.toString(),
          if (p['timeoutMs'] != null) 'timeoutMs': p['timeoutMs'].toString(),
        };
        return _callExtensionRaw(
          'ext.flutterpilot.waitForState',
          mapped,
        ).then((res) => res.toCallToolResult());
      },
    );

    server.registerTool(
      'set_device_rotation',
      description:
          'Rotates the device to portrait or landscape orientation. Use to test responsive layouts, '
          'orientation-locked screens, and rotation animations.',
      inputSchema: ToolInputSchema(
        properties: {
          'orientation': JsonSchema.string(
            enumValues: ['portrait', 'landscape', 'all'],
          ),
        },
        required: ['orientation'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.setOrientation',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'set_locale',
      description:
          'Switch app language (e.g., "en", "de_DE"). Use this to check for text overflows in different languages.',
      inputSchema: ToolInputSchema(
        properties: {
          'locale': JsonSchema.string(
            description:
                'BCP-47 locale tag (e.g. "en", "fr", "ar", "zh-CN"). Use "system" to restore the device default.',
          ),
        },
        required: ['locale'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.setLocale',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'set_theme',
      description:
          'Toggle Light/Dark mode. Use this to verify design consistency across themes.',
      inputSchema: ToolInputSchema(
        properties: {
          'theme': JsonSchema.string(enumValues: ['light', 'dark']),
        },
        required: ['theme'],
      ),
      callback: (p, e) {
        final val = p['theme'] == 'dark'
            ? 'Brightness.dark'
            : 'Brightness.light';
        return _callExtensionRaw('ext.flutter.brightnessOverride', {
          'value': val,
        }).then((res) => res.toCallToolResult());
      },
    );
  }
}
