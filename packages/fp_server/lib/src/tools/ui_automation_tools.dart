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
  final overflows = post?['overflows'] as List?;
  if (overflows != null && overflows.isNotEmpty) {
    for (final ov in overflows) {
      if (ov is Map) {
        final type = ov['type'] ?? 'Widget';
        final px = ov['pixels'] != null ? ' by ${ov['pixels']}px' : '';
        final side = ov['side'] ?? 'edge';
        final src = ov['source'] != null ? ' [${ov['source']}]' : '';
        buffer.write(
          '\n⚠️ Layout Overflow: $type overflowed$px on the $side$src',
        );
      }
    }
  }
  final clipped = post?['clippedElements'] as List?;
  if (clipped != null && clipped.isNotEmpty) {
    for (final cl in clipped.take(2)) {
      if (cl is Map) {
        final target = cl['target'] ?? cl['type'] ?? 'Element';
        final issue = cl['issue'] ?? 'partially clipped by viewport edge';
        final src = cl['source'] != null ? ' [${cl['source']}]' : '';
        buffer.write('\n⚠️ Clipped Action: "$target" $issue$src');
      }
    }
  }
  final newErrors = post?['newErrorCount'];
  if (newErrors is int && newErrors > 0) {
    final lastErr = post?['lastError']?.toString();
    if (lastErr != null && lastErr.isNotEmpty) {
      final shortErr = lastErr.length > 100
          ? '${lastErr.substring(0, 100)}…'
          : lastErr;
      buffer.write('\n⚠️ $newErrors new error(s): $shortErr');
    } else {
      buffer.write('\n⚠️ $newErrors new error(s) — call get_errors.');
    }
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

  Future<CallToolResult?> _awaitPostActionCondition({
    required Map<String, dynamic> params,
    required String verb,
    required _ExtensionResult actionResult,
    String? fromRoute,
  }) async {
    final waitFor = params['waitFor']?.toString();
    final failureKey = params['failureKey']?.toString();
    final rawAnyOf = params['anyOf'];
    final anyOfStr = rawAnyOf is List
        ? rawAnyOf.map((s) => s.toString()).join(',')
        : rawAnyOf?.toString();
    if (waitFor == null && failureKey == null && anyOfStr == null) return null;

    final timeout = ((params['timeoutMs'] as num?)?.toInt() ?? 5000).toString();
    final waitRes =
        await _callExtensionRaw('ext.flutterpilot.waitForCondition', {
          if (waitFor != null && waitFor.isNotEmpty) 'selector': waitFor,
          'anyOf': ?anyOfStr,
          'failureKey': ?failureKey,
          'timeoutMs': timeout,
          'previousRoute': ?fromRoute,
        });
    if (waitRes.isError) {
      final targetDesc = waitFor ?? anyOfStr ?? 'target';
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text:
                '${_formatActionFeedback(verb, params, actionResult)}\n'
                'But "$targetDesc" did not appear: ${waitRes.errorMessage}',
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

  void _registerUiAutomationTools() {
    _tool(
      'tap_widget',
      description:
          'Taps widget by key/text/selector (auto-scrolls) or x/y. '
          'Reports route, diff and tappable elements.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(description: 'Key, selector, text or icon.'),
          'mark': JsonSchema.integer(description: 'Set-of-Mark id.'),
          'identifier': JsonSchema.string(description: 'Semantics id.'),
          'semanticsId': JsonSchema.integer(description: 'SemanticsNode id.'),
          'text': JsonSchema.string(description: 'Visible text.'),
          'type': JsonSchema.string(description: 'Widget type.'),
          'x': JsonSchema.number(description: 'X in logical px.'),
          'y': JsonSchema.number(description: 'Y in logical px.'),
          'gesture': JsonSchema.string(
            enumValues: ['tap', 'double', 'long', 'secondary'],
            description: 'Default tap.',
          ),
          'durationMs': JsonSchema.integer(description: 'Long-press ms (600).'),
          'waitFor': JsonSchema.string(description: 'Key/text to await.'),
          'failureKey': JsonSchema.string(description: 'Fast-fail key.'),
          'anyOf': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Keys to await.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Wait timeout ms (5000).',
          ),
          'quickSettle': JsonSchema.boolean(description: '<=400ms settle.'),
          'settleTimeoutMs': JsonSchema.integer(
            description: 'Settle timeout ms.',
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
              ..remove('failureKey')
              ..remove('anyOf')
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
              ..remove('failureKey')
              ..remove('anyOf')
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
        final fromRoute =
            (res.data?['delta'] as Map<String, dynamic>?)?['fromRoute']
                ?.toString();
        final waitResult = await _awaitPostActionCondition(
          params: p,
          verb: '$verb${target != null ? ' "$target"' : ''}',
          actionResult: res,
          fromRoute: fromRoute,
        );
        if (waitResult != null) return waitResult;

        final feedback = _formatActionFeedback(verb, p, res);
        // A tap that changed nothing on a device nothing here can tap a
        // system dialog on: say what may have opened one.
        final dialog = feedback.contains('Nothing changed')
            ? await _permissionDialogHint()
            : null;
        return CallToolResult(
          content: [
            TextContent(text: dialog == null ? feedback : '$feedback\n$dialog'),
          ],
        );
      },
    );

    _tool(
      'enter_text',
      description:
          'Types text into field by key/selector/label or focused field. '
          'Pass submit:true for Enter.',
      inputSchema: ToolInputSchema(
        properties: {
          'text': JsonSchema.string(description: 'Text ("" clears).'),
          'key': JsonSchema.string(
            description: 'Key/label (omit for focused).',
          ),
          'mark': JsonSchema.integer(description: 'Set-of-Mark id.'),
          'identifier': JsonSchema.string(description: 'Semantics id.'),
          'clearFirst': JsonSchema.boolean(
            description: 'Clear first (default true).',
          ),
          'submit': JsonSchema.boolean(description: 'Press Enter.'),
          'waitFor': JsonSchema.string(description: 'Key/text to await.'),
          'failureKey': JsonSchema.string(description: 'Fast-fail key.'),
          'anyOf': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Keys to await.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Wait timeout ms (5000).',
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
          ..remove('failureKey')
          ..remove('anyOf')
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

        final verb = 'Typed "${res.data?['text'] ?? ''}" into';
        final fromRoute =
            (activeRes.data?['delta'] as Map<String, dynamic>?)?['fromRoute']
                ?.toString();
        final waitResult = await _awaitPostActionCondition(
          params: p,
          verb: verb,
          actionResult: activeRes,
          fromRoute: fromRoute,
        );
        if (waitResult != null) return waitResult;

        final feedback = _formatActionFeedback(verb, {
          'key': target ?? 'the focused field',
        }, activeRes);
        final notes = <String>[if (shouldSubmit) 'submitted with Enter'];
        final suffix = notes.isEmpty ? '' : ' (${notes.join(', ')}).';
        return CallToolResult(content: [TextContent(text: '$feedback$suffix')]);
      },
    );

    _tool(
      'press_key',
      description:
          'Presses key on focused widget (enter, tab, escape, arrows, '
          'or "back" to pop).',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'Key name ("enter", "back", "tab", "escape", arrow, char).',
          ),
          'modifiers': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'shift, ctrl, alt, meta.',
          ),
          'count': JsonSchema.integer(description: 'Repeat count (1–20).'),
          'waitFor': JsonSchema.string(description: 'Key/text to await.'),
          'failureKey': JsonSchema.string(description: 'Fast-fail key.'),
          'anyOf': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Keys to await.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Wait timeout ms (5000).',
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
          final fromRoute =
              (res.data?['delta'] as Map<String, dynamic>?)?['fromRoute']
                  ?.toString();
          final waitResult = await _awaitPostActionCondition(
            params: p,
            verb: count > 1 ? 'Back pressed x$count' : 'Back pressed',
            actionResult: res,
            fromRoute: fromRoute,
          );
          if (waitResult != null) return waitResult;
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
        final fromRoute =
            (res.data?['delta'] as Map<String, dynamic>?)?['fromRoute']
                ?.toString();
        final waitResult = await _awaitPostActionCondition(
          params: p,
          verb: verb,
          actionResult: res,
          fromRoute: fromRoute,
        );
        if (waitResult != null) return waitResult;
        final feedback = _formatActionFeedback(verb, p, res);
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
          'Drives widget with swipe, drag, pinch, focus or slide. Reports '
          'screen and route changes; supports waitFor, failureKey, and anyOf.',
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
          'identifier': JsonSchema.string(description: 'Semantics id.'),
          'x': JsonSchema.number(description: 'Center x for pinch, with y.'),
          'y': JsonSchema.number(description: 'Center y for pinch, with x.'),
          'value': JsonSchema.number(description: 'Slider value for slide.'),
          'waitFor': JsonSchema.string(
            description: 'Widget key/selector to wait for.',
          ),
          'failureKey': JsonSchema.string(
            description: 'Fast-fail key (e.g. error banner).',
          ),
          'anyOf': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Candidate keys to await.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Timeout for waitFor (default 5000).',
          ),
        },
        required: ['gesture'],
      ),
      callback: (p, e) async {
        CallToolResult error(String text) =>
            CallToolResult(isError: true, content: [TextContent(text: text)]);
        final problem = gestureRequestError(p);
        if (problem != null) return error(problem);
        final CallToolResult gestureResult;
        _ExtensionResult? activeRes;
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
            activeRes = res;
            gestureResult = CallToolResult(
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
            activeRes = res;
            gestureResult = CallToolResult(
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
            activeRes = res;
            gestureResult = CallToolResult(
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
            if (res.isError) return res.toCallToolResult();
            activeRes = res;
            gestureResult = res.toCallToolResult();
          default:
            return error('Unknown gesture "${p['gesture']}".');
        }

        final fromRoute =
            (activeRes.data?['delta'] as Map<String, dynamic>?)?['fromRoute']
                ?.toString();
        final waitResult = await _awaitPostActionCondition(
          params: p,
          verb: 'Gesture (${p['gesture']})',
          actionResult: activeRes,
          fromRoute: fromRoute,
        );
        if (waitResult != null) return waitResult;
        return gestureResult;
      },
    );

    _tool(
      'scroll_into_view',
      description: 'Scrolls until widget is visible; tap:true taps it.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(description: 'Key, selector or text.'),
          'tap': JsonSchema.boolean(description: 'Tap once visible.'),
          'waitFor': JsonSchema.string(description: 'Key/text to await.'),
          'failureKey': JsonSchema.string(description: 'Fast-fail key.'),
          'anyOf': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Keys to await.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Wait timeout ms (5000).',
          ),
        },
      ),
      callback: (p, e) async {
        final scrollArgs = Map<String, dynamic>.of(p)
          ..remove('tap')
          ..remove('waitFor')
          ..remove('failureKey')
          ..remove('anyOf')
          ..remove('timeoutMs');
        final res = await _callExtensionRaw(
          'ext.flutterpilot.scrollIntoView',
          scrollArgs,
        );
        if (res.isError) return res.toCallToolResult();
        if (p['tap'] == true) {
          final target =
              p['key'] ?? p['target'] ?? p['identifier'] ?? p['text'] ?? '';
          final tapRes = await _callExtensionRaw('ext.flutterpilot.tapWidget', {
            'key': target.toString(),
          });
          if (tapRes.isError) return tapRes.toCallToolResult();
          final fromRoute =
              (tapRes.data?['delta'] as Map<String, dynamic>?)?['fromRoute']
                  ?.toString();
          final waitResult = await _awaitPostActionCondition(
            params: p,
            verb: 'Scrolled into view and tapped "$target"',
            actionResult: tapRes,
            fromRoute: fromRoute,
          );
          if (waitResult != null) return waitResult;
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
        final fromRoute =
            (res.data?['delta'] as Map<String, dynamic>?)?['fromRoute']
                ?.toString();
        final waitResult = await _awaitPostActionCondition(
          params: p,
          verb: 'Scrolled into view',
          actionResult: res,
          fromRoute: fromRoute,
        );
        if (waitResult != null) return waitResult;
        return res.toCallToolResult();
      },
    );

    _tool(
      'toggle_checkbox',
      description:
          'Toggles Checkbox, Switch or Radio; value sets state idempotently.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(description: 'Key, selector or row label.'),
          'value': JsonSchema.boolean(
            description: 'Target state (no-op if already set).',
          ),
          'waitFor': JsonSchema.string(description: 'Key/text to await.'),
          'failureKey': JsonSchema.string(description: 'Fast-fail key.'),
          'anyOf': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Keys to await.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Wait timeout ms (5000).',
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
        final fromRoute =
            (res.data?['delta'] as Map<String, dynamic>?)?['fromRoute']
                ?.toString();
        final waitResult = await _awaitPostActionCondition(
          params: p,
          verb: 'Toggled "$key"',
          actionResult: res,
          fromRoute: fromRoute,
        );
        if (waitResult != null) return waitResult;
        final feedback = _formatActionDelta(
          res.data,
          verb: 'Toggled',
          memory: _activeContext?.screenMemory,
        );
        return CallToolResult(content: [TextContent(text: feedback)]);
      },
    );

    _tool(
      'fill_form',
      description: 'Fills multiple form fields and optionally submits.',
      inputSchema: ToolInputSchema(
        properties: {
          'fields': JsonSchema.object(
            description: 'Map of field key/selector to value (string or bool).',
          ),
          'submitWith': JsonSchema.string(
            description: 'Button key/selector to tap after filling.',
          ),
          'submit': JsonSchema.boolean(description: 'Tap primary button.'),
          'waitFor': JsonSchema.string(description: 'Key/text to await.'),
          'failureKey': JsonSchema.string(description: 'Fast-fail key.'),
          'anyOf': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Keys to await.',
          ),
          'timeoutMs': JsonSchema.integer(
            description: 'Wait timeout ms (5000).',
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
            final matching = primary
                .where((b) => submitPattern.hasMatch(b))
                .toList();
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
        final failureKey = p['failureKey']?.toString();
        final rawAnyOf = p['anyOf'];
        final anyOfStr = rawAnyOf is List
            ? rawAnyOf.map((s) => s.toString()).join(',')
            : rawAnyOf?.toString();
        if (waitFor != null || failureKey != null || anyOfStr != null) {
          final timeout = ((p['timeoutMs'] as num?)?.toInt() ?? 5000)
              .toString();
          final fromRoute =
              (res.data?['delta'] as Map<String, dynamic>?)?['fromRoute']
                  ?.toString();
          final waitRes =
              await _callExtensionRaw('ext.flutterpilot.waitForCondition', {
                if (waitFor != null && waitFor.isNotEmpty) 'selector': waitFor,
                'anyOf': ?anyOfStr,
                'failureKey': ?failureKey,
                'timeoutMs': timeout,
                'previousRoute': ?fromRoute,
              });
          if (waitRes.isError) {
            final targetDesc = waitFor ?? anyOfStr ?? 'target';
            return withVerdict(
              CallToolResult(
                isError: true,
                content: [
                  TextContent(
                    text:
                        'Filled $filled/$total fields${submitted ? ' and submitted' : ''}, but "$targetDesc" did not appear: ${waitRes.errorMessage}$validationNote',
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
        final waitNote = waitFor != null && waitFor.isNotEmpty
            ? ' Settled on "$waitFor".'
            : (anyOfStr != null ? ' Settled.' : '');
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
          'Waits for widget key, anyOf, route, animations, state, or frames.',
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(description: 'Key, selector or text.'),
          'anyOf': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Wait until any listed key appears.',
          ),
          'failureKey': JsonSchema.string(
            description: 'Fast-fail key that aborts wait if seen.',
          ),
          'gone': JsonSchema.boolean(description: 'Until key is gone.'),
          'route': JsonSchema.string(description: 'Target route.'),
          'animations': JsonSchema.boolean(description: 'Wait for animations.'),
          'state': JsonSchema.string(description: 'Provider or bloc name.'),
          'expectedValue': JsonSchema.string(
            description: 'Expected state substring.',
          ),
          'frames': JsonSchema.integer(description: 'Frames to pump (1–120).'),
          'timeoutMs': JsonSchema.integer(
            description: 'Timeout ms (default 5000).',
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
          'Audits layout overflows, tap targets, contrast, labels, tokens, '
          'keyboard, or viewports.',
      inputSchema: ToolInputSchema(
        properties: {
          'routes': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Routes to sweep.',
          ),
          'category': JsonSchema.string(
            enumValues: ['all', 'overflow', 'a11y', 'contrast', 'tokens'],
            description: 'Category filter (default all).',
          ),
          'query': JsonSchema.string(
            description: 'Filter by widget, key, file, or text.',
          ),
          'designQuality': JsonSchema.boolean(
            description: 'Audit 4/8dp spacing, typography, and tokens.',
          ),
          'viewports': JsonSchema.array(
            items: JsonSchema.string(),
            description: 'Viewports (phone, tablet, desktop, WxH).',
          ),
          'keyboardInset': JsonSchema.number(
            description: 'Keyboard height in dp to test and restore.',
          ),
          'restore': JsonSchema.boolean(
            description: 'Restore initial state afterwards (default true).',
          ),
        },
      ),
      callback: (p, e) async {
        final queryStr = p['query']?.toString().toLowerCase();
        bool matchesQuery(dynamic item) {
          if (queryStr == null || queryStr.isEmpty) return true;
          if (item is Map) {
            for (final key in const [
              'source',
              'target',
              'details',
              'issue',
              'type',
              'widget',
              'location',
              'color',
              'closestToken',
              'radius',
              'nearest',
            ]) {
              final value = item[key];
              if (value != null &&
                  value.toString().toLowerCase().contains(queryStr)) {
                return true;
              }
            }
            return false;
          }
          return item.toString().toLowerCase().contains(queryStr);
        }

        // One screen's findings; a sweep shows fewer per kind and leaves
        // out the reading order.
        String report(Map<String, dynamic> data, {required bool sweep}) {
          final max = sweep ? 5 : 12;

          List<dynamic> list(String key) =>
              (data[key] as List? ?? const []).where(matchesQuery).toList();
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

          final category = p['category']?.toString() ?? 'all';
          if (category == 'all' || category == 'overflow') {
            section('Layout overflows', overflows, (o) {
              final src = o['source'] != null ? ' at ${o['source']}' : '';
              final px = o['pixels'] != null ? ' by ${o['pixels']}px' : '';
              final side = o['side'] != null ? ' on the ${o['side']}' : '';
              final axis = o['axis'] ?? 'flex';
              final fix = o['source'] != null
                  ? (axis == 'vertical'
                        ? '\n  → Fix: wrap children in Expanded / Flexible or wrap Column in SingleChildScrollView'
                        : '\n  → Fix: wrap children in Expanded / Flexible or replace Row with Wrap')
                  : '';
              return '${o['type']}$src: overflowed$px$side${o['details'] != null && !o['details'].toString().contains('overflowed') ? ' (${o['details']})' : ''}$fix';
            });
            final clippedList = list('clippedElements');
            section('Clipped interactive elements', clippedList, (c) {
              final target = c['target'] ?? c['type'] ?? 'Element';
              final issue = c['issue'] ?? 'partially clipped';
              final src = c['source'] != null ? ' at ${c['source']}' : '';
              return '"$target"$src: $issue';
            });
          }
          if (category == 'all' || category == 'a11y') {
            section('Small tap targets', targets, (a) {
              final src = a['source'] != null ? ' at ${a['source']}' : '';
              final fix = a['source'] != null
                  ? '\n  → Fix: apply_patch_and_verify(target: "${a['source']}", wrapWith: "SizedBox(width: 48, height: 48)") or add padding'
                  : '';
              return '`${a['target']}` (${a['type']})$src: ${a['issue']}$fix';
            });
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
          }
          if (category == 'all' || category == 'contrast') {
            section('Low contrast text', contrast, (c) => '$c');
          }
          if (category == 'all') {
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
          }
          if (buffer.isEmpty) {
            buffer.writeln(
              category == 'all'
                  ? 'No layout overflows, small tap targets, unlabeled controls, '
                        'low-contrast text or reading order jumps.'
                  : 'No $category findings on screen.',
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
        final restore = p['restore'] != false;

        String formatTokenAudit(
          Map<String, dynamic> data, {
          String filterType = 'all',
        }) {
          final colors = ((data['unthemedColors'] as List?) ?? const [])
              .where(matchesQuery)
              .toList();
          final radii = ((data['offGridRadii'] as List?) ?? const [])
              .where(matchesQuery)
              .toList();
          final colorCount = data['unthemedColorCount'] ?? colors.length;
          final radiusCount = data['offGridRadiusCount'] ?? radii.length;
          final buf = StringBuffer(
            'Checked ${data['checked'] ?? 0} colors and radii set in the '
            'app\'s code on this screen.',
          );
          if (colors.isEmpty && radii.isEmpty) {
            buf.write(' All come from the theme.');
          }
          String at(Map m) =>
              m['location'] != null ? ' at ${m['location']}' : '';
          if (colors.isNotEmpty &&
              (filterType == 'all' || filterType == 'colors')) {
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
          if (radii.isNotEmpty &&
              (filterType == 'all' || filterType == 'radii')) {
            buf.write('\nCorner radii off the 4dp grid ($radiusCount):');
            for (final r in radii.cast<Map>()) {
              buf.write(
                '\n  ${r['radius']} in ${r['widget']}${at(r)} '
                '(nearest: ${r['nearest']})',
              );
            }
          }
          return buf.toString();
        }

        final requestedCategory = p['category']?.toString() ?? 'all';
        if (requestedCategory == 'tokens') {
          final res = await _callExtensionRaw(
            'ext.flutterpilot.auditDesignTokens',
            {},
          );
          if (res.isError) {
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
          if (data['unavailable'] != null) {
            final msg = '${data['unavailable']}';
            return CallToolResult(
              isError: true,
              content: [TextContent(text: msg)],
              structuredContent: auditVerdict(
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
                reason: msg,
              ),
            );
          }
          return CallToolResult(
            content: [TextContent(text: formatTokenAudit(data))],
            structuredContent: auditVerdict(
              requested: 0,
              visited: 0,
              audited: 1,
              failed: 0,
              skipped: 0,
              findings: const {},
              restored: true,
              incomplete: false,
              loading: false,
              status: 'ok',
            ),
          );
        }

        final kbHeight = ((p['keyboardInset'] ?? p['height']) as num?)
            ?.toDouble();
        if (kbHeight != null) {
          final setRes = await _callExtensionRaw(
            'ext.flutterpilot.setKeyboardInset',
            {'inset': kbHeight.toString()},
          );
          if (setRes.isError) {
            return withVerdict(
              setRes.toCallToolResult(),
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
                reason: setRes.errorMessage,
              ),
            );
          }

          try {
            await Future<void>.delayed(const Duration(milliseconds: 150));
            final results = await Future.wait([
              _callExtensionRaw(
                'ext.flutterpilot.auditScreenHealth',
                auditParams,
              ),
              _callExtensionRaw('ext.flutterpilot.getInteractiveElements', {}),
            ]);
            final audit = results[0];
            if (audit.isError) {
              return withVerdict(
                audit.toCallToolResult(),
                auditVerdict(
                  requested: 0,
                  visited: 0,
                  audited: 0,
                  failed: 1,
                  skipped: 0,
                  findings: const {},
                  restored: restore || kbHeight <= 0,
                  incomplete: true,
                  loading: false,
                  status: 'unavailable',
                  reason: audit.errorMessage,
                ),
              );
            }
            final interactive = results[1];
            final auditData = audit.data ?? const <String, dynamic>{};
            final overflows = (auditData['overflows'] as List?) ?? const [];
            final elements =
                (interactive.data?['elements'] as List?) ?? const [];
            final focusedInput = elements.firstWhere(
              (el) => el is Map && el['isFocused'] == true,
              orElse: () => null,
            );

            var focusedObscured = false;
            if (focusedInput is Map && focusedInput['bounds'] is Map) {
              final bounds = focusedInput['bounds'] as Map;
              final bottomY =
                  (bounds['y'] as num? ?? 0) + (bounds['height'] as num? ?? 0);
              final viewHeight =
                  (setRes.data?['height'] as num?)?.toDouble() ?? 844.0;
              if (bottomY > viewHeight - kbHeight) {
                focusedObscured = true;
              }
            }

            final hasOverflow = overflows.isNotEmpty;
            final pass = !hasOverflow && !focusedObscured;
            final buf = StringBuffer(
              'Simulated on-screen keyboard (${kbHeight.toInt()}dp)'
              '${restore ? ' (restored)' : ''}:\n',
            );
            if (pass) {
              buf.write(
                '✓ Screen layout is clean with keyboard open. No overflows.',
              );
            } else {
              buf.write('✗ Layout defects detected with keyboard open:');
              if (hasOverflow) {
                buf.write(
                  '\n  • RenderFlex bottom overflow (${overflows.length} issue(s)):',
                );
                for (final o in overflows) {
                  final src = o['source'] != null ? ' at ${o['source']}' : '';
                  buf.write('\n    - ${o['details'] ?? o['type']}$src');
                  if (o['source'] != null) {
                    buf.write(
                      '\n      → Fix: apply_patch_and_verify(target: "${o['source']}", wrapWith: "SingleChildScrollView")',
                    );
                  }
                }
                buf.write(
                  '\n  Prescription: Wrap the screen body in SingleChildScrollView or set Scaffold.resizeToAvoidBottomInset: false.',
                );
              }
              if (focusedObscured) {
                final name =
                    focusedInput['label'] ?? focusedInput['key'] ?? 'input';
                buf.write(
                  '\n  • Focused text field "$name" is obscured behind the keyboard.',
                );
                buf.write(
                  '\n  Prescription: Ensure the input is within a Scrollable or call Scrollable.ensureVisible.',
                );
              }
            }

            return CallToolResult(
              content: [TextContent(text: buf.toString())],
              structuredContent: auditVerdict(
                requested: 0,
                visited: 0,
                audited: 1,
                failed: 0,
                skipped: 0,
                findings: screenFindings(auditData),
                restored: restore || kbHeight <= 0,
                incomplete: false,
                loading: false,
                status: 'ok',
                reason: focusedObscured
                    ? 'Focused input is obscured behind simulated keyboard'
                    : null,
              ),
            );
          } finally {
            if (restore && kbHeight > 0) {
              await _callExtensionRaw('ext.flutterpilot.setKeyboardInset', {
                'inset': '0',
              });
            }
          }
        }

        if (viewports.isNotEmpty) {
          final context = await _deviceContextForParameters(p);
          final vm = context?.service;
          int? pid;
          try {
            pid = vm == null ? null : (await vm.getVM()).pid;
          } catch (_) {}
          final initialOs = pid != null && context?.operatingSystem == 'macos'
              ? await readAppWindowSize(pid)
              : null;
          final snapshot = await _callExtensionRaw(
            'ext.flutterpilot.getAppSnapshot',
            {},
          );
          if (snapshot.isError && vm == null) {
            return withVerdict(
              snapshot.toCallToolResult(),
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
                reason: snapshot.errorMessage,
              ),
            );
          }
          final initialViewport = snapshot.data?['viewport'];

          const presets = <String, ({int width, int height})>{
            'phone': (width: 390, height: 844),
            'mobile_portrait': (width: 390, height: 844),
            'mobile_landscape': (width: 844, height: 390),
            'tablet': (width: 768, height: 1024),
            'desktop': (width: 1280, height: 800),
          };

          final matrixBuffer = StringBuffer(
            'Responsive Viewport Matrix (${viewports.length} viewport${viewports.length == 1 ? '' : 's'}):\n',
          );
          final totals = <String, int>{};
          var audited = 0;
          var failed = 0;
          var usedOsResize = false;
          var usedInAppResize = false;

          try {
            for (final vp in viewports) {
              final sz = presets[vp.toLowerCase()] ?? parseWindowSize(vp);
              if (sz == null) {
                matrixBuffer.writeln('• $vp: Skipped (unknown dimensions)');
                failed++;
                continue;
              }
              final dim = '${sz.width}x${sz.height}';
              final osResized = await _setWindowSize(p, dim);
              if (!osResized.failed) {
                usedOsResize = true;
              } else {
                final appResized = await _callExtensionRaw(
                  'ext.flutterpilot.setWindowSize',
                  {'width': '${sz.width}', 'height': '${sz.height}'},
                );
                if (appResized.isError) {
                  matrixBuffer.writeln(
                    '• $vp ($dim): Failed (${osResized.line})',
                  );
                  failed++;
                  continue;
                }
                usedInAppResize = true;
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }

              final res = await _callExtensionRaw(
                'ext.flutterpilot.auditScreenHealth',
                auditParams,
              );
              if (res.isError) {
                matrixBuffer.writeln('• $vp ($dim): Audit failed');
                failed++;
                continue;
              }
              audited++;
              final data = res.data ?? const <String, dynamic>{};
              addFindings(totals, screenFindings(data));
              final ov = (data['overflows'] as List?) ?? const [];
              final cramped = (data['crampedScrollables'] as List?) ?? const [];

              if (ov.isEmpty && cramped.isEmpty) {
                matrixBuffer.writeln('• $vp ($dim): PASS (0 overflows)');
              } else {
                matrixBuffer.writeln(
                  '• $vp ($dim): FAIL (${ov.length} overflow${ov.length == 1 ? '' : 's'}, ${cramped.length} cramped)',
                );
                for (final o in ov) {
                  final src = o['source'] != null ? ' at ${o['source']}' : '';
                  matrixBuffer.writeln(
                    '    - ${o['type']}$src: ${o['details']}',
                  );
                  if (o['source'] != null) {
                    matrixBuffer.writeln(
                      '      → Fix: apply_patch_and_verify(target: "${o['source']}", wrapWith: "Expanded")',
                    );
                  }
                }
                for (final c in cramped) {
                  matrixBuffer.writeln(
                    '    - Cramped: ${c['details'] ?? c['type']}',
                  );
                }
              }
            }
          } finally {
            if (restore) {
              if (usedOsResize && initialOs != null) {
                await _setWindowSize(p, initialOs);
              }
              if (usedInAppResize) {
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
              }
              matrixBuffer.writeln('✓ Restored initial viewport.');
            }
          }

          return CallToolResult(
            content: [TextContent(text: matrixBuffer.toString().trim())],
            structuredContent: auditVerdict(
              requested: 0,
              visited: 0,
              audited: audited,
              failed: failed,
              skipped: 0,
              findings: totals,
              restored: restore,
              incomplete: failed > 0,
              loading: false,
              status: failed > 0
                  ? (audited == 0 ? 'unavailable' : 'partial')
                  : 'ok',
            ),
          );
        }

        if (routes.isEmpty) {
          final includeDesignQuality = p['designQuality'] == true;
          final auditFuture = _callExtensionRaw(
            'ext.flutterpilot.auditScreenHealth',
            auditParams,
          );
          final tokensFuture = includeDesignQuality
              ? _callExtensionRaw('ext.flutterpilot.auditDesignTokens', {})
              : null;
          final res = await auditFuture;
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
          var body = report(data, sweep: false);
          if (tokensFuture != null) {
            final tokens = await tokensFuture;
            final tData = tokens.data ?? const <String, dynamic>{};
            if (!tokens.isError && tData['unavailable'] == null) {
              body = '$body\n\n${formatTokenAudit(tData)}';
            }
          }
          return CallToolResult(
            content: [TextContent(text: body)],
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
          final pair = await Future.wait([
            _callExtensionRaw('ext.flutterpilot.screenNow', {}),
            _callExtensionRaw(
              'ext.flutterpilot.auditScreenHealth',
              auditParams,
            ),
          ]);
          final now = pair[0];
          final post = now.data?['postActionState'] as Map?;
          final errors = (post?['newErrorCount'] as num?)?.toInt() ?? 0;
          final res = pair[1];
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
      'execute_action_chain',
      description:
          'Runs steps in order, stopping on failure; returns step outcomes '
          'and final screen state.',
      inputSchema: ToolInputSchema(
        properties: {
          'steps': JsonSchema.array(
            items: compositeStepSchema(),
            description: 'Ordered list of {tool, arguments} steps.',
          ),
          'exportAsTest': JsonSchema.boolean(
            description: 'Write executed flow as an integration test.',
          ),
          'testName': JsonSchema.string(description: 'Generated test name.'),
          'testFilePath': JsonSchema.string(
            description: 'Output test file path.',
          ),
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
            final isolateId = vm == null ? null : await _uiIsolateId(vm, null);
            final entry = isolateId == null
                ? null
                : await _appEntrypoint(vm!, isolateId);
            final root = entry?.root ?? Directory.current.path;
            final mainImport = entry?.mainImport ?? 'package:app/main.dart';
            final testName =
                p['testName']?.toString() ?? 'Action Chain Journey';
            final sanitizedName = testName.toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9_]'),
              '_',
            );
            final relPath =
                p['testFilePath']?.toString() ??
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
          final resSteps = (res.data?['steps'] as List?) ?? const [];
          for (var i = 0; i < resSteps.length; i++) {
            final step = resSteps[i];
            if (step is! Map) continue;
            final index = (step['index'] as num?)?.toInt() ?? i;
            if (index < 0 || index >= steps.length) continue;
            final stepDef = steps[index];
            final status = step['status']?.toString();
            if (Verification.checks.contains(stepDef.tool) &&
                (status == 'ok' ||
                    status == 'assertionFailed' ||
                    status == 'timeout')) {
              _verification?.record(
                stepDef.tool,
                stepDef.arguments,
                status == 'ok' ? 'ok' : (failure ?? status ?? 'failed'),
                isError: status != 'ok',
              );
            }
            final note = step['note'];
            final hasNote = note is String && note.isNotEmpty;
            if (status == 'ok' && (steps.length > 1 || hasNote)) {
              buffer.write(
                'Step ${index + 1} ${stepDef.tool}: '
                '${hasNote ? note : 'ok'}\n',
              );
            }
          }
          buffer.write(_formatActionFeedback('Chain finished', const {}, res));
          final exported = await exportJourney(passed: failure == null);
          if (exported != null) {
            buffer.writeln(
              '\n✓ Exported journey to runnable integration test: $exported',
            );
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

        // Mixed chains batch contiguous segments of >= 2 in-app steps into
        // single RPCs instead of paying one round-trip per step.
        final progress = ToolProgress(e, total: steps.length.toDouble());
        final outcomes = <String>[];
        var failed = false;
        int? failedStep;
        var completed = 0;
        var index = 0;
        while (index < steps.length) {
          if (progress.cancelled) {
            outcomes.add('Cancelled before running ${steps[index].tool}.');
            failed = true;
            failedStep = index + 1;
            break;
          }

          final segmentInApp = <Map<String, String>>[];
          for (var j = index; j < steps.length; j++) {
            final action = inAppChainAction(steps[j]);
            if (action == null) break;
            segmentInApp.add(action);
          }
          if (segmentInApp.length >= 2) {
            final end = index + segmentInApp.length;
            await progress.advance(
              'Steps ${index + 1}-$end/${steps.length}: in-app batch',
            );
            final res = await _callExtensionRaw(
              'ext.flutterpilot.executeActionChain',
              {'actions': json.encode(segmentInApp)},
            );
            if (res.isError) {
              outcomes.add(res.errorMessage ?? 'Action batch failed.');
              failed = true;
              failedStep = index + 1;
              break;
            }
            final executed = (res.data?['executedCount'] as num?)?.toInt() ?? 0;
            final failure = res.data?['failure'] as String?;
            final resSteps = (res.data?['steps'] as List?) ?? const [];
            final isFinalSegment = end == steps.length && failure == null;
            for (var k = 0; k < executed && k < segmentInApp.length; k++) {
              final s = k < resSteps.length && resSteps[k] is Map
                  ? resSteps[k] as Map
                  : const {};
              final note = s['note']?.toString();
              var outcome = note != null && note.isNotEmpty ? note : 'ok';
              if (isFinalSegment && k == executed - 1) {
                final feedback = _formatActionFeedback(
                  'Chain finished',
                  const {},
                  res,
                );
                if (feedback.isNotEmpty) outcome = '$outcome\n$feedback';
              }
              if (Verification.checks.contains(steps[index + k].tool)) {
                _verification?.record(
                  steps[index + k].tool,
                  steps[index + k].arguments,
                  outcome,
                  isError: false,
                );
              }
              outcomes.add(outcome);
              completed++;
            }
            if (failure != null) {
              final failIdx = index + executed;
              if (failIdx < steps.length &&
                  Verification.checks.contains(steps[failIdx].tool)) {
                _verification?.record(
                  steps[failIdx].tool,
                  steps[failIdx].arguments,
                  failure,
                  isError: true,
                );
              }
              outcomes.add(failure);
              failed = true;
              failedStep = failIdx + 1;
              break;
            }
            index = end;
            continue;
          }

          final step = steps[index];
          await progress.advance(
            'Step ${index + 1}/${steps.length}: ${step.tool}',
          );
          final stepArgs = Map<String, dynamic>.of(step.arguments);
          if (step.tool == 'tap_widget' &&
              index < steps.length - 1 &&
              stepArgs['waitFor'] == null &&
              stepArgs['failureKey'] == null &&
              stepArgs['anyOf'] == null) {
            stepArgs.putIfAbsent('quickSettle', () => true);
          }
          final res = await _toolCallbacks[step.tool]!(stepArgs, e);
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
          index++;
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
            content: [TextContent(text: fullText)],
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
