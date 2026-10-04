part of '../../flutterpilot_server.dart';

/// Renders the capped `widgetDiff` block (see
/// `PilotWidgetInspector.diffWidgetTrees`) into a short summary line plus a
/// handful of sample changes. Empty string when nothing changed.
String _widgetDiffSummary(Map<String, dynamic>? widgetDiff) {
  if (widgetDiff == null || widgetDiff['hasChanges'] != true) return '';
  final added = widgetDiff['addedCount'] ?? 0;
  final removed = widgetDiff['removedCount'] ?? 0;
  final modified = widgetDiff['modifiedCount'] ?? 0;
  final buffer = StringBuffer(
    ' Widget tree: +$added / -$removed / ~$modified.',
  );
  final samples = <String>[
    ...(widgetDiff['added'] as List? ?? const []).map((s) => '+ $s'),
    ...(widgetDiff['modified'] as List? ?? const []).map((s) => '~ $s'),
    ...(widgetDiff['removed'] as List? ?? const []).map((s) => '- $s'),
  ];
  if (samples.isNotEmpty) {
    buffer.write('\n  ${samples.take(5).join('\n  ')}');
  }
  if (widgetDiff['note'] != null) {
    buffer.write('\n  (${widgetDiff['note']})');
  }
  return buffer.toString();
}

/// Formats the `delta` block (route change + widget-tree diff) that
/// mutating SDK extensions attach to their response into a postcondition
/// summary, so the agent gets "did this do anything" for free instead of
/// needing a follow-up get_widget_tree/capture_screenshot round-trip.
/// Only falls back to suggesting a screenshot when truly nothing
/// observable changed — no route change and no widget-tree diff.
/// " Route unchanged (/home)." — but never claims "unchanged" for a route
/// the app can't name (no page in a Navigator): a navigation may have
/// happened unseen.
String _unchangedRoute(Object? route) => route == null || route == 'Unknown'
    ? ' Route unknown (no page in a Navigator), so a navigation would not '
          'show here: read the widget diff.'
    : ' Route unchanged ($route).';

/// What the screen shows once the action settled: the tappable elements,
/// new errors, and whether it was still moving when read.
String _screenNow(Map<String, dynamic>? data) {
  final post = data?['postActionState'] as Map<String, dynamic>?;
  final buffer = StringBuffer();
  final elements = post?['visibleInteractiveElements'] as List?;
  if (elements != null && elements.isNotEmpty) {
    buffer.write(
      '\nTappable now (${post!['interactiveElementsCount']}): '
      '${elements.map((e) => '"$e"').join(', ')}',
    );
  }
  if (post?['stillMoving'] == true) {
    buffer.write(
      '\nThe screen was still moving 2 s after the action (a looping '
      'animation?), so the above may be mid-motion.',
    );
  }
  if (post?['loading'] == true) {
    buffer.write(
      '\nA progress indicator is showing: results may still be loading; '
      'wait_for them.',
    );
  }
  final newErrors = post?['newErrorCount'];
  if (newErrors is int && newErrors > 0) {
    buffer.write('\n⚠️ $newErrors new error(s) — call get_errors.');
  }
  return buffer.toString();
}

/// Said when an action changed nothing, even after being watched for a
/// late effect ([delta] `quietMs`); empty otherwise.
String _quietNote(Map<String, dynamic>? delta) {
  final ms = delta?['quietMs'];
  if (ms is! int) return '';
  return ' Nothing changed in the ${(ms / 1000).toStringAsFixed(1)} s after '
      'it either. If it starts slow work (a request), wait_for the result '
      '(or pass waitFor).';
}

String _formatActionDelta(Map<String, dynamic>? data, {required String verb}) {
  final delta = data?['delta'] as Map<String, dynamic>?;
  if (delta == null) return '$verb.';
  final navigated = delta['navigated'] == true;
  final diffText = _widgetDiffSummary(
    delta['widgetDiff'] as Map<String, dynamic>?,
  );

  final buffer = StringBuffer(verb);
  if (navigated) {
    buffer.write(
      '. Route changed: ${delta['fromRoute']} → ${delta['toRoute']}.',
    );
  } else {
    buffer.write('.${_unchangedRoute(delta['toRoute'] ?? delta['fromRoute'])}');
  }
  buffer.write(diffText);
  buffer.write(_quietNote(delta));
  if (!navigated && diffText.isEmpty && delta['quietMs'] == null) {
    buffer.write(
      ' No widget-tree changes detected either. HINT: If you expected a purely '
      'visual-only change (color, animation frame, pixel-level effect with no '
      'structural diff), call capture_screenshot to confirm.',
    );
  }
  buffer.write(_screenNow(data));
  return buffer.toString();
}

/// Tools for tapping, typing, scrolling, swiping, and other UI interactions.
mixin _UiAutomationToolsMixin on _FlutterPilotServerBase {
  /// Tools execute_action_chain runs: the ones that drive or check the
  /// screen, each answering as when called alone.
  static const _chainStepTools = {
    'tap_widget',
    'enter_text',
    'press_key',
    'scroll_into_view',
    'swipe_widget',
    'drag_widget',
    'toggle_checkbox',
    'set_slider_value',
    'fill_form',
    'navigate_to',
    'assert_widget',
    'wait_for',
  };

  String _formatActionFeedback(
    String actionName,
    Map<String, dynamic> params,
    _ExtensionResult res,
  ) {
    final target =
        res.data?['target'] ??
        res.data?['key'] ??
        params['key'] ??
        params['identifier'] ??
        params['text'] ??
        '';
    final postState = res.data?['postActionState'] as Map<String, dynamic>?;
    final delta = res.data?['delta'] as Map<String, dynamic>?;
    final buffer = StringBuffer();
    final targetStr = target.toString();
    buffer.write('$actionName${targetStr.isNotEmpty ? ' "$targetStr"' : ''}.');
    // E.g. it closed the on-screen keyboard to reach the target.
    final note = res.data?['note'];
    if (note is String) buffer.write(' $note');
    final route = postState?['route'] ?? delta?['toRoute'];
    final changed =
        postState?['routeChanged'] == true || delta?['navigated'] == true;
    if (route != null) {
      buffer.write(
        changed
            ? ' Route changed: ${delta?['fromRoute'] ?? postState?['previousRoute'] ?? '?'} → $route.'
            : _unchangedRoute(route),
      );
    }
    // What appeared/disappeared, so the agent rarely needs a follow-up read.
    buffer.write(
      _widgetDiffSummary(delta?['widgetDiff'] as Map<String, dynamic>?),
    );
    buffer.write(_quietNote(delta));
    buffer.write(_screenNow(res.data));
    // A permission alert is not part of the Flutter tree (and doesn't even
    // change the app's lifecycle on iOS): an action that "did nothing" may
    // have opened one.
    final diff = delta?['widgetDiff'] as Map<String, dynamic>?;
    if (actionName.toLowerCase().contains('tap') &&
        !changed &&
        diff != null &&
        _widgetDiffSummary(diff).isEmpty &&
        _allTools['native_describe_screen']?.enabled == true) {
      buffer.write(
        '\nNothing changed in the app. If this opens a system alert '
        '(permissions, sign-in), native_describe_screen shows it.',
      );
    }
    return buffer.toString().trim();
  }

  void _registerUiAutomationTools() {
    _tool(
      'tap_widget',
      description:
          'Taps a widget found by key, selector (e.g. '
          '"ElevatedButton[\'Log In\']") or visible text, scrolling to it '
          'first — or taps at x/y. '
          'Exact text wins; text that several widgets merely contain is '
          'refused with the candidates. Reports the route change, a '
          'widget-tree diff and what is tappable now.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'Key, selector, visible text or icon name '
                '("IconButton[\'settings\']").',
          ),
          'identifier': JsonSchema.string(
            description: 'Semantics identifier (Flutter 3.19+).',
          ),
          'semanticsId': JsonSchema.integer(
            description: 'SemanticsNode id from get_semantics_tree.',
          ),
          'text': JsonSchema.string(
            description: 'Visible text inside the widget.',
          ),
          'type': JsonSchema.string(
            description: 'Widget type, e.g. "IconButton".',
          ),
          'x': JsonSchema.number(
            description: 'X in logical pixels (top-left origin), with y.',
          ),
          'y': JsonSchema.number(description: 'Y in logical pixels.'),
          'gesture': JsonSchema.string(
            enumValues: ['tap', 'double', 'long', 'secondary'],
            description:
                'Default tap. long takes durationMs; secondary is a right-click '
                '(context menus).',
          ),
          'durationMs': JsonSchema.integer(
            description: 'Long-press duration (default 600).',
          ),
          'waitFor': JsonSchema.string(
            description:
                'A widget (key, selector or text) to wait for after the tap, in '
                'place of a separate wait_for call.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'How long to wait for waitFor (default 5000).',
          ),
        },
      ),
      callback: (p, e) async {
        final gesture = p['gesture']?.toString() ?? 'tap';
        final target = p['target'] ?? p['key'];
        final String extension;
        final Map<String, dynamic> args;
        final String verb;
        switch (gesture) {
          case 'tap':
            extension = 'ext.flutterpilot.tapWidget';
            args = Map.of(p)
              ..remove('gesture')
              ..remove('waitFor')
              ..remove('timeoutMs');
            verb = 'Widget tapped';
          case 'secondary':
            extension = 'ext.flutterpilot.secondaryTapWidget';
            args = Map.of(p)
              ..remove('gesture')
              ..remove('waitFor')
              ..remove('timeoutMs');
            verb = 'Secondary tap';
          case 'double' || 'long':
            if (target == null) {
              return CallToolResult(
                isError: true,
                content: [
                  TextContent(
                    text:
                        'A $gesture tap needs a key (key, selector or text), not coordinates.',
                  ),
                ],
              );
            }
            extension = gesture == 'double'
                ? 'ext.flutterpilot.doubleTapWidget'
                : 'ext.flutterpilot.longPressWidget';
            args = {
              'key': target.toString(),
              if (gesture == 'long' && p['durationMs'] != null)
                'durationMs': p['durationMs'].toString(),
            };
            verb = gesture == 'double' ? 'Double-tapped' : 'Long-pressed';
          default:
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text:
                      'Unknown gesture "$gesture": use tap, double, long or secondary.',
                ),
              ],
            );
        }
        final res = await _callExtensionRaw(extension, args);
        if (res.isError) return res.toCallToolResult();
        final waitFor = p['waitFor']?.toString();
        if (waitFor == null || waitFor.isEmpty) {
          return CallToolResult(
            content: [TextContent(text: _formatActionFeedback(verb, p, res))],
          );
        }
        final fromRoute =
            (res.data?['delta'] as Map<String, dynamic>?)?['fromRoute'];
        final waitRes = await _callExtensionRaw(
          'ext.flutterpilot.waitForWidget',
          {
            'key': waitFor,
            'timeoutMs': ((p['timeoutMs'] as num?)?.toInt() ?? 5000).toString(),
            'previousRoute': ?fromRoute?.toString(),
          },
        );
        if (waitRes.isError) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    '${_formatActionFeedback(verb, p, res)}\nBut "$waitFor" '
                    'did not appear: ${waitRes.errorMessage}',
              ),
            ],
          );
        }
        // Report the screen after the wait, not the one right after the tap.
        return CallToolResult(
          content: [
            TextContent(
              text: _formatActionFeedback(
                '$verb${target != null ? ' "$target"' : ''}; then appeared',
                const {},
                waitRes,
              ),
            ),
          ],
        );
      },
    );

    _tool(
      'enter_text',
      description:
          'Types text into a text field found by key, selector (e.g. '
          '"TextField[\'Email\']") or label — or into the focused field '
          'when no key is given — replacing what it holds. Fires '
          'onChanged; press_key("enter") afterwards submits.',
      inputSchema: ToolInputSchema(
        properties: {
          'text': JsonSchema.string(
            description: 'The text to enter ("" clears the field).',
          ),
          'key': JsonSchema.string(
            description:
                'Key, selector or label of the field. Omit for the focused '
                'field.',
          ),
          'identifier': JsonSchema.string(
            description: 'Semantics identifier of the text field.',
          ),
          'clearFirst': JsonSchema.boolean(
            description:
                'Clear the existing text before typing (default true).',
          ),
        },
        required: ['text'],
      ),
      callback: (p, e) async {
        final target = p['target'] ?? p['key'];
        if (p['text']?.toString() == '' && target != null) {
          final res = await _callExtensionRaw(
            'ext.flutterpilot.clearTextField',
            {'key': target.toString()},
          );
          return res.isError
              ? res.toCallToolResult()
              : CallToolResult(
                  content: [TextContent(text: 'Cleared "$target".')],
                );
        }
        final res = await _callExtensionRaw('ext.flutterpilot.enterText', {
          ...p,
          if (target == null) 'focused_element': true,
        });
        if (res.isError) return res.toCallToolResult();
        return CallToolResult(
          content: [
            TextContent(
              // Echo the SDK's copy of the text: it masks password fields.
              text: _formatActionFeedback(
                'Typed "${res.data?['text'] ?? ''}" into',
                {'key': target ?? 'the focused field'},
                res,
              ),
            ),
          ],
        );
      },
    );

    _tool(
      'press_key',
      description:
          'Presses a key on the focused widget: enter (submits a text '
          'field), tab, escape (closes menus and dialogs), arrows, a '
          'character, or a shortcut with modifiers. "back" is the system '
          'back button: it pops the route and never quits the app from '
          'the root. In a focused text field keys edit it as typing '
          'would, and the response shows the field\'s text and cursor; '
          'enter_text sets a whole value.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'E.g. "enter", "tab", "escape", "back", "arrowDown", "space", '
                '"backspace", or a single character.',
          ),
          'modifiers': JsonSchema.array(
            items: JsonSchema.string(),
            description:
                'Optional modifier keys: "shift", "ctrl", "alt", "meta".',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        if (p['key']?.toString().toLowerCase() == 'back') {
          final res = await _callExtensionRaw('ext.flutterpilot.pressBack', {});
          if (res.isError) return res.toCallToolResult();
          final popped = res.data?['popped'] as bool? ?? false;
          return CallToolResult(
            content: [
              TextContent(
                text: popped
                    ? _formatActionFeedback('Back pressed', const {}, res)
                    : 'Back pressed — already at root (nothing to pop).',
              ),
            ],
          );
        }
        final callParams = <String, dynamic>{'key': p['key']};
        if (p['modifiers'] != null) {
          final mods = p['modifiers'];
          callParams['modifiers'] = mods is List
              ? mods.join(',')
              : mods.toString();
        }
        final res = await _callExtensionRaw(
          'ext.flutterpilot.pressKey',
          callParams,
        );
        if (res.isError) return res.toCallToolResult();
        final feedback = _formatActionFeedback(
          'Key "${p['key']}" pressed on',
          p,
          res,
        );
        // In a text field, say what the field holds now: the diff above only
        // tracks widgets, and a cursor move changes no widget.
        final field = res.data?['field'] as Map<String, dynamic>?;
        if (field == null) {
          return CallToolResult(content: [TextContent(text: feedback)]);
        }
        final start = field['selectionStart'];
        final end = field['selectionEnd'];
        final cursor = start == end
            ? 'cursor at $start'
            : 'selected $start–$end';
        return CallToolResult(
          content: [
            TextContent(
              text:
                  '$feedback\nField: "${field['text']}" ($cursor)'
                  '${field['changed'] == true ? '' : ', unchanged'}.',
            ),
          ],
        );
      },
    );

    _tool(
      'pinch_zoom',
      description:
          'Two-finger pinch on a widget or at x/y. Reports what changed.',
      inputSchema: ToolInputSchema(
        properties: {
          'scale': JsonSchema.number(
            description: 'Above 1 zooms in, below 1 zooms out.',
          ),
          'key': JsonSchema.string(
            description: 'Key or selector of the widget.',
          ),
          'identifier': JsonSchema.string(
            description: 'Semantics identifier of the target widget.',
          ),
          'x': JsonSchema.number(description: 'Center of the pinch, with y.'),
          'y': JsonSchema.number(),
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
            TextContent(text: _formatActionFeedback('Pinch zoom', p, res)),
          ],
        );
      },
    );

    _tool(
      'scroll_into_view',
      description:
          'Scrolls the lists on screen until the widget (key, selector or '
          'text) is on screen, including items a lazy list has not built yet '
          'and cards in a horizontal list inside a vertical one. tap_widget '
          'already does this before tapping.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key, selector or text of the widget.',
          ),
        },
      ),
      callback: (p, e) => _callExtensionRaw(
        'ext.flutterpilot.scrollIntoView',
        p,
      ).then((res) => res.toCallToolResult()),
    );

    _tool(
      'swipe_widget',
      description:
          'Swipes on a widget up/down/left/right: scroll a list, dismiss a '
          'card, open a drawer, pull to refresh (down on a list at its top). '
          'Reports what changed.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key or selector of the widget to swipe on.',
          ),
          'direction': JsonSchema.string(
            enumValues: ['up', 'down', 'left', 'right'],
          ),
          'distance': JsonSchema.number(
            description:
                'Scroll distance in logical pixels. Positive = down/right, negative = up/left.',
          ),
        },
        required: ['direction'],
      ),
      callback: (p, e) async {
        final args = {
          'key': (p['key'] ?? p['target']).toString(),
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
              text: _formatActionDelta(
                res.data,
                verb: res.data?['pullToRefresh'] == true
                    ? 'Pulled to refresh'
                    : 'Swipe complete',
              ),
            ),
          ],
        );
      },
    );

    _tool(
      'drag_widget',
      description:
          'Drags one widget onto another (drag-and-drop, reordering). Reports '
          'what changed.',
      inputSchema: ToolInputSchema(
        properties: {
          'fromKey': JsonSchema.string(
            description: 'Key or selector of the widget to drag.',
          ),
          'toKey': JsonSchema.string(
            description: 'Key or selector of the widget to drop it on.',
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
              text: _formatActionDelta(res.data, verb: 'Drag complete'),
            ),
          ],
        );
      },
    );

    _tool(
      'focus_widget',
      description:
          'Focuses the widget found by key (opens the software keyboard for a '
          'TextField). Without a key, removes focus from everything and '
          'dismisses the keyboard.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key or selector. Omit to unfocus everything.',
          ),
        },
      ),
      callback: (p, e) async {
        final target = p['target'] ?? p['key'];
        if (target == null) {
          final res = await _callExtensionRaw(
            'ext.flutterpilot.unfocusAll',
            {},
          );
          return res.isError
              ? res.toCallToolResult()
              : CallToolResult(
                  content: [
                    TextContent(text: 'Focus removed; keyboard dismissed.'),
                  ],
                );
        }
        final res = await _callExtensionRaw('ext.flutterpilot.focusWidget', {
          'key': target.toString(),
        });
        return res.isError
            ? res.toCallToolResult()
            : CallToolResult(
                content: [TextContent(text: 'Focused "$target".')],
              );
      },
    );

    _tool(
      'set_slider_value',
      description:
          'Moves a Slider to a value (clamped to its min/max) the way a user '
          'would, so onChanged fires.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key or selector of the Slider.',
          ),
          'value': JsonSchema.number(),
        },
        required: ['value'],
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.setSliderValue', {
          'key': (p['key'] ?? p['target']).toString(),
          'value': p['value'].toString(),
        });
        return res.toCallToolResult();
      },
    );

    _tool(
      'toggle_checkbox',
      description:
          'Toggles the Checkbox, Switch or Radio under the key, also one '
          'inside a tappable row, where tap_widget would tap the row. The '
          'response shows its new value (= true/false).',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'Key, selector or label of the toggle, or of the row that '
                'holds it.',
          ),
        },
      ),
      callback: (p, e) async {
        final res = await _callExtensionRaw('ext.flutterpilot.toggleCheckbox', {
          'key': (p['key'] ?? p['target']).toString(),
        });
        return res.isError
            ? res.toCallToolResult()
            : CallToolResult(
                content: [
                  TextContent(
                    text: _formatActionDelta(res.data, verb: 'Toggled'),
                  ),
                ],
              );
      },
    );

    _tool(
      'fill_form',
      description:
          'Fills several fields in one call and optionally taps a submit '
          'button: text for text fields, true/false for checkboxes and '
          'switches. Reports the route change and widget-tree diff.',
      inputSchema: ToolInputSchema(
        properties: {
          'fields': JsonSchema.object(
            description:
                'Map of field key/selector to value, e.g. {"TextField[\'Email\']": "a@b.dev", "Checkbox[\'Terms\']": true}.',
          ),
          'submitWith': JsonSchema.string(
            description:
                'Optional key/selector of the button to tap after filling (e.g. "ElevatedButton[\'Log In\']").',
          ),
        },
        required: ['fields'],
      ),
      callback: (p, e) async {
        final submit = p['submitWith'] ?? p['submitTarget'];
        final res = await _callExtensionRaw('ext.flutterpilot.fillForm', {
          'fields': json.encode(p['fields']),
          if (submit != null) 'submitWith': submit.toString(),
        });
        if (res.isError) return res.toCallToolResult();
        final filled = res.data?['fieldsFilled'] ?? 0;
        final total = res.data?['totalFields'] ?? 0;
        final submitted = res.data?['submitted'] == true;
        final delta = res.data?['delta'] as Map<String, dynamic>?;
        final navigated = delta?['navigated'] == true;
        final routeNote = navigated
            ? ' Route changed: ${delta?['fromRoute']} → ${delta?['toRoute']}.'
            : submitted
            ? _unchangedRoute(delta?['toRoute'])
            : '';
        final diffNote = _widgetDiffSummary(
          delta?['widgetDiff'] as Map<String, dynamic>?,
        );
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Filled $filled/$total fields${submitted ? ' and tapped submit.' : '.'}'
                  '$routeNote$diffNote${_quietNote(delta)}${_screenNow(res.data)}',
            ),
          ],
        );
      },
    );

    _tool(
      'wait_for',
      description:
          'Waits for one condition, polling (never a blind sleep), and '
          'fails with the reason on timeout: a widget on screen (key), a '
          'route, settled animations, a Riverpod/Bloc value (state + '
          'expectedValue) or a number of frames.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key, selector or text that must be on screen.',
          ),
          'route': JsonSchema.string(
            description: 'The route to be on, e.g. "/dashboard".',
          ),
          'animations': JsonSchema.boolean(
            description: 'Until animations and frame callbacks have settled.',
          ),
          'state': JsonSchema.string(
            description:
                'Provider or bloc name from get_state, with expectedValue '
                '(needs the Riverpod or Bloc plugin).',
          ),
          'expectedValue': JsonSchema.string(
            description: 'Substring expected in the state\'s value.',
          ),
          'frames': JsonSchema.integer(
            description: 'Pump this many frames (1–120).',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Default 5000 (3000 for key).',
          ),
        },
      ),
      callback: (p, e) async {
        final timeout = p['timeoutMs']?.toString();
        final selector = p['selector'] ?? p['target'] ?? p['key'];
        if (selector != null) {
          final res = await _callExtensionRaw(
            'ext.flutterpilot.waitForCondition',
            {'selector': selector.toString(), 'timeoutMs': ?timeout},
          );
          if (res.isError) return res.toCallToolResult();
          return CallToolResult(
            content: [
              TextContent(
                text:
                    '"$selector" is on screen (${res.data?['elapsedMs'] ?? 0}ms).',
              ),
            ],
          );
        }
        if (p['route'] != null) {
          return (await _callExtensionRaw('ext.flutterpilot.waitForRoute', {
            'route': p['route'].toString(),
            'timeoutMs': ?timeout,
          })).toCallToolResult();
        }
        if (p['state'] != null) {
          return (await _callExtensionRaw('ext.flutterpilot.waitForState', {
            'type': await _stateTypeOf(p['state'].toString()),
            'name': p['state'].toString(),
            'expectedValue': p['expectedValue']?.toString() ?? '',
            'timeoutMs': ?timeout,
          })).toCallToolResult();
        }
        if (p['frames'] != null) {
          final count = ((p['frames'] as num).toInt()).clamp(1, 120);
          return (await _callExtensionRaw('ext.flutterpilot.pumpFrames', {
            'count': count.toString(),
          })).toCallToolResult();
        }
        if (p['animations'] == true) {
          return (await _callExtensionRaw('ext.flutterpilot.waitForAnimation', {
            'timeoutMs': ?timeout,
          })).toCallToolResult();
        }
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text:
                  'Say what to wait for: key, route, animations: true, state '
                  '(with expectedValue) or frames.',
            ),
          ],
        );
      },
    );

    _tool(
      'audit_screen_health',
      description:
          'Layout and accessibility check of the current screen: layout '
          'overflows, tap targets under the platform minimum (48dp phones, '
          '24px desktop/web), controls a screen reader can\'t name (no '
          'label/tooltip), text below WCAG contrast (4.5:1, large 3:1, from '
          'the rendered pixels), and where the screen reader order jumps back '
          'up. Each with position and source file:line. Use after '
          'set_app_settings(textScale/locale/theme) or a UI change.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.auditScreenHealth',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        final data = res.data ?? const {};
        List<dynamic> list(String key) => data[key] as List? ?? const [];
        final overflows = list('overflows');
        final targets = list('accessibilityIssues');
        final unlabeled = list('unlabeled');
        final contrast = list('lowContrast');
        final jumps = list('readingOrderJumps');
        final order = list('readingOrder');
        final buffer = StringBuffer();
        void section(
          String title,
          List<dynamic> items,
          String Function(dynamic) line,
        ) {
          if (items.isEmpty) return;
          buffer.writeln('$title (${items.length}):');
          for (final item in items.take(12)) {
            buffer.writeln('- ${line(item)}');
          }
          if (items.length > 12) {
            buffer.writeln('- … ${items.length - 12} more');
          }
        }

        section(
          'Layout overflows',
          overflows,
          (o) => '${o['type']}: ${o['details']}',
        );
        section(
          'Small tap targets',
          targets,
          (a) => '`${a['target']}` (${a['type']}): ${a['issue']}',
        );
        section('Controls without a label', unlabeled, (u) => '$u');
        section('Low contrast text', contrast, (c) => '$c');
        section('Reading order jumps', jumps, (j) => '$j');
        if (buffer.isEmpty) {
          buffer.writeln(
            'No layout overflows, small tap targets, unlabeled controls, '
            'low-contrast text or reading order jumps.',
          );
        }
        if (order.isNotEmpty) {
          final shown = order.take(15).join(' → ');
          buffer.writeln(
            'Screen reader order (${order.length} controls): $shown'
            '${order.length > 15 ? ' → …' : ''}',
          );
        }
        if (data['semanticsNote'] != null) {
          buffer.writeln(data['semanticsNote']);
        }
        return CallToolResult(
          content: [TextContent(text: buffer.toString().trim())],
        );
      },
    );

    _tool(
      'execute_action_chain',
      description:
          'Runs a known sequence of steps in one call, stopping at the first '
          'that fails: taps, text, keys, scrolls, navigation, and wait_for / '
          'assert_widget checks between them. Returns each step\'s outcome '
          'and the screen after the last one (route, diff, tappable '
          'elements).',
      inputSchema: ToolInputSchema(
        properties: {
          'steps': JsonSchema.array(
            items: JsonSchema.object(),
            description:
                'Tool calls run in order, e.g. [{"tool": "tap_widget", '
                '"arguments": {"key": "New note"}}, {"tool": "enter_text", '
                '"arguments": {"key": "Title", "text": "Groceries"}}, '
                '{"tool": "assert_widget", "arguments": {"text": "Saved"}}]. '
                'Tools: ${(_chainStepTools.toList()..sort()).join(', ')}.',
          ),
        },
        required: ['steps'],
      ),
      callback: (p, e) async {
        CallToolResult error(String text) =>
            CallToolResult(isError: true, content: [TextContent(text: text)]);
        final steps = <({String tool, Map<String, dynamic> arguments})>[];
        for (final s in (p['steps'] as List?) ?? const []) {
          final step = chainStep(s);
          if (step == null ||
              !_chainStepTools.contains(step.tool) ||
              !_toolCallbacks.containsKey(step.tool)) {
            return error(
              'Step ${steps.length + 1}: '
              '${step == null ? 'not a {"tool": ..., "arguments": {...}} step' : '"${step.tool}" can\'t run in a chain'}. '
              'Tools: ${(_chainStepTools.where(_toolCallbacks.containsKey).toList()..sort()).join(', ')}.',
            );
          }
          steps.add(step);
        }
        if (steps.isEmpty) return error('steps is empty.');

        // Taps and text entries alone run inside the app, in one round trip.
        final inApp = [for (final step in steps) ?inAppChainAction(step)];
        if (inApp.length == steps.length) {
          final res = await _callExtensionRaw(
            'ext.flutterpilot.executeActionChain',
            {'actions': json.encode(inApp)},
          );
          if (res.isError) return res.toCallToolResult();
          final executed = res.data?['executedCount'] ?? 0;
          final total = res.data?['totalActions'] ?? 0;
          final failure = res.data?['failure'] as String?;
          final buffer = StringBuffer(
            failure == null
                ? 'Action chain: $executed/$total steps done.\n'
                : 'Action chain stopped after $executed/$total steps. '
                      '$failure\nRemaining steps were skipped. State now:\n',
          );
          for (final step in (res.data?['steps'] as List?) ?? const []) {
            if (step is Map && step['note'] is String) {
              buffer.write('Step ${step['index']}: ${step['note']}\n');
            }
          }
          buffer.write(_formatActionFeedback('Chain finished', const {}, res));
          return CallToolResult(
            isError: failure != null,
            content: [TextContent(text: buffer.toString())],
          );
        }

        // Anything else: one tool after the other, each as if called alone.
        final outcomes = <String>[];
        var failed = false;
        for (final step in steps) {
          final res = await _toolCallbacks[step.tool]!(
            Map.of(step.arguments),
            e,
          );
          final text = res.content
              .whereType<TextContent>()
              .map((c) => c.text)
              .join('\n');
          failed = res.isError == true;
          // A check inside a chain is evidence like one called alone (the
          // chain itself is recorded as the action).
          if (Verification.checks.contains(step.tool)) {
            _verification?.record(
              step.tool,
              step.arguments,
              text,
              isError: failed,
            );
          }
          outcomes.add(text);
          if (failed) break;
        }
        return CallToolResult(
          isError: failed,
          content: [
            TextContent(
              text: describeChain(
                [for (final step in steps) step.tool],
                outcomes,
                failed: failed,
              ),
            ),
          ],
        );
      },
    );
  }
}
