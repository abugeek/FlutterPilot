part of '../../flutterpilot_server.dart';

/// Tools for tapping, typing, scrolling, swiping, and other UI interactions.
mixin _UiAutomationToolsMixin on _FlutterPilotServerBase {
  void _registerUiAutomationTools() {
    server.registerTool(
      'tap_at',
      description:
          'Simulates a physical tap at specific (x, y) coordinates. Prefer `tap_widget` if you have a Key.',
      inputSchema: ToolInputSchema(
        properties: {
          'x': JsonSchema.number(
            description:
                'X screen coordinate in logical pixels. Screen origin is top-left.',
          ),
          'y': JsonSchema.number(
            description:
                'Y screen coordinate in logical pixels. Screen origin is top-left.',
          ),
        },
        required: ['x', 'y'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.tapAt', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Tap successful. HINT: Use get_navigation_stack or get_riverpod_state to see if the app responded.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'tap_widget',
      description:
          'Finds a widget by its Key and taps its center. HINT: Use `get_widget_tree` to find the Key first. After tapping, you should verify state changes.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The ValueKey string of the widget to tap. Use get_widget_tree to find widget keys.',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.tapWidget', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Widget tapped. HINT: The UI should have changed. Use capture_screenshot to verify.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'enter_text',
      description:
          'Types text into a TextField identified by a Key. Automatically handles controller updates and change notifications.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The ValueKey string of the widget to tap. Use get_widget_tree to find widget keys.',
          ),
          'text': JsonSchema.string(
            description:
                'The text to enter into the text field.',
          ),
        },
        required: ['key', 'text'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.enterText', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Text entered. HINT: You may need to tap a "Submit" or "Save" button now.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'scroll_into_view',
      description:
          'Ensures a widget is visible by scrolling its parent list. Use this before tapping a widget that might be off-screen.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The ValueKey string of the widget to scroll into view.',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.scrollIntoView',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    server.registerTool(
      'double_tap_widget',
      description:
          'Double-taps a widget by Key (two rapid taps). Use for zoom gestures, selection toggles, or any widget that responds to double-tap.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The ValueKey string of the widget to double-tap. Use get_widget_tree to find keys.',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.doubleTapWidget',
          p,
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: 'Double-tapped. Use capture_screenshot to verify.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'long_press_widget',
      description:
          'Long-presses a widget by Key. Use to trigger context menus, drag handles, or long-press actions. Optional durationMs (default 600).',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'The ValueKey string of the widget to long-press.',
          ),
          'durationMs': JsonSchema.integer(
            description:
                'Duration of the long press in milliseconds (default: 600ms).',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final args = {
          'key': p['key'] as String,
          if (p['durationMs'] != null) 'durationMs': p['durationMs'].toString(),
        };
        final res = await _callExtensionRaw(
          'ext.flutterpilot.longPressWidget',
          args,
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Long press complete. Use capture_screenshot to verify the context menu or action.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'swipe_widget',
      description:
          'Swipes on a widget in a direction (up/down/left/right). Use to scroll lists, dismiss cards, open drawers, or trigger swipe actions.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'The ValueKey string of the widget to swipe.',
          ),
          'direction': JsonSchema.string(
            enumValues: ['up', 'down', 'left', 'right'],
          ),
          'distance': JsonSchema.number(
            description:
                'Scroll distance in logical pixels. Positive = down/right, negative = up/left.',
          ),
        },
        required: ['key', 'direction'],
      ),
      callback: (p, e) async {
        final args = {
          'key': p['key'] as String,
          'direction': p['direction'] as String,
          if (p['distance'] != null) 'distance': p['distance'].toString(),
        };
        final res = await _callExtensionRaw(
          'ext.flutterpilot.swipeWidget',
          args,
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Swipe complete. Use capture_screenshot or get_widget_tree to verify.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'drag_widget',
      description:
          'Drags one widget onto another by Key. Use for drag-and-drop reordering, drag targets, or drop zones.',
      inputSchema: ToolInputSchema(
        properties: {
          'fromKey': JsonSchema.string(
            description:
                'The ValueKey string of the widget to drag from (drag source).',
          ),
          'toKey': JsonSchema.string(
            description:
                'The ValueKey string of the target widget to drag to (drop target).',
          ),
        },
        required: ['fromKey', 'toKey'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.dragWidget', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Drag complete. Use capture_screenshot to verify the new position.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'clear_text_field',
      description:
          'Clears the text of a TextField / TextFormField identified by its '
          'widget key. Equivalent to select-all then delete. '
          'Use enter_text to type new content afterwards.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'The ValueKey string of the text field to clear.',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.clearTextField', {
          'key': p['key'].toString(),
        });
        return res.isError
            ? res.toCallToolResult()
            : CallToolResult(
                content: [TextContent(text: 'Text field cleared.')],
              );
      },
    );

    server.registerTool(
      'focus_widget',
      description:
          'Taps the centre of the widget identified by key to request focus '
          '(opens the software keyboard for a TextField). '
          'Use unfocus_all to close the keyboard afterwards.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'The ValueKey string of the widget to focus.',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.focusWidget', {
          'key': p['key'].toString(),
        });
        return res.isError
            ? res.toCallToolResult()
            : CallToolResult(content: [TextContent(text: 'Widget focused.')]);
      },
    );

    server.registerTool(
      'unfocus_all',
      description:
          'Removes focus from all widgets and dismisses the software keyboard. '
          'Call this after finishing text input to close the keyboard before '
          'taking screenshots or tapping other elements.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.unfocusAll', {});
        return res.isError
            ? res.toCallToolResult()
            : CallToolResult(
                content: [TextContent(text: 'Keyboard dismissed.')],
              );
      },
    );

    server.registerTool(
      'set_text_scale_factor',
      description:
          'Overrides the app-wide text scale factor for accessibility testing. '
          'Common values: 1.0 (default), 1.5 (large), 2.0 (extra-large), '
          '3.0 (maximum). Pass 0 to reset to system default. '
          'Requires the app to wrap MaterialApp with a MediaQuery that '
          'listens to FlutterPilot.textScaleNotifier.',
      inputSchema: ToolInputSchema(
        properties: {
          'scale': JsonSchema.number(
            description:
                'Text scale factor (1.0 = normal, 2.0 = double size, 0.5 = half size). Test accessibility at 2.0.',
          ),
        },
        required: ['scale'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.setTextScaleFactor',
          {'scale': p['scale'].toString()},
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'set_slider_value',
      description:
          'Sets the value of a Slider widget identified by key. Computes '
          'the correct tap position for the target value based on the '
          'slider\'s min/max range and dispatches a pointer event. '
          'The value is clamped to [min, max].',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'The ValueKey string of the Slider widget.',
          ),
          'value': JsonSchema.number(
            description:
                'The new slider value. Must be within the slider min/max range.',
          ),
        },
        required: ['key', 'value'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.setSliderValue', {
          'key': p['key'].toString(),
          'value': p['value'].toString(),
        });
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'toggle_checkbox',
      description:
          'Taps the centre of the first Checkbox, Switch, or Radio widget '
          'found under the given key to toggle its state. '
          'Use get_widget_properties to read the resulting isChecked value.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The ValueKey string of the Checkbox, Switch, or Radio widget to toggle.',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.toggleCheckbox', {
          'key': p['key'].toString(),
        });
        return res.isError
            ? res.toCallToolResult()
            : CallToolResult(content: [TextContent(text: 'Toggled.')]);
      },
    );

    server.registerTool(
      'pump_frames',
      description:
          'Waits for a specified number of vsync animation frames to complete. '
          'Use this to let animations, timers, or async widget builds settle '
          'without needing a full wait_for_animation call. '
          'Max 120 frames.',
      inputSchema: ToolInputSchema(
        properties: {
          'count': JsonSchema.integer(
            description:
                'Number of frames to pump. Use 1–5 for immediate animations, 60 for ~1 second of wall time.',
          ),
        },
      ),
      callback: (p, e) async {
        final count = ((p['count'] as int?) ?? 1).clamp(1, 120);
        final res = await _callExtensionRaw('ext.flutterpilot.pumpFrames', {
          'count': count.toString(),
        });
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'simulate_deep_link',
      description:
          'Simulates opening a deep link URL, triggering the same routing '
          'path as an OS-level deep link (e.g., "myapp://product/123" or '
          '"/product/123"). Use this to test deep link handlers, share links, '
          'and notification tap flows.',
      inputSchema: ToolInputSchema(
        properties: {
          'url': JsonSchema.string(
            description:
                'The URL pattern to intercept (exact match or prefix).',
          ),
        },
        required: ['url'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.simulateDeepLink',
          {'url': p['url'].toString()},
        );
        return res.toCallToolResult();
      },
    );

    server.registerTool(
      'press_back',
      description:
          'Simulates pressing the hardware/system back button. Pops the '
          'current route from the Navigator. Reports whether a route was '
          'actually popped (false if already at root).',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.pressBack', {});
        if (res.isError) return res.toCallToolResult();
        final popped = res.data?['popped'] as bool? ?? false;
        return CallToolResult(
          content: [
            TextContent(
              text: popped
                  ? 'Back pressed — route popped.'
                  : 'Back pressed — already at root (nothing to pop).',
            ),
          ],
        );
      },
    );
  }
}
