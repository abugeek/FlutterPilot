part of '../../fp_server.dart';

/// Renders the capped `widgetDiff` block (see
/// `PilotWidgetInspector.diffWidgetTrees`) into a short summary line plus a
/// handful of sample changes. Empty string when nothing changed.
String _widgetDiffSummary(Map<String, dynamic>? widgetDiff) {
  if (widgetDiff == null || widgetDiff['hasChanges'] != true) return '';
  final added = widgetDiff['addedCount'] ?? 0;
  final removed = widgetDiff['removedCount'] ?? 0;
  final modified = widgetDiff['modifiedCount'] ?? 0;
  final moved = widgetDiff['movedCount'] ?? 0;
  final counts =
      '+$added / -$removed / ~$modified${moved > 0 ? ' / ↕$moved shifted' : ''}';
  final buffer = StringBuffer(' Widget tree: $counts.');
  final samples = <String>[
    ...(widgetDiff['added'] as List? ?? const []).map((s) => '+ $s'),
    ...(widgetDiff['modified'] as List? ?? const []).map((s) => '~ $s'),
    ...(widgetDiff['removed'] as List? ?? const []).map((s) => '- $s'),
    ...(widgetDiff['moved'] as List? ?? const []).map((s) => '↕ $s'),
  ];
  if (samples.isNotEmpty) {
    buffer.write('\n  ${samples.take(5).join('\n  ')}');
  }
  if (widgetDiff['note'] case final String note) {
    // The counts are in the line above; the SDK's note repeats them and how
    // to read on, 190 characters on every tap that rebuilds a list.
    buffer.write(
      note.contains('total node changes')
          ? '\n  (a bulk rebuild: these are samples)'
          : '\n  ($note)',
    );
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
String _screenNow(Map<String, dynamic>? data, {ScreenMemory? memory}) {
  final post = data?['postActionState'] as Map<String, dynamic>?;
  final buffer = StringBuffer();
  final elements = post?['visibleInteractiveElements'] as List?;
  if (elements != null && elements.isNotEmpty) {
    final count = (post!['interactiveElementsCount'] as num?)?.toInt();
    final shown = [for (final e in elements) '$e'];
    buffer.write(
      '\n${(memory ?? ScreenMemory()).tappable(shown, count ?? shown.length)}',
    );
  }
  final draft = post?['draft'];
  if (draft is String && draft.isNotEmpty) {
    buffer.write('\nDraft: ${Redaction.text(draft)}');
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
      'it either; if it starts slow work (a request), wait_for the result.';
}

String _formatActionDelta(
  Map<String, dynamic>? data, {
  required String verb,
  ScreenMemory? memory,
}) {
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
      ' No widget-tree change either; for a purely visual one (a color, an '
      'animation frame), capture_screenshot.',
    );
  }
  buffer.write(_screenNow(data, memory: memory));
  return buffer.toString();
}

/// Tools for tapping, typing, scrolling, swiping, and other UI interactions.
mixin _UiAutomationToolsMixin on _FlutterPilotServerBase {
  /// Tools execute_action_chain runs: the ones that drive or check the
  /// screen, each answering as when called alone — and the ones that set up
  /// what the screen is tested against (mocked responses and channels, the
  /// network, app settings). In the call log `mock_http_response` followed
  /// itself 37 times: each mock was an agent turn of its own.
  static const _chainStepTools = {
    'tap_widget',
    'enter_text',
    'press_key',
    'scroll_into_view',
    'gesture_widget',
    'toggle_checkbox',
    'fill_form',
    'navigate_to',
    'assert_widget',
    'wait_for',
    'mock_http_response',
    'mock_platform_channel',
    'simulate_network',
    'set_app_settings',
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
    // Tapping through to another screen is a route change: push it to
    // subscribers of the summary, the tree and the route (task 27).
    if (changed) _notifyRouteChanged();
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
    buffer.write(_screenNow(res.data, memory: _activeContext?.screenMemory));
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
          'Taps a widget by key, selector or text (scrolling first) or at x/y. '
          'Reports route change, widget diff and tappable elements now.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key, selector, visible text or icon name.',
          ),
          'mark': JsonSchema.integer(
            description: 'Mark number from capture_screenshot.',
          ),
          'identifier': JsonSchema.string(
            description: 'Semantics identifier.',
          ),
          'semanticsId': JsonSchema.integer(
            description: 'SemanticsNode id.',
          ),
          'text': JsonSchema.string(
            description: 'Visible text inside the widget.',
          ),
          'type': JsonSchema.string(
            description: 'Widget type, e.g. "IconButton".',
          ),
          'x': JsonSchema.number(
            description: 'X in logical pixels, with y.',
          ),
          'y': JsonSchema.number(description: 'Y in logical pixels.'),
          'gesture': JsonSchema.string(
            enumValues: ['tap', 'double', 'long', 'secondary'],
            description: 'Default tap (or double/long/secondary).',
          ),
          'durationMs': JsonSchema.integer(
            description: 'Long-press duration (default 600).',
          ),
          'waitFor': JsonSchema.string(
            description: 'Widget to wait for after tap.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Timeout for waitFor (default 5000).',
          ),
          'quickSettle': JsonSchema.boolean(
            description: 'Settle in <=400ms.',
          ),
          'settleTimeoutMs': JsonSchema.integer(
            description: 'Screen settle timeout in ms.',
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
            if (p['quickSettle'] != null) {
              args['quickSettle'] = p['quickSettle'].toString();
            }
            if (p['settleTimeoutMs'] != null) {
              args['settleTimeoutMs'] = p['settleTimeoutMs'].toString();
            }
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
          final feedback = _formatActionFeedback(verb, p, res);
          // A tap that changed nothing on a device nothing here can tap a
          // system dialog on: say what may have opened one.
          final dialog = feedback.contains('Nothing changed')
              ? await _permissionDialogHint()
              : null;
          return CallToolResult(
            content: [
              TextContent(
                text: dialog == null ? feedback : '$feedback\n$dialog',
              ),
            ],
          );
        }
        final fromRoute =
            (res.data?['delta'] as Map<String, dynamic>?)?['fromRoute'];
        // 5000 is waitForWidget's own default when timeoutMs is absent; that
        // literal carries a comment pointing back here
        // (fp_sdk/lib/src/extensions/navigation_extensions.dart).
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
          'Types text into a field by key, selector or label (or focused '
          'field). Fires onChanged; pass submit:true to press Enter, or '
          'waitFor to poll for a resulting widget.',
      inputSchema: ToolInputSchema(
        properties: {
          'text': JsonSchema.string(
            description: 'Text to enter ("" clears the field).',
          ),
          'key': JsonSchema.string(
            description: 'Key, selector or label. Omit for focused field.',
          ),
          'mark': JsonSchema.integer(
            description: 'Mark number from capture_screenshot.',
          ),
          'identifier': JsonSchema.string(
            description: 'Semantics id.',
          ),
          'clearFirst': JsonSchema.boolean(
            description: 'Clear existing text first (default true).',
          ),
          'submit': JsonSchema.boolean(
            description: 'Press Enter to submit.',
          ),
          'waitFor': JsonSchema.string(
            description: 'Widget or text to wait for.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Timeout in ms (default 5000).',
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
        final callParams = Map.of(p)
          ..remove('submit')
          ..remove('waitFor')
          ..remove('timeoutMs');
        final res = await _callExtensionRaw('ext.flutterpilot.enterText', {
          ...callParams,
          if (target == null) 'focused_element': true,
        });
        if (res.isError) return res.toCallToolResult();

        final shouldSubmit = p['submit'] == true;
        _ExtensionResult activeRes = res;
        if (shouldSubmit) {
          final pressRes = await _callExtensionRaw(
            'ext.flutterpilot.pressKey',
            {'key': 'enter'},
          );
          if (pressRes.isError) return pressRes.toCallToolResult();
          activeRes = pressRes;
        }

        final waitFor = p['waitFor']?.toString();
        if (waitFor != null && waitFor.isNotEmpty) {
          final timeout =
              ((p['timeoutMs'] as num?)?.toInt() ?? 5000).toString();
          final waitRes = await _callExtensionRaw(
            'ext.flutterpilot.waitForWidget',
            {'key': waitFor, 'timeoutMs': timeout},
          );
          if (waitRes.isError) {
            final verb = 'Typed "${res.data?['text'] ?? ''}" into';
            final prefix = _formatActionFeedback(
              verb,
              {'key': target ?? 'the focused field'},
              activeRes,
            );
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text:
                      '$prefix\nBut "$waitFor" did not appear: ${waitRes.errorMessage}',
                ),
              ],
            );
          }
        }

        final verb = 'Typed "${res.data?['text'] ?? ''}" into';
        final feedback = _formatActionFeedback(
          verb,
          {'key': target ?? 'the focused field'},
          activeRes,
        );
        final notes = <String>[
          if (shouldSubmit) 'submitted with Enter',
          if (waitFor != null && waitFor.isNotEmpty) 'settled on "$waitFor"',
        ];
        final suffix = notes.isEmpty ? '' : ' (${notes.join(', ')}).';
        return CallToolResult(
          content: [
            TextContent(
              text: '$feedback$suffix',
            ),
          ],
        );
      },
    );

    _tool(
      'press_key',
      description:
          'Presses a key on focused widget (enter, tab, escape, arrows, '
          'or "back" to pop). Use count to repeat; pass waitFor to await a '
          'widget.',
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
          'count': JsonSchema.integer(
            description: 'Number of times to press the key (1–20, default 1).',
          ),
          'waitFor': JsonSchema.string(
            description: 'Optional widget key/selector to wait for.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Timeout for waitFor in ms (default 5000).',
          ),
        },
        required: ['key'],
      ),
      callback: (p, e) async {
        final count = ((p['count'] as num?)?.toInt() ?? 1).clamp(1, 20);
        if (p['key']?.toString().toLowerCase() == 'back') {
          _ExtensionResult? lastRes;
          var popped = false;
          for (var i = 0; i < count; i++) {
            lastRes = await _callExtensionRaw('ext.flutterpilot.pressBack', {});
            if (lastRes.isError) return lastRes.toCallToolResult();
            if (lastRes.data?['popped'] == true) popped = true;
          }
          final res = lastRes!;
          return CallToolResult(
            content: [
              TextContent(
                text: popped
                    ? _formatActionFeedback(
                        count > 1 ? 'Back pressed x$count' : 'Back pressed',
                        const {},
                        res,
                      )
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
        _ExtensionResult? lastRes;
        for (var i = 0; i < count; i++) {
          lastRes = await _callExtensionRaw(
            'ext.flutterpilot.pressKey',
            callParams,
          );
          if (lastRes.isError) return lastRes.toCallToolResult();
        }
        final res = lastRes!;
        final verb = count > 1
            ? 'Key "${p['key']}" pressed x$count on'
            : 'Key "${p['key']}" pressed on';
        final feedback = _formatActionFeedback(
          verb,
          p,
          res,
        );
        final waitFor = p['waitFor']?.toString();
        if (waitFor != null && waitFor.isNotEmpty) {
          final fromRoute =
              (res.data?['delta'] as Map<String, dynamic>?)?['fromRoute'];
          final waitRes = await _callExtensionRaw(
            'ext.flutterpilot.waitForWidget',
            {
              'key': waitFor,
              'timeoutMs':
                  ((p['timeoutMs'] as num?)?.toInt() ?? 5000).toString(),
              'previousRoute': ?fromRoute?.toString(),
            },
          );
          if (waitRes.isError) {
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text:
                      '$feedback\nBut "$waitFor" did not appear: ${waitRes.errorMessage}',
                ),
              ],
            );
          }
          return CallToolResult(
            content: [
              TextContent(
                text: _formatActionFeedback(
                  '$verb; then appeared',
                  const {},
                  waitRes,
                ),
              ),
            ],
          );
        }
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
      'gesture_widget',
      description:
          'Drives a widget with swipe, drag, pinch, focus or slide. Reports '
          'what changed in route and tree.',
      inputSchema: ToolInputSchema(
        properties: {
          'gesture': JsonSchema.string(
            enumValues: ['swipe', 'drag', 'pinch', 'focus', 'slide'],
            description: 'swipe, drag, pinch, focus, or slide.',
          ),
          'key': JsonSchema.string(
            description: 'Key or selector. Omit for focus to unfocus.',
          ),
          'direction': JsonSchema.string(
            enumValues: ['up', 'down', 'left', 'right'],
            description: 'Direction for swipe.',
          ),
          'distance': JsonSchema.number(
            description: 'Distance in logical pixels.',
          ),
          'fromKey': JsonSchema.string(
            description: 'Drag source key/selector.',
          ),
          'toKey': JsonSchema.string(description: 'Drag target key/selector.'),
          'scale': JsonSchema.number(
            description: 'Pinch scale (>1 zoom in, <1 zoom out).',
          ),
          'identifier': JsonSchema.string(
            description: 'Semantics id.',
          ),
          'x': JsonSchema.number(description: 'Center x for pinch, with y.'),
          'y': JsonSchema.number(),
          'value': JsonSchema.number(description: 'Slider value for slide.'),
        },
        required: ['gesture'],
      ),
      callback: (p, e) async {
        CallToolResult error(String text) =>
            CallToolResult(isError: true, content: [TextContent(text: text)]);
        final problem = gestureRequestError(p);
        if (problem != null) return error(problem);
        switch (p['gesture']) {
          case 'swipe':
            final res = await _callExtensionRaw(
              'ext.flutterpilot.swipeWidget',
              {
                'key': (p['key'] ?? p['target']).toString(),
                'direction': p['direction'].toString(),
                if (p['distance'] != null) 'distance': p['distance'].toString(),
              },
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
                    memory: _activeContext?.screenMemory,
                  ),
                ),
              ],
            );
          case 'drag':
            final res = await _callExtensionRaw('ext.flutterpilot.dragWidget', {
              'fromKey': p['fromKey'] ?? p['key'],
              'toKey': p['toKey'],
            });
            if (res.isError) return res.toCallToolResult();
            return CallToolResult(
              content: [
                TextContent(
                  text: _formatActionDelta(
                    res.data,
                    verb: 'Drag complete',
                    memory: _activeContext?.screenMemory,
                  ),
                ),
              ],
            );
          case 'pinch':
            final res =
                await _callExtensionRaw('ext.flutterpilot.pinchZoomWidget', {
                  'scale': p['scale'],
                  if (p['key'] != null) 'key': p['key'],
                  if (p['identifier'] != null) 'identifier': p['identifier'],
                  if (p['x'] != null) 'x': p['x'],
                  if (p['y'] != null) 'y': p['y'],
                });
            if (res.isError) return res.toCallToolResult();
            return CallToolResult(
              content: [
                TextContent(text: _formatActionFeedback('Pinch zoom', p, res)),
              ],
            );
          case 'focus':
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
            final res = await _callExtensionRaw(
              'ext.flutterpilot.focusWidget',
              {'key': target.toString()},
            );
            return res.isError
                ? res.toCallToolResult()
                : CallToolResult(
                    content: [TextContent(text: 'Focused "$target".')],
                  );
          case 'slide':
            final res =
                await _callExtensionRaw('ext.flutterpilot.setSliderValue', {
                  'key': (p['key'] ?? p['target']).toString(),
                  'value': p['value'].toString(),
                });
            return res.toCallToolResult();
          default:
            return error('Unknown gesture "${p['gesture']}".');
        }
      },
    );

    _tool(
      'scroll_into_view',
      description:
          'Scrolls until widget (key, selector, or text) is visible. '
          'Pass tap: true to tap once visible.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key, selector or text of the widget.',
          ),
          'tap': JsonSchema.boolean(
            description: 'Whether to tap the widget once scrolled into view.',
          ),
          'waitFor': JsonSchema.string(
            description: 'Optional widget to wait for after tapping.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Timeout for waitFor in ms (default 5000).',
          ),
        },
      ),
      callback: (p, e) async {
        final scrollArgs = Map<String, dynamic>.of(p)
          ..remove('tap')
          ..remove('waitFor')
          ..remove('timeoutMs');
        final res = await _callExtensionRaw(
          'ext.flutterpilot.scrollIntoView',
          scrollArgs,
        );
        if (res.isError) return res.toCallToolResult();
        if (p['tap'] == true) {
          final target =
              p['key'] ?? p['target'] ?? p['identifier'] ?? p['text'] ?? '';
          final tapRes = await _callExtensionRaw(
            'ext.flutterpilot.tapWidget',
            {'key': target.toString()},
          );
          if (tapRes.isError) return tapRes.toCallToolResult();
          final waitFor = p['waitFor']?.toString();
          if (waitFor != null && waitFor.isNotEmpty) {
            final fromRoute =
                (tapRes.data?['delta'] as Map<String, dynamic>?)?['fromRoute'];
            final waitRes = await _callExtensionRaw(
              'ext.flutterpilot.waitForWidget',
              {
                'key': waitFor,
                'timeoutMs':
                    ((p['timeoutMs'] as num?)?.toInt() ?? 5000).toString(),
                'previousRoute': ?fromRoute?.toString(),
              },
            );
            if (waitRes.isError) {
              return CallToolResult(
                isError: true,
                content: [
                  TextContent(
                    text:
                        '${_formatActionFeedback('Scrolled into view and tapped', p, tapRes)}\n'
                        'But "$waitFor" did not appear: ${waitRes.errorMessage}',
                  ),
                ],
              );
            }
            return CallToolResult(
              content: [
                TextContent(
                  text: _formatActionFeedback(
                    'Scrolled into view and tapped "$target"; then appeared',
                    const {},
                    waitRes,
                  ),
                ),
              ],
            );
          }
          return CallToolResult(
            content: [
              TextContent(
                text: _formatActionFeedback(
                  'Scrolled into view and tapped',
                  p,
                  tapRes,
                ),
              ),
            ],
          );
        }
        return res.toCallToolResult();
      },
    );

    _tool(
      'toggle_checkbox',
      description:
          'Toggles Checkbox, Switch or Radio. Pass value to set idempotently '
          'or waitFor to await next widget.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'Key, selector or label of the toggle, or of the row that '
                'holds it.',
          ),
          'value': JsonSchema.boolean(
            description:
                'Target state (true/false). If already set, does not toggle.',
          ),
          'waitFor': JsonSchema.string(
            description: 'Optional widget key to wait for.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Timeout for waitFor in ms (default 5000).',
          ),
        },
      ),
      callback: (p, e) async {
        final key = (p['key'] ?? p['target']).toString();
        final res = await _callExtensionRaw('ext.flutterpilot.toggleCheckbox', {
          'key': key,
          if (p.containsKey('value')) 'value': (p['value'] == true).toString(),
        });
        if (res.isError) return res.toCallToolResult();
        if (res.data?['alreadySet'] == true) {
          return CallToolResult(
            content: [
              TextContent(
                text: 'Toggle "$key" is already ${res.data?['value']} (no-op).',
              ),
            ],
          );
        }
        final feedback = _formatActionDelta(
          res.data,
          verb: 'Toggled',
          memory: _activeContext?.screenMemory,
        );
        final waitFor = p['waitFor']?.toString();
        if (waitFor != null && waitFor.isNotEmpty) {
          final fromRoute =
              (res.data?['delta'] as Map<String, dynamic>?)?['fromRoute'];
          final waitRes = await _callExtensionRaw(
            'ext.flutterpilot.waitForWidget',
            {
              'key': waitFor,
              'timeoutMs':
                  ((p['timeoutMs'] as num?)?.toInt() ?? 5000).toString(),
              'previousRoute': ?fromRoute?.toString(),
            },
          );
          if (waitRes.isError) {
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text:
                      '$feedback\nBut "$waitFor" did not appear: ${waitRes.errorMessage}',
                ),
              ],
            );
          }
          return CallToolResult(
            content: [
              TextContent(
                text: _formatActionFeedback(
                  'Toggled; then appeared',
                  const {},
                  waitRes,
                ),
              ),
            ],
          );
        }
        return CallToolResult(content: [TextContent(text: feedback)]);
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
                'Optional button to tap after filling (e.g. "ElevatedButton[\'Log In\']").',
          ),
          'submit': JsonSchema.boolean(
            description: 'Tap the one primary button.',
          ),
          'waitFor': JsonSchema.string(
            description: 'Widget or text to wait for after submitting.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Timeout for waitFor (default 5000).',
          ),
        },
        required: ['fields'],
      ),
      callback: (p, e) async {
        var submit = p['submitWith'] ?? p['submitTarget'];
        if (submit == null && p['submit'] == true) {
          final found = await _callExtensionRaw(
            'ext.flutterpilot.getInteractiveElements',
            {},
          );
          final primary = primaryButtons(found.data?['elements']);
          if (primary.length == 1) {
            submit = primary.single;
          } else {
            final submitPattern = RegExp(
              r'submit|save|continue|log\s*in|sign\s*in|register|next|confirm|done|send',
              caseSensitive: false,
            );
            final matching =
                primary.where((b) => submitPattern.hasMatch(b)).toList();
            if (matching.length == 1) {
              submit = matching.single;
            } else {
              return CallToolResult(
                isError: true,
                content: [
                  TextContent(
                    text:
                        'submit: true needs exactly one primary button on '
                        'screen; found ${primary.length}'
                        '${primary.isEmpty ? '' : ' (${primary.join(', ')})'}. '
                        'Name it in submitWith.',
                  ),
                ],
              );
            }
          }
        }
        final res = await _callExtensionRaw('ext.flutterpilot.fillForm', {
          'fields': json.encode(p['fields']),
          if (submit != null) 'submitWith': submit.toString(),
        });
        if (res.isError) {
          return withVerdict(
            res.toCallToolResult(),
            fillFormVerdict(
              submitted: false,
              filledCount: 0,
              totalFields: (p['fields'] as Map?)?.length ?? 0,
              status: 'unavailable',
            ),
          );
        }
        final filled = (res.data?['fieldsFilled'] as num?)?.toInt() ?? 0;
        final total = (res.data?['totalFields'] as num?)?.toInt() ?? 0;
        final submitted = res.data?['submitted'] == true;
        final failedField = (res.data?['failedFields'] as List?)?.firstOrNull
            ?.toString();
        final validationList = (res.data?['validationErrors'] as List?)
            ?.map((e) => e.toString())
            .toList();
        final validationNote =
            (validationList != null && validationList.isNotEmpty)
                ? '\n⚠️ Form validation issues (${validationList.length}): ${validationList.join('; ')}'
                : '';

        final waitFor = p['waitFor']?.toString();
        if (waitFor != null && waitFor.isNotEmpty) {
          final timeout =
              ((p['timeoutMs'] as num?)?.toInt() ?? 5000).toString();
          final waitRes = await _callExtensionRaw(
            'ext.flutterpilot.waitForWidget',
            {'key': waitFor, 'timeoutMs': timeout},
          );
          if (waitRes.isError) {
            return withVerdict(
              CallToolResult(
                isError: true,
                content: [
                  TextContent(
                    text:
                        'Filled $filled/$total fields${submitted ? ' and submitted' : ''}, but "$waitFor" did not appear: ${waitRes.errorMessage}$validationNote',
                  ),
                ],
              ),
              fillFormVerdict(
                submitted: submitted,
                filledCount: filled,
                totalFields: total,
                failedField: failedField,
                validationErrors: validationList,
                status: 'unavailable',
              ),
            );
          }
        }

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
        final waitNote =
            waitFor != null && waitFor.isNotEmpty ? ' Settled on "$waitFor".' : '';
        return withVerdict(
          CallToolResult(
            content: [
              TextContent(
                text:
                    'Filled $filled/$total fields${submitted ? ' and tapped submit.' : '. Not submitted: pass submitWith (a button) or submit: true.'}'
                    '$routeNote$diffNote$waitNote$validationNote${_quietNote(delta)}${_screenNow(res.data, memory: _activeContext?.screenMemory)}',
              ),
            ],
          ),
          fillFormVerdict(
            submitted: submitted,
            filledCount: filled,
            totalFields: total,
            failedField: failedField,
            validationErrors: validationList,
          ),
        );
      },
    );

    _tool(
      'wait_for',
      description:
          'Waits for condition: widget key, anyOf targets, route, animations, '
          'state, or frames. Supports failureKey for fast error abort.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key, selector or text on screen.',
          ),
          'anyOf': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Wait until any one of these keys/selectors appears.',
          ),
          'failureKey': JsonSchema.string(
            description:
                'Immediate failure key (e.g. error banner). Aborts wait immediately if seen.',
          ),
          'gone': JsonSchema.boolean(description: 'Until key is gone.'),
          'route': JsonSchema.string(
            description: 'Target route (e.g. "/dashboard").',
          ),
          'animations': JsonSchema.boolean(
            description: 'Until animations have settled.',
          ),
          'state': JsonSchema.string(
            description: 'Provider or bloc name from get_state.',
          ),
          'expectedValue': JsonSchema.string(
            description: 'Substring expected in state value.',
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
        // What was waited for, then the screen as it is now: the same text as
        // always, plus the structured twin of the outcome (met, waitedMs,
        // timedOut, condition, and the route when the app reports one).
        final watch = Stopwatch()..start();
        Future<CallToolResult> waited(
          String text, {
          bool route = true,
          required String condition,
          required bool met,
          required int timeoutMs,
          int? waitedMs,
          bool? timedOut,
        }) async {
          final after = await _screenAfterData(route: route);
          return CallToolResult(
            content: [TextContent(text: '$text${after.text}')],
            structuredContent: {
              ...waitForVerdict(
                condition: condition,
                met: met,
                waitedMs: waitedMs ?? watch.elapsedMilliseconds,
                timeoutMs: timeoutMs,
                timedOut: timedOut,
              ),
              if (after.route != null) 'route': Redaction.text(after.route!),
            },
          );
        }

        // A wait that errored never met its condition; its structured result
        // says so instead of leaving that to the error alone. `status` is
        // "unavailable": the app did not answer, so `met`/`timedOut` are
        // defaults, not a verdict.
        CallToolResult unmet(
          String condition,
          int timeoutMs,
          _ExtensionResult res,
        ) => withVerdict(
          res.toCallToolResult(),
          waitForVerdict(
            condition: condition,
            met: false,
            waitedMs: watch.elapsedMilliseconds,
            timeoutMs: timeoutMs,
            status: 'unavailable',
          ),
        );
        final timeout = p['timeoutMs']?.toString();
        // The defaults the extensions use when `timeoutMs` is absent — 3000 for
        // the widget condition (widget_extensions.dart) and animations, 5000
        // for route (navigation_extensions.dart) and state
        // (state_extensions.dart) — so a clock-based `timedOut` means the wait
        // used its whole deadline. Each of those literals carries a comment
        // pointing back here: change one, change the other.
        int timeoutOf(int fallback) => int.tryParse(timeout ?? '') ?? fallback;
        final selector = p['selector'] ?? p['target'] ?? p['key'];
        final rawAnyOf = p['anyOf'];
        final anyOfStr = rawAnyOf is List
            ? rawAnyOf.map((s) => s.toString()).join(',')
            : rawAnyOf?.toString();
        final failureKey = p['failureKey']?.toString();
        if (selector != null || anyOfStr != null || failureKey != null) {
          final t = timeoutOf(3000);
          final res =
              await _callExtensionRaw('ext.flutterpilot.waitForCondition', {
                if (selector != null) 'selector': selector.toString(),
                'anyOf': ?anyOfStr,
                'failureKey': ?failureKey,
                'timeoutMs': ?timeout,
                if (p['gone'] == true) 'gone': 'true',
              });
          if (res.isError) return unmet('key', t, res);
          final matched = res.data?['selector'] ?? selector ?? anyOfStr;
          return waited(
            p['gone'] == true
                ? '"$matched" is gone (${res.data?['elapsedMs'] ?? 0}ms).'
                : '"$matched" is on screen (${res.data?['elapsedMs'] ?? 0}ms).',
            condition: 'key',
            met: true,
            timeoutMs: t,
            waitedMs: (res.data?['elapsedMs'] as num?)?.toInt(),
          );
        }
        if (p['route'] != null) {
          final t = timeoutOf(5000);
          final res = await _callExtensionRaw('ext.flutterpilot.waitForRoute', {
            'route': p['route'].toString(),
            'timeoutMs': ?timeout,
          });
          if (res.isError) return unmet('route', t, res);
          return waited(
            'On route "${p['route']}".',
            route: false,
            condition: 'route',
            met: true,
            timeoutMs: t,
          );
        }
        if (p['state'] != null) {
          final t = timeoutOf(5000);
          final res = await _callExtensionRaw('ext.flutterpilot.waitForState', {
            'type': await _stateTypeOf(p['state'].toString()),
            'name': p['state'].toString(),
            'expectedValue': p['expectedValue']?.toString() ?? '',
            'timeoutMs': ?timeout,
          });
          if (res.isError) return unmet('state', t, res);
          final value = '${res.data?['value']}';
          return waited(
            '${p['state']} is '
            '${value.length > 200 ? '${value.substring(0, 200)}…' : value}.',
            condition: 'state',
            met: true,
            timeoutMs: t,
          );
        }
        if (p['frames'] != null) {
          final t = timeoutOf(5000);
          final count = ((p['frames'] as num).toInt()).clamp(1, 120);
          final res = await _callExtensionRaw('ext.flutterpilot.pumpFrames', {
            'count': count.toString(),
          });
          if (res.isError) return unmet('frames', t, res);
          return waited(
            'Pumped $count frames.',
            condition: 'frames',
            met: true,
            timeoutMs: t,
          );
        }
        if (p['animations'] == true) {
          final t = timeoutOf(3000);
          final res = await _callExtensionRaw(
            'ext.flutterpilot.waitForAnimation',
            {'timeoutMs': ?timeout},
          );
          if (res.isError) return unmet('animations', t, res);
          final settled = res.data?['status'] == 'settled';
          return waited(
            settled
                ? 'Animations settled.'
                : 'Animations were still running at the timeout (a looping '
                      'animation or a spinner?).',
            condition: 'animations',
            met: settled,
            timeoutMs: t,
            // The app's own answer says which of the two it is, so this one
            // is not inferred from the clock and the copied default.
            timedOut: res.data?['status'] == 'timeout',
          );
        }
        return withVerdict(
          CallToolResult(
            isError: true,
            content: [
              TextContent(
                text:
                    'Say what to wait for: key, route, animations: true, state '
                    '(with expectedValue) or frames.',
              ),
            ],
          ),
          waitForVerdict(
            condition: 'none',
            met: false,
            waitedMs: 0,
            timeoutMs: 0,
            status: 'refused',
          ),
        );
      },
    );

    _tool(
      'audit_screen_health',
      description:
          'Audits screen health: layout overflows, tap targets under minimum '
          '(48dp mobile, 24px desktop), unlabeled controls, low contrast text '
          'and reading order jumps. routes sweeps multiple routes; viewports '
          'audits responsive breakpoints.',
      inputSchema: ToolInputSchema(
        properties: {
          'routes': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Go to each route and check it.',
          ),
          'designQuality': JsonSchema.boolean(
            description: 'Audit 4/8dp spacing grid and typography hierarchy.',
          ),
          'viewports': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Audit viewports (e.g. ["mobile_portrait", "tablet"]).',
          ),
        },
      ),
      callback: (p, e) async {
        // One screen's findings; a sweep shows fewer per kind and leaves
        // out the reading order.
        String report(Map<String, dynamic> data, {required bool sweep}) {
          final max = sweep ? 5 : 12;
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
            for (final item in items.take(max)) {
              buffer.writeln('- ${line(item)}');
            }
            if (items.length > max) {
              buffer.writeln('- … ${items.length - max} more');
            }
          }

          section(
            'Layout overflows',
            overflows,
            (o) {
              final src = o['source'] != null ? ' at ${o['source']}' : '';
              final fix = o['source'] != null
                  ? '\n  → Fix: apply_patch_and_verify(target: "${o['source']}", wrapWith: "Expanded") or wrap in SingleChildScrollView'
                  : '';
              return '${o['type']}$src: ${o['details']}$fix';
            },
          );
          section(
            'Small tap targets',
            targets,
            (a) {
              final src = a['source'] != null ? ' at ${a['source']}' : '';
              final fix = a['source'] != null
                  ? '\n  → Fix: apply_patch_and_verify(target: "${a['source']}", wrapWith: "SizedBox(width: 48, height: 48)") or add padding'
                  : '';
              return '`${a['target']}` (${a['type']})$src: ${a['issue']}$fix';
            },
          );
          // Grouped on purpose: identical controls (one list row repeating one
          // widget) are one finding. Say both numbers so a count of "1" is
          // never read as "one control".
          if (unlabeled.isNotEmpty) {
            final controls = unlabeled.fold<int>(
              0,
              (n, u) => n + _unlabeledControls('$u'),
            );
            buffer.writeln(
              'Controls without a label (${unlabeled.length} '
              'finding${unlabeled.length == 1 ? '' : 's'}, '
              '$controls control${controls == 1 ? '' : 's'}):',
            );
            for (final item in unlabeled.take(max)) {
              buffer.writeln('- $item');
              final srcMatch = RegExp(
                r'Code:\s*([^\s,;()]+\.dart):(\d+):(\d+)',
              ).firstMatch('$item');
              if (srcMatch != null) {
                final f = srcMatch.group(1)!;
                final l = srcMatch.group(2)!;
                buffer.writeln(
                  '  → Fix: apply_patch_and_verify(file: "$f", line: $l, ...) or add tooltip: \'...\' / Semantics(label: \'...\')',
                );
              }
            }
            if (unlabeled.length > max) {
              buffer.writeln('- … ${unlabeled.length - max} more');
            }
          }
          section('Low contrast text', contrast, (c) => '$c');
          section('Reading order jumps', jumps, (j) => '$j');
          final gridIssues = list('spacingGridIssues');
          section(
            'Padding off the 4dp grid, set in the app\'s code',
            gridIssues,
            (g) =>
                '${g['widget']} ${g['source']}: ${g['details']}'
                '${(g['count'] ?? 1) > 1 ? ' (×${g['count']})' : ''}',
          );
          final typography = list('typographyHierarchy');
          if (typography.isNotEmpty && !sweep) {
            buffer.writeln('Typography hierarchy: ${typography.join(", ")}');
          }
          if (buffer.isEmpty) {
            buffer.writeln(
              'No layout overflows, small tap targets, unlabeled controls, '
              'low-contrast text or reading order jumps.',
            );
          }
          if (order.isNotEmpty && !sweep) {
            final shown = order.take(15).join(' → ');
            buffer.writeln(
              'Screen reader order (${order.length} controls): $shown'
              '${order.length > 15 ? ' → …' : ''}',
            );
          }
          if (data['semanticsNote'] != null) {
            buffer.writeln(data['semanticsNote']);
          }
          return buffer.toString().trim();
        }

        // The counts the structured result carries: one screen's findings by
        // category, and the same read across a sweep.
        Map<String, int> screenFindings(Map<String, dynamic> data) {
          int n(String key) => ((data[key] as List?) ?? const []).length;
          return {
            'overflows': n('overflows'),
            'tapTargets': n('accessibilityIssues'),
            'unlabeled': n('unlabeled'),
            'lowContrast': n('lowContrast'),
            'readingOrderJumps': n('readingOrderJumps'),
            if (data.containsKey('spacingGridIssues'))
              'offGridSpacing': n('spacingGridIssues'),
          };
        }

        void addFindings(Map<String, int> into, Map<String, int> from) {
          for (final e in from.entries) {
            into[e.key] = (into[e.key] ?? 0) + e.value;
          }
        }

        final routes = [
          for (final r in (p['routes'] as List?) ?? const []) '$r',
        ];
        final auditParams = {
          if (p['designQuality'] == true) 'designQuality': 'true',
        };
        final viewports = [
          for (final v in (p['viewports'] as List?) ?? const []) '$v',
        ];
        if (viewports.isNotEmpty) {
          final snapshot =
              await _callExtensionRaw('ext.flutterpilot.getAppSnapshot', {});
          final initialViewport = snapshot.data?['viewport'];

          const presets = <String, ({int width, int height})>{
            'mobile_portrait': (width: 390, height: 844),
            'mobile_landscape': (width: 844, height: 390),
            'tablet': (width: 768, height: 1024),
            'desktop': (width: 1280, height: 800),
          };

          final matrixBuffer = StringBuffer(
            'Responsive Viewport Matrix (${viewports.length} viewport${viewports.length == 1 ? '' : 's'}):\n',
          );
          var totalOverflows = 0;
          final matrixResults = <String, dynamic>{};

          for (final vp in viewports) {
            final sz = presets[vp] ?? parseWindowSize(vp);
            if (sz == null) {
              matrixBuffer.writeln('• $vp: Skipped (unknown dimensions)');
              continue;
            }
            await _callExtensionRaw('ext.flutterpilot.setWindowSize', {
              'width': '${sz.width}',
              'height': '${sz.height}',
            });
            await Future<void>.delayed(const Duration(milliseconds: 100));

            final res = await _callExtensionRaw(
              'ext.flutterpilot.auditScreenHealth',
              auditParams,
            );
            final data = res.data ?? const <String, dynamic>{};
            final ov = (data['overflows'] as List?) ?? const [];
            totalOverflows += ov.length;
            matrixResults[vp] = {
              'width': sz.width,
              'height': sz.height,
              'overflows': ov.length,
              'findings': screenFindings(data),
            };

            if (ov.isEmpty) {
              matrixBuffer.writeln('• $vp (${sz.width}x${sz.height}): PASS (0 overflows)');
            } else {
              matrixBuffer.writeln(
                '• $vp (${sz.width}x${sz.height}): FAIL (${ov.length} layout overflow${ov.length == 1 ? '' : 's'})',
              );
              for (final o in ov) {
                final src = o['source'] != null ? ' at ${o['source']}' : '';
                matrixBuffer.writeln('    - ${o['type']}$src: ${o['details']}');
                if (o['source'] != null) {
                  matrixBuffer.writeln(
                    '      → Fix: apply_patch_and_verify(target: "${o['source']}", wrapWith: "Expanded")',
                  );
                }
              }
            }
          }

          if (initialViewport is Map &&
              initialViewport['width'] != null &&
              initialViewport['height'] != null) {
            await _callExtensionRaw('ext.flutterpilot.setWindowSize', {
              'width': '${initialViewport['width']}',
              'height': '${initialViewport['height']}',
            });
          } else {
            await _callExtensionRaw('ext.flutterpilot.setWindowSize', {});
          }
          matrixBuffer.writeln('✓ Restored initial viewport.');

          return CallToolResult(
            content: [TextContent(text: matrixBuffer.toString().trim())],
            structuredContent: {
              'totalViewports': viewports.length,
              'totalOverflows': totalOverflows,
              'matrix': matrixResults,
              'restored': true,
            },
          );
        }

        if (routes.isEmpty) {
          final res = await _callExtensionRaw(
            'ext.flutterpilot.auditScreenHealth',
            auditParams,
          );
          if (res.isError) {
            // The current screen could not be read: one audit failed, nothing
            // visited, so the caller does not read an empty findings map as a
            // clean screen (task 07).
            return withVerdict(
              res.toCallToolResult(),
              auditVerdict(
                requested: 0,
                visited: 0,
                audited: 0,
                failed: 1,
                skipped: 0,
                findings: const {},
                restored: true,
                incomplete: true,
                loading: false,
                status: 'unavailable',
                reason: res.errorMessage,
              ),
            );
          }
          final data = res.data ?? const <String, dynamic>{};
          return CallToolResult(
            content: [TextContent(text: report(data, sweep: false))],
            structuredContent: auditVerdict(
              requested: 0,
              visited: 0,
              audited: 1,
              failed: 0,
              skipped: 0,
              findings: screenFindings(data),
              restored: true,
              incomplete: false,
              loading: false,
            ),
          );
        }
        // navigate_to, get_errors and audit_screen_health per screen were
        // three calls a screen in field sessions (75 such rounds in one).
        final out = StringBuffer();
        var clean = 0;
        // What the sweep asked for and actually did, for the structured
        // result: a route that could not be reached or audited is not covered,
        // and neither is one whose screen was still loading.
        final requested = routes.length;
        final checked = routes.take(40).toList();
        final skipped = requested - checked.length;
        var visited = 0;
        var audited = 0;
        var failed = 0;
        var arrivalErrors = 0;
        var loading = false;
        final totals = <String, int>{};
        // The sweep ends where it started: found on a phone, left three
        // screens away from the list the next tap was meant for.
        final before = await _callExtensionRaw(
          'ext.flutterpilot.screenNow',
          {},
        );
        final start = (before.data?['postActionState'] as Map?)?['route'];
        final progress = ToolProgress(e, total: checked.length.toDouble());
        var stoppedEarly = 0;
        for (var i = 0; i < checked.length; i++) {
          if (progress.cancelled) {
            stoppedEarly = checked.length - i;
            break;
          }
          final route = checked[i];
          await progress.advance(
            'Auditing route ${i + 1}/${checked.length}: $route',
          );
          out.writeln('== $route ==');
          final went = await _callExtensionRaw('ext.flutterpilot.navigateTo', {
            'route': route,
          });
          if (went.isError) {
            out.writeln('Could not go there: ${went.errorMessage}');
            failed++;
            continue;
          }
          visited++;
          await _callExtensionRaw('ext.flutterpilot.waitForAnimation', {
            'timeoutMs': '1500',
          });
          final now = await _callExtensionRaw('ext.flutterpilot.screenNow', {});
          final post = now.data?['postActionState'] as Map?;
          final errors = (post?['newErrorCount'] as num?)?.toInt() ?? 0;
          final res = await _callExtensionRaw(
            'ext.flutterpilot.auditScreenHealth',
            auditParams,
          );
          if (res.isError) {
            out.writeln('Audit failed: ${res.errorMessage}');
            failed++;
            continue;
          }
          audited++;
          addFindings(totals, screenFindings(res.data ?? const {}));
          if (errors > 0) arrivalErrors += errors;
          if (post?['loading'] == true) loading = true;
          final text = report(res.data ?? const {}, sweep: true);
          final fine = text.startsWith('No layout overflows') && errors == 0;
          if (fine) clean++;
          if (errors > 0) {
            out.writeln('$errors new error(s) on arriving: get_errors.');
          }
          if (post?['loading'] == true) {
            out.writeln('A progress indicator was still showing.');
          }
          out.writeln(fine ? 'Clean.' : text);
        }
        final totalSkipped = skipped + stoppedEarly;
        final skippedNote = skipped > 0
            ? ' $skipped more routes not checked (40 a call).'
            : stoppedEarly > 0
            ? ' $stoppedEarly route(s) not checked (cancelled).'
            : '';
        // Where it started: restored is true only when the sweep ended back on
        // it (or never left it). An unknown start cannot be claimed.
        var restored =
            start is String && start == routes.last && stoppedEarly == 0;
        var back = '';
        if (start is String && start != 'Unknown' && !restored) {
          final returned = await _callExtensionRaw(
            'ext.flutterpilot.navigateTo',
            {'route': start},
          );
          if (!returned.isError) {
            await _callExtensionRaw('ext.flutterpilot.waitForAnimation', {
              'timeoutMs': '1500',
            });
            back = '\nBack on $start.';
            restored = true;
          }
        }
        // A failed route is not clean, and neither is a screen still loading:
        // the sweep is incomplete even when every audit it reached was fine.
        final incomplete =
            totalSkipped > 0 || failed > 0 || arrivalErrors > 0 || loading;
        return CallToolResult(
          content: [
            TextContent(
              text: FlutterPilotServer._boundToolText(
                '${checked.length - stoppedEarly} routes checked, $clean clean.'
                '$skippedNote\n${out.toString().trim()}$back',
              ),
            ),
          ],
          structuredContent: auditVerdict(
            requested: requested,
            visited: visited,
            audited: audited,
            failed: failed,
            skipped: totalSkipped,
            findings: totals,
            restored: restored,
            incomplete: incomplete,
            loading: loading,
            status: incomplete ? 'partial' : 'ok',
          ),
        );
      },
    );

    _tool(
      'audit_design_tokens',
      description:
          'Colors and corner radii the app\'s own widgets hard-code instead of '
          'taking from the theme\'s ColorScheme (radii off the 4dp grid), each '
          'with file:line and the closest token. Framework widgets are not '
          'checked. Debug builds.',
      inputSchema: ToolInputSchema(properties: {}),
      callback: (p, e) async {
        final res = await _callExtensionRaw(
          'ext.flutterpilot.auditDesignTokens',
          {},
        );
        if (res.isError) return res.toCallToolResult();
        final data = res.data ?? const <String, dynamic>{};
        if (data['unavailable'] != null) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: '${data['unavailable']}')],
          );
        }
        final colors = (data['unthemedColors'] as List?) ?? const [];
        final radii = (data['offGridRadii'] as List?) ?? const [];
        final colorCount = data['unthemedColorCount'] ?? colors.length;
        final radiusCount = data['offGridRadiusCount'] ?? radii.length;
        final buf = StringBuffer(
          'Checked ${data['checked'] ?? 0} colors and radii set in the app\'s '
          'code on this screen.',
        );
        if (colors.isEmpty && radii.isEmpty) {
          buf.write(' All come from the theme.');
        }
        String at(Map m) => m['location'] != null ? ' at ${m['location']}' : '';
        if (colors.isNotEmpty) {
          buf.write('\nNot from the ColorScheme ($colorCount):');
          for (final c in colors.cast<Map>()) {
            buf.write(
              '\n  ${c['color']} in ${c['widget']}${at(c)} '
              '(closest: ${c['closestToken']})',
            );
          }
          if (colorCount is int && colorCount > colors.length) {
            buf.write('\n  … ${colorCount - colors.length} more');
          }
        }
        if (radii.isNotEmpty) {
          buf.write('\nCorner radii off the 4dp grid ($radiusCount):');
          for (final r in radii.cast<Map>()) {
            buf.write(
              '\n  ${r['radius']} in ${r['widget']}${at(r)} '
              '(nearest: ${r['nearest']})',
            );
          }
        }
        return CallToolResult(
          content: [TextContent(text: buf.toString())],
          structuredContent: data,
        );
      },
    );

    _tool(
      'execute_action_chain',
      description:
          'Runs a known sequence of steps in one call, stopping at the first '
          'that fails. Returns each step\'s outcome and post-chain screen state '
          '(route, visual diff, elements).',
      inputSchema: ToolInputSchema(
        properties: {
          'steps': JsonSchema.array(
            items: compositeStepSchema(),
            description:
                'Sequence of steps, e.g. [{"tool": "tap_widget", "arguments": {"key": "Save"}}].',
          ),
          'exportAsTest': JsonSchema.boolean(
            description:
                'Export the executed journey as a runnable integration test file.',
          ),
          'testName': JsonSchema.string(description: 'Name of the generated test.'),
          'testFilePath': JsonSchema.string(description: 'Target test file path.'),
        },
        required: ['steps'],
      ),
      callback: (p, e) async {
        final requested = (p['steps'] as List?)?.length ?? 0;
        CallToolResult error(String text, {int? failedStep}) => withVerdict(
          CallToolResult(isError: true, content: [TextContent(text: text)]),
          actionChainVerdict(
            passed: false,
            completedSteps: 0,
            totalSteps: requested,
            failedStep: failedStep,
            failureReason: text,
            status: 'refused',
          ),
        );
        // Every step is validated before any runs (task 02): a malformed step
        // N means nothing was tapped or typed, on every path.
        final preflight = preflightChain(
          p['steps'],
          allowedTools: _chainStepTools,
          isAvailable: _toolCallbacks.containsKey,
          profileRefusal: stepProfileRefusal,
          gate: (tool, args) => _toolArgGates[tool]!(args),
        );
        if (!preflight.ok) {
          return error(preflight.problem!, failedStep: preflight.problemStep);
        }
        final steps = preflight.steps;

        // Taps and text entries alone run inside the app, in one round trip.
        Future<String?> exportJourney({required bool passed}) async {
          if (p['exportAsTest'] != true || !passed) return null;
          try {
            final vm = (await _deviceContextForParameters(const {}))?.service;
            final isolateId =
                vm == null ? null : await _uiIsolateId(vm, null);
            final entry = isolateId == null
                ? null
                : await _appEntrypoint(vm!, isolateId);
            final root = entry?.root ?? Directory.current.path;
            final mainImport = entry?.mainImport ?? 'package:app/main.dart';
            final testName =
                p['testName']?.toString() ?? 'Action Chain Journey';
            final sanitizedName =
                testName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
            final relPath = p['testFilePath']?.toString() ??
                path_pkg.join('integration_test', '${sanitizedName}_test.dart');
            final fullPath = path_pkg.isAbsolute(relPath)
                ? relPath
                : path_pkg.join(root, relPath);

            final recorded = <Map<String, dynamic>>[];
            for (final step in steps) {
              final a = step.arguments;
              String? finder;
              if (a['key'] != null) {
                finder = "find.byKey(const Key('${a['key']}'))";
              } else if (a['text'] != null) {
                finder = "find.text('${a['text']}')";
              }
              if (step.tool == 'tap_widget' && finder != null) {
                recorded.add({'type': 'tap', 'finder': finder, 'stable': true});
              } else if (step.tool == 'enter_text' && finder != null) {
                recorded.add({
                  'type': 'enterText',
                  'finder': finder,
                  'text': a['text']?.toString() ?? '',
                  'stable': true,
                });
              } else if (step.tool == 'press_key') {
                recorded.add({
                  'type': 'pressKey',
                  'key': a['key']?.toString() ?? '',
                  'modifiers': a['modifiers'] as List? ?? const [],
                });
              } else if (step.tool == 'assert_widget' && finder != null) {
                recorded.add({'type': 'tap', 'finder': finder, 'stable': true});
              }
            }

            final test = writeIntegrationTest(
              name: testName,
              mainImport: mainImport,
              steps: recorded,
            );

            final targetFile = File(fullPath);
            targetFile.parent.createSync(recursive: true);
            targetFile.writeAsStringSync(test.source);
            try {
              await Process.run('dart', ['format', fullPath]);
            } catch (_) {}
            return relPath;
          } catch (_) {
            return null;
          }
        }

        final inApp = [for (final step in steps) ?inAppChainAction(step)];
        if (inApp.length == steps.length) {
          final res = await _callExtensionRaw(
            'ext.flutterpilot.executeActionChain',
            {'actions': json.encode(inApp)},
          );
          if (res.isError) {
            return withVerdict(
              res.toCallToolResult(),
              actionChainVerdict(
                passed: false,
                completedSteps: 0,
                totalSteps: steps.length,
                status: 'unavailable',
              ),
            );
          }
          final executed = (res.data?['executedCount'] as num?)?.toInt() ?? 0;
          final total = (res.data?['totalActions'] as num?)?.toInt() ?? 0;
          final failure = res.data?['failure'] as String?;
          // One formatter for both chain paths (this in-app fast path and the
          // tool-at-a-time fallback below): the same words, the same 1-based
          // step numbers, the same "Not run:" line.
          final buffer = StringBuffer(
            failure == null
                ? 'Action chain: $executed/$total steps done.\n'
                : 'Action chain stopped after $executed/$total steps.\n'
                      'Step ${executed + 1} ${steps[executed].tool} failed: '
                      '$failure\n',
          );
          if (failure != null && executed + 1 < steps.length) {
            final notRun = steps
                .skip(executed + 1)
                .map((s) => s.tool)
                .join(', ');
            buffer.write('Not run: $notRun.\n');
          }
          for (final step in (res.data?['steps'] as List?) ?? const []) {
            // Tap notes, one per step that ran; numbered like `describeChain`.
            if (step is Map && step['index'] is num && step['note'] is String) {
              final index = (step['index'] as num).toInt();
              final tool = index >= 0 && index < steps.length
                  ? steps[index].tool
                  : null;
              buffer.write(
                'Step ${index + 1}${tool == null ? '' : ' $tool'}: '
                '${step['note']}\n',
              );
            }
          }
          buffer.write(_formatActionFeedback('Chain finished', const {}, res));
          final exported = await exportJourney(passed: failure == null);
          if (exported != null) {
            buffer.writeln('\n✓ Exported journey to runnable integration test: $exported');
          }
          return withVerdict(
            CallToolResult(
              isError: failure != null,
              content: [TextContent(text: buffer.toString())],
            ),
            actionChainVerdict(
              passed: failure == null,
              completedSteps: executed,
              totalSteps: total,
              failedStep: failure == null ? null : executed + 1,
              failureReason: failure,
            ),
          );
        }

        // Anything else: one tool after the other, each as if called alone.
        final progress = ToolProgress(e, total: steps.length.toDouble());
        final outcomes = <String>[];
        var failed = false;
        int? failedStep;
        var completed = 0;
        for (final (index, step) in steps.indexed) {
          if (progress.cancelled) {
            outcomes.add('Cancelled before running ${step.tool}.');
            failed = true;
            failedStep = index + 1;
            break;
          }
          await progress.advance(
            'Step ${index + 1}/${steps.length}: ${step.tool}',
          );
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
          if (failed) {
            failedStep = index + 1;
            break;
          }
          completed++;
        }
        final chainDesc = describeChain(
          [for (final step in steps) step.tool],
          outcomes,
          failed: failed,
        );
        final exported = await exportJourney(passed: !failed);
        final fullText = exported != null
            ? '$chainDesc\n\n✓ Exported journey to runnable integration test: $exported'
            : chainDesc;
        return withVerdict(
          CallToolResult(
            isError: failed,
            content: [
              TextContent(
                text: fullText,
              ),
            ],
          ),
          actionChainVerdict(
            passed: !failed,
            completedSteps: completed,
            totalSteps: steps.length,
            failedStep: failedStep,
            failureReason: failed ? outcomes.last : null,
          ),
        );
      },
    );
  }
}

/// How many controls one `audit_screen_health` unlabeled finding covers. The
/// auditor groups identical controls as `Role ×N at …` (one list row repeats
/// one widget); a finding without `×N` is a single control.
int _unlabeledControls(String finding) {
  final match = RegExp(r' ×(\d+) ').firstMatch(finding);
  return match == null ? 1 : int.parse(match.group(1)!);
}
