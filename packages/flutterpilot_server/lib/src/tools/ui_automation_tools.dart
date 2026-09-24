part of '../../flutterpilot_server.dart';

/// Tools for tapping, typing, scrolling, swiping, and other UI interactions.
mixin _UiAutomationToolsMixin on _FlutterPilotServerBase {
  static String _formatActionFeedback(
    String actionName,
    Map<String, dynamic> params,
    _ExtensionResult res,
  ) {
    final target = res.data?['target'] ??
        res.data?['key'] ??
        params['key'] ??
        params['identifier'] ??
        params['text'] ??
        '';
    final postState = res.data?['postActionState'] as Map<String, dynamic>?;
    final buffer = StringBuffer();
    final targetStr = target.toString();
    buffer.writeln(
      '⚡ $actionName${targetStr.isNotEmpty ? ' on "$targetStr"' : ''} executed successfully.',
    );
    if (postState != null) {
      buffer.writeln('\nInstant Post-Action State:');
      final route = postState['route'];
      final routeChanged = postState['routeChanged'] == true;
      final focused = postState['focusedElement'];
      final elements = postState['visibleInteractiveElements'] as List?;
      final count = postState['interactiveElementsCount'];
      final errors = postState['errorCount'];

      if (route != null) {
        buffer.writeln('• Route: $route${routeChanged ? ' (CHANGED!)' : ''}');
      }
      if (focused != null) {
        buffer.writeln('• Focused Element: "$focused"');
      }
      if (elements != null && elements.isNotEmpty) {
        buffer.writeln(
          '• Hittable Elements ($count total): [${elements.join(", ")}]',
        );
      }
      if (errors != null && (errors is int ? errors > 0 : errors != 0)) {
        buffer.writeln(
          '• ⚠️ Uncaught Errors: $errors (call get_errors to inspect)',
        );
      }
      final issueAlert = postState['issueAlert'] ?? postState['perfAlert'];
      if (issueAlert != null && issueAlert.toString().isNotEmpty) {
        buffer.writeln(issueAlert.toString());
      }
    }
    return buffer.toString().trim();
  }

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
          'Finds a widget by Key, Semantics identifier (Flutter 3.19+), semanticsId, visible text, runtime type, or direct coordinates, and taps it. '
          'Works reliably across all screen sizes and device types. '
          'PREREQUISITES: Call get_interactive_elements or get_widget_tree to discover available widgets. '
          'AFTER: Verify the tap worked with capture_screenshot or state inspection tools.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'ValueKey string, semantic selector (e.g. "ElevatedButton[\'Sign In\']"), visible button text, or icon name (e.g. "IconButton[\'settings\']").',
          ),
          'identifier': JsonSchema.string(
            description:
                'Semantics identifier property (Flutter 3.19+) for robust AI targeting.',
          ),
          'semanticsId': JsonSchema.integer(
            description:
                'Numeric SemanticsNode ID from get_semantics_tree for accessibility-first interaction.',
          ),
          'text': JsonSchema.string(
            description: 'Visible text content within the widget to tap.',
          ),
          'type': JsonSchema.string(
            description: 'Widget runtime type, e.g. "ElevatedButton", "TextButton", "IconButton".',
          ),
          'maxAttempts': JsonSchema.integer(
            description: 'Max scroll attempts if widget is off-screen (default: 8).',
          ),
          'x': JsonSchema.number(
            description: 'Optional direct X screen coordinate.',
          ),
          'y': JsonSchema.number(
            description: 'Optional direct Y screen coordinate.',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.tapWidget', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: _formatActionFeedback('Widget tapped', p, res),
            ),
          ],
        );
      },
    );

    // Convenience alias matching standard MCP patterns
    server.registerTool(
      'tap',
      description:
          'Convenience alias for tap_widget. Finds a widget by Key, identifier, semanticsId, visible text, or coordinates and taps it.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'ValueKey string, semantic selector, or target.',
          ),
          'identifier': JsonSchema.string(
            description: 'Semantics identifier property.',
          ),
          'semanticsId': JsonSchema.integer(
            description: 'Numeric SemanticsNode ID from get_semantics_tree.',
          ),
          'text': JsonSchema.string(
            description: 'Visible text within the widget to tap.',
          ),
          'type': JsonSchema.string(
            description: 'Widget runtime type.',
          ),
          'maxAttempts': JsonSchema.integer(
            description: 'Max scroll attempts if widget is off-screen (default: 8).',
          ),
          'x': JsonSchema.number(
            description: 'Optional direct X coordinate.',
          ),
          'y': JsonSchema.number(
            description: 'Optional direct Y coordinate.',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.tapWidget', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: _formatActionFeedback('Tap', p, res),
            ),
          ],
        );
      },
    );

    server.registerTool(
      'enter_text',
      description:
          'Types text into a TextField, TextFormField, or editable widget. '
          'Can target by Key, identifier, or into the currently focused element if key is omitted or focused_element: true. '
          'Automatically updates the TextEditingController and fires onChanged/onSubmitted callbacks. '
          'AFTER: The text field now contains the new text. You may need to tap a submit button or call press_key("enter").',
      inputSchema: ToolInputSchema(
        properties: {
          'text': JsonSchema.string(
            description: 'The text to enter into the text field.',
          ),
          'key': JsonSchema.string(
            description:
                'Optional ValueKey string, selector (e.g. "TextField[\'Email\']"), or label of the text field to type into.',
          ),
          'identifier': JsonSchema.string(
            description: 'Optional semantics identifier of the text field.',
          ),
          'focused_element': JsonSchema.boolean(
            description:
                'If true, enters text into the currently focused text field without requiring a key.',
          ),
          'clear_first': JsonSchema.boolean(
            description:
                'Whether to clear existing text before typing (default: true).',
          ),
        },
        required: ['text'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.enterText', p);
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: _formatActionFeedback('Text entered', p, res),
            ),
          ],
        );
      },
    );

    server.registerTool(
      'press_key',
      description:
          'Dispatches physical hardware key events (e.g. "enter", "tab", "escape", "backspace", "arrowDown", "space") '
          'directly to Flutter\'s HardwareKeyboard and focused widget. '
          'Supports Enter form submission and modifier keys (shift, ctrl, alt, meta).',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'Key name to press, e.g. "enter", "tab", "escape", "backspace", "arrowDown", "arrowUp", "space", or single characters.',
          ),
          'modifiers': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Optional modifier keys: "shift", "ctrl", "alt", "meta".',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final callParams = <String, dynamic>{'key': p['key']};
        if (p['modifiers'] != null) {
          final mods = p['modifiers'];
          callParams['modifiers'] =
              mods is List ? mods.join(',') : mods.toString();
        }
        final res = await _callExtensionRaw(
          'ext.flutterpilot.pressKey',
          callParams,
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: _formatActionFeedback('Key pressed', p, res),
            ),
          ],
        );
      },
    );

    server.registerTool(
      'secondary_tap',
      description:
          'Performs a secondary tap (right-click / context tap) on a widget or coordinates. '
          'Useful for triggering desktop/web context menus.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'The ValueKey or selector of the widget.',
          ),
          'identifier': JsonSchema.string(
            description: 'Semantics identifier of the widget.',
          ),
          'text': JsonSchema.string(
            description: 'Visible text of the widget.',
          ),
          'type': JsonSchema.string(
            description: 'Widget runtime type.',
          ),
          'x': JsonSchema.number(
            description: 'Optional direct X coordinate.',
          ),
          'y': JsonSchema.number(
            description: 'Optional direct Y coordinate.',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.secondaryTapWidget',
          p,
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: _formatActionFeedback('Secondary tap', p, res),
            ),
          ],
        );
      },
    );

    server.registerTool(
      'pinch_zoom',
      description:
          'Simulates a two-finger pinch-to-zoom gesture on a widget or at coordinates. '
          'Scale > 1 zooms in, scale < 1 zooms out.',
      inputSchema: ToolInputSchema(
        properties: {
          'scale': JsonSchema.number(
            description:
                'Zoom scale factor (e.g. 1.5 to zoom in, 0.75 to zoom out).',
          ),
          'key': JsonSchema.string(
            description: 'The ValueKey or selector of the target widget.',
          ),
          'identifier': JsonSchema.string(
            description: 'Semantics identifier of the target widget.',
          ),
          'x': JsonSchema.number(
            description: 'Optional center X coordinate for pinch gesture.',
          ),
          'y': JsonSchema.number(
            description: 'Optional center Y coordinate for pinch gesture.',
          ),
        },
        required: ['scale'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.pinchZoomWidget',
          p,
        );
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: _formatActionFeedback('Pinch zoom', p, res),
            ),
          ],
        );
      },
    );

    server.registerTool(
      'scroll_into_view',
      description:
          'Ensures a widget is visible by scrolling its parent list. Works with Keys, semantic selectors, or text labels.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The ValueKey string, semantic selector, or label of the widget to scroll into view.',
          ),
          'maxAttempts': JsonSchema.integer(
            description: 'Max scroll attempts to locate the widget in lazy lists (default: 8).',
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

    Future<CallToolResult> backCallback(
      Map<String, dynamic> p,
      dynamic e,
    ) async {
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
    }

    server.registerTool(
      'press_back',
      description:
          'Simulates pressing the hardware/system back button. Pops the '
          'current route from the Navigator. Reports whether a route was '
          'actually popped (false if already at root).',
      inputSchema: ToolInputSchema(properties: {}),
      callback: backCallback,
    );

    server.registerTool(
      'go_back',
      description:
          'Alias for press_back. Pops the current route or screen.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: backCallback,
    );

    server.registerTool(
      'fill_form',
      description:
          'Fills multiple form fields in a single shot using Virtual Semantic Selectors or keys, '
          'with optional one-shot form submission. Eliminates multiple turn delays when testing forms.',
      inputSchema: ToolInputSchema(
        properties: {
          'fields': JsonSchema.object(
            description:
                'Map of field selectors to text values (e.g. {"TextField[\'Email\']": "test@flutterpilot.dev", "TextField[\'Password\']": "secret"}).',
          ),
          'submitWith': JsonSchema.string(
            description:
                'Optional selector or key of the submit button to tap after filling (e.g. "ElevatedButton[\'Log In\']").',
          ),
        },
        required: ['fields'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.fillForm', {
          'fields': json.encode(p['fields']),
          if (p['submitWith'] != null) 'submitWith': p['submitWith'].toString(),
        });
        if (res.isError) return res.toCallToolResult();
        final filled = res.data?['fieldsFilled'] ?? 0;
        final total = res.data?['totalFields'] ?? 0;
        final submitted = res.data?['submitted'] == true;
        return CallToolResult(
          content: [
            TextContent(
              text: '✅ Filled $filled/$total form fields successfully${submitted ? ' and tapped submit.' : '.'}',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'wait_for_condition',
      description:
          'Reliably polls until a target element or semantic selector is visible on screen, or until timeout. '
          'Prevents flaky test timing during async loading spinners or page transitions.',
      inputSchema: ToolInputSchema(
        properties: {
          'selector': JsonSchema.string(
            description: 'Semantic selector or key to wait for (e.g. "Text[\'Dashboard\']" or "order_confirmed_icon").',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Maximum milliseconds to wait before failing (default: 3000).',
          ),
        },
        required: ['selector'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.waitForCondition', {
          'selector': p['selector'].toString(),
          if (p['timeoutMs'] != null) 'timeoutMs': p['timeoutMs'].toString(),
        });
        if (res.isError) return res.toCallToolResult();
        final elapsed = res.data?['elapsedMs'] ?? 0;
        return CallToolResult(
          content: [
            TextContent(
              text: '🎯 Condition satisfied: "${p['selector']}" is now visible on screen (${elapsed}ms).',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'audit_screen_health',
      description:
          'Performs an autonomous UI & layout audit on the active screen. Detects yellow-black striped RenderFlex '
          'overflow errors (e.g. "overflowed by 14px") and flags touch targets smaller than the standard 48x48 dp accessibility guideline.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.auditScreenHealth', {});
        if (res.isError) return res.toCallToolResult();
        final isHealthy = res.data?['isHealthy'] == true;
        final overflowCount = res.data?['overflowCount'] ?? 0;
        final a11yCount = res.data?['accessibilityIssueCount'] ?? 0;
        final overflows = res.data?['overflows'] as List? ?? [];
        final a11y = res.data?['accessibilityIssues'] as List? ?? [];

        if (isHealthy) {
          return CallToolResult(
            content: [
              TextContent(
                text: '🎉 **Screen Health Audit Passed!**\n- 0 Layout Overflows\n- 0 Accessibility Violations',
              ),
            ],
          );
        }

        final buffer = StringBuffer('⚠️ **Screen Health Issues Detected:**\n');
        if (overflowCount > 0) {
          buffer.writeln('\n### 🚨 Layout Overflows ($overflowCount):');
          for (final o in overflows) {
            buffer.writeln('- **${o['type']}**: ${o['details']}');
          }
        }
        if (a11yCount > 0) {
          buffer.writeln('\n### ♿ Accessibility / Tap Target Issues ($a11yCount):');
          for (final a in a11y) {
            buffer.writeln('- `${a['target']}` (${a['type']}): ${a['issue']}');
          }
        }

        return CallToolResult(content: [TextContent(text: buffer.toString())]);
      },
    );

    server.registerTool(
      'execute_action_chain',
      description:
          'Executes a batch sequence of UI actions (taps, text entries) inside the Flutter engine at native speed. '
          'Eliminates multi-turn LLM latency when the sequence of steps is already known.',
      inputSchema: ToolInputSchema(
        properties: {
          'actions': JsonSchema.array(
            items: JsonSchema.object(),
            description:
                'List of action objects, e.g. [{"action": "tap", "target": "Icon[\'menu\']"}, {"action": "enterText", "target": "TextField[\'Search\']", "text": "theme"}].',
          ),
        },
        required: ['actions'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.executeActionChain', {
          'actions': json.encode(p['actions']),
        });
        if (res.isError) return res.toCallToolResult();
        final executed = res.data?['executedCount'] ?? 0;
        final total = res.data?['totalActions'] ?? 0;
        return CallToolResult(
          content: [
            TextContent(
              text: '⚡ Action Chain executed successfully: $executed/$total actions completed natively.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'tap_and_wait',
      description:
          'Macro composite tool: Taps a target widget and immediately waits for an expected widget '
          'to appear. Replaces 2 separate round-trip tool calls with 1 fast step.',
      inputSchema: ToolInputSchema(
        properties: {
          'target': JsonSchema.string(
            description:
                'Key, semantic selector, or text of the widget to tap (e.g. "login_btn", "Button[\'Submit\']").',
          ),
          'expect': JsonSchema.string(
            description:
                'Key, semantic selector, or text of the widget expected to appear (e.g. "home_dashboard", "Text[\'Welcome\']").',
          ),
          'timeout': JsonSchema.integer(
            description: 'Timeout in milliseconds to wait for the expected widget (default: 5000ms).',
          ),
        },
        required: ['target', 'expect'],
      ),
      callback: (p, e) async {
        final target = p['target'].toString();
        final expectKey = p['expect'].toString();
        final timeoutMs = (p['timeout'] as num?)?.toInt() ?? 5000;

        final tapRes = await _callExtensionRaw('ext.flutterpilot.tapWidget', {'key': target});
        if (tapRes.isError) return tapRes.toCallToolResult();

        final waitRes = await _callExtensionRaw('ext.flutterpilot.waitForWidget', {
          'key': expectKey,
          'timeoutMs': timeoutMs.toString(),
        });
        if (waitRes.isError) return waitRes.toCallToolResult();

        return CallToolResult(
          content: [
            TextContent(
              text: '⚡ Tapped "$target" and successfully waited for "$expectKey" to appear.',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'enter_text_and_submit',
      description:
          'Macro composite tool: Enters text into an input field and immediately taps a submit button. '
          'Executes both steps in a single tool call.',
      inputSchema: ToolInputSchema(
        properties: {
          'target': JsonSchema.string(
            description:
                'Key or semantic selector of the text field (e.g. "email_input", "TextField[\'Email\']").',
          ),
          'text': JsonSchema.string(
            description: 'Text string to enter into the field.',
          ),
          'submitTarget': JsonSchema.string(
            description:
                'Key or semantic selector of the submit button to tap after entering text (e.g. "submit_btn", "Button[\'Continue\']").',
          ),
        },
        required: ['target', 'text', 'submitTarget'],
      ),
      callback: (p, e) async {
        final target = p['target'].toString();
        final text = p['text'].toString();
        final submitTarget = p['submitTarget'].toString();

        final enterRes = await _callExtensionRaw('ext.flutterpilot.enterText', {
          'key': target,
          'text': text,
        });
        if (enterRes.isError) return enterRes.toCallToolResult();

        final tapRes = await _callExtensionRaw('ext.flutterpilot.tapWidget', {
          'target': submitTarget,
        });
        if (tapRes.isError) return tapRes.toCallToolResult();

        return CallToolResult(
          content: [
            TextContent(
              text: '⚡ Entered text into "$target" and tapped "$submitTarget".',
            ),
          ],
        );
      },
    );

    server.registerTool(
      'fill_form_batch',
      description:
          'Atomic Form Auto-Filler Macro: Fills multiple input fields and toggles checkboxes/switches '
          'in a single frame pass (<5ms) and optionally submits. Reduces 5+ agent turns to 1.',
      inputSchema: ToolInputSchema(
        properties: {
          'fields': JsonSchema.object(
            description:
                'Map of field targets (keys/selectors) to values (string for TextFields, bool for Checkboxes/Switches). '
                'Example: {"TextField[\'Email\']": "alice@test.com", "Checkbox[\'Terms\']": true}',
          ),
          'submitTarget': JsonSchema.string(
            description:
                'Optional key or selector of the submit button to tap after filling all fields.',
          ),
        },
        required: ['fields'],
      ),
      callback: (p, e) async {
        final fields = p['fields'];
        final submitTarget = p['submitTarget']?.toString();

        final res = await _callExtensionRaw('ext.flutterpilot.fillForm', {
          'fields': jsonEncode(fields),
          'submitWith': ?submitTarget,
        });

        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              text: '⚡ Form filled successfully: ${jsonEncode(res.data)}',
            ),
          ],
        );
      },
    );
  }
}
