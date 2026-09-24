part of '../../flutterpilot_sdk.dart';

/// Widget interaction and inspection service extensions.
///
/// Registers the following `ext.flutterpilot.*` service extensions:
/// - `tapWidget` — Tap a widget by key or semantic selector
/// - `enterText` — Enter text in a text field by key or semantic selector
/// - `scrollIntoView` — Scroll a widget into the visible viewport
/// - `doubleTapWidget` — Double-tap a widget by key or selector
/// - `longPressWidget` — Long-press a widget by key or selector
/// - `swipeWidget` — Swipe from a widget center in a direction
/// - `dragWidget` — Drag from one widget to another
/// - `clearTextField` — Clear a text field by key or selector
/// - `focusWidget` — Focus a widget by key or selector
/// - `toggleCheckbox` — Toggle a Checkbox/Switch/Radio
/// - `setSliderValue` — Set a Slider's value
/// - `getWidgetProperties` — Read semantic properties of a widget
/// - `getWidgetTree` — Capture the full widget tree as JSON
/// - `assertWidgetVisible` — Assert a widget exists and has layout
/// - `assertTextVisible` — Assert text is visible on screen
/// - `assertWidgetCount` — Assert count of widgets of a type
/// - `assertWidgetEnabled` — Assert a widget is enabled
/// - `assertWidgetDisabled` — Assert a widget is disabled
/// - `unfocusAll` — Remove focus from all widgets
extension _WidgetExtensions on FlutterPilot {
  static final KeyboardSimulator _keyboardSimulator = KeyboardSimulator();

  static String _makeWidgetNotFoundMessage(String target) {
    final suggestions = PilotWidgetInspector.getAvailableActionableTargets();
    if (suggestions.isNotEmpty) {
      return 'Widget not found matching: "$target".\n'
          'HINT: Visible actionable targets on current screen:\n'
          '${suggestions.map((s) => ' • "$s"').join('\n')}\n'
          'Or call get_widget_tree() / get_interactive_elements() to inspect the UI hierarchy.';
    }
    return 'Widget not found matching: "$target". HINT: Call get_interactive_elements() or get_widget_tree() to inspect available widgets.';
  }

  static void register() {
    // -- ext.flutterpilot.tapWidget -------------------------------------------
    registerExtension('ext.flutterpilot.tapWidget', (method, parameters) async {
      final xVal = double.tryParse(parameters['x'] ?? '');
      final yVal = double.tryParse(parameters['y'] ?? '');
      if (xVal != null && yVal != null) {
        final routeBefore = NavigationTracker.currentRoute;
        if (FlutterPilot._isRecording) {
          FlutterPilot._recordAction('tapAt', {'x': xVal, 'y': yVal});
        }
        await InteractionManager.tapAt(
          Offset(xVal, yVal),
          label: '(${xVal.round()}, ${yVal.round()})',
        );
        final routeAfter = NavigationTracker.currentRoute;
        return ServiceExtensionResponse.result(
          json.encode({
            'status': 'success',
            'coordinates': {'x': xVal, 'y': yVal},
            'delta': {
              'navigated': routeBefore != routeAfter,
              'fromRoute': routeBefore,
              'toRoute': routeAfter,
            },
          }),
        );
      }

      int? semanticsId = int.tryParse(parameters['semanticsId'] ?? '');
      final rawTarget = parameters['key'] ??
          parameters['target'] ??
          parameters['identifier'] ??
          parameters['text'] ??
          parameters['type'];

      if (semanticsId == null && rawTarget != null) {
        final semMatch = RegExp(r'^(?:semantics:|Semantics#|id:)(\d+)$', caseSensitive: false)
            .firstMatch(rawTarget.toString().trim());
        if (semMatch != null) {
          semanticsId = int.tryParse(semMatch.group(1)!);
        }
      }

      if (semanticsId != null) {
        FlutterPilot._semanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
        SemanticsNode? root;
        try {
          root = RendererBinding.instance.rootPipelineOwner.semanticsOwner?.rootSemanticsNode;
        } catch (_) {}

        SemanticsNode? targetNode;
        if (root != null) {
          void search(SemanticsNode node) {
            if (targetNode != null) return;
            if (node.id == semanticsId) {
              targetNode = node;
              return;
            }
            node.visitChildren((child) {
              search(child);
              return targetNode == null;
            });
          }
          search(root);
        }

        if (targetNode != null) {
          Matrix4 transform = Matrix4.identity();
          SemanticsNode? curr = targetNode;
          while (curr != null) {
            if (curr.transform != null) {
              transform = curr.transform!.multiplied(transform);
            }
            curr = curr.parent;
          }
          final globalRect = MatrixUtils.transformRect(transform, targetNode!.rect);
          final center = globalRect.center;
          final routeBefore = NavigationTracker.currentRoute;
          if (FlutterPilot._isRecording) {
            FlutterPilot._recordAction('tapWidget', {'semanticsId': semanticsId});
          }
          await InteractionManager.tapAt(center, label: 'Semantics #$semanticsId');
          final routeAfter = NavigationTracker.currentRoute;
          final postActionState = FlutterPilot.getPostActionState(previousRoute: routeBefore);
          return ServiceExtensionResponse.result(
            json.encode({
              'status': 'success',
              'semanticsId': semanticsId,
              'coordinates': {'x': center.dx, 'y': center.dy},
              'postActionState': postActionState,
              'delta': {
                'navigated': routeBefore != routeAfter,
                'fromRoute': routeBefore,
                'toRoute': routeAfter,
              },
            }),
          );
        } else {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            'SemanticsNode with id $semanticsId not found in the current semantics tree.',
          );
        }
      }

      final target = rawTarget;
      final maxAttempts = int.tryParse(parameters['maxAttempts'] ?? '') ?? 8;

      if (target == null || target.isEmpty) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key, target, identifier, text, semanticsId, or coordinates (x, y)',
        );
      }

      var element = PilotWidgetInspector.findElement(target);
      if (element == null || !HitTestUtils.isElementHittable(element)) {
        await ScrollSimulator.scrollUntilVisible(target, maxAttempts: maxAttempts);
        element = PilotWidgetInspector.findElement(target);
      }

      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          _makeWidgetNotFoundMessage(target),
        );
      }

      final routeBefore = NavigationTracker.currentRoute;
      RenderObject? ro = element.renderObject;
      if (ro is! RenderBox || !ro.hasSize || !ro.attached || !HitTestUtils.isElementHittable(element)) {
        try {
          await Scrollable.ensureVisible(
            element,
            duration: const Duration(milliseconds: 150),
            alignment: 0.5,
          );
          await InteractionManager.pumpAndSettleAdaptive();
          ro = element.renderObject;
        } catch (_) {}
      }

      if (ro is RenderBox && ro.hasSize && ro.attached) {
        final pos = ro.localToGlobal(ro.size.center(Offset.zero));
        if (FlutterPilot._isRecording) {
          FlutterPilot._recordAction('tapWidget', {'key': target});
        }
        await InteractionManager.tapAt(pos, label: target);
        final routeAfter = NavigationTracker.currentRoute;
        final postActionState =
            FlutterPilot.getPostActionState(previousRoute: routeBefore);
        return ServiceExtensionResponse.result(
          json.encode({
            'status': 'success',
            'target': target,
            'postActionState': postActionState,
            'delta': {
              'navigated': routeBefore != routeAfter,
              'fromRoute': routeBefore,
              'toRoute': routeAfter,
            },
          }),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'No layout for target: $target',
      );
    });

    // -- ext.flutterpilot.secondaryTapWidget ----------------------------------
    registerExtension('ext.flutterpilot.secondaryTapWidget', (
      method,
      parameters,
    ) async {
      final xVal = double.tryParse(parameters['x'] ?? '');
      final yVal = double.tryParse(parameters['y'] ?? '');
      if (xVal != null && yVal != null) {
        await InteractionManager.secondaryTapAt(
          Offset(xVal, yVal),
          label: 'Right Click (${xVal.round()}, ${yVal.round()})',
        );
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success', 'coordinates': {'x': xVal, 'y': yVal}}),
        );
      }

      final target = parameters['key'] ??
          parameters['target'] ??
          parameters['identifier'] ??
          parameters['text'];

      if (target == null || target.isEmpty) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key, target, identifier, or coordinates',
        );
      }

      var element = PilotWidgetInspector.findElement(target);
      if (element == null || !HitTestUtils.isElementHittable(element)) {
        await ScrollSimulator.scrollUntilVisible(target);
        element = PilotWidgetInspector.findElement(target);
      }

      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          _makeWidgetNotFoundMessage(target),
        );
      }

      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize && ro.attached) {
        final pos = ro.localToGlobal(ro.size.center(Offset.zero));
        await InteractionManager.secondaryTapAt(pos, label: 'Right Click: $target');
        final postActionState = FlutterPilot.getPostActionState();
        return ServiceExtensionResponse.result(
          json.encode({
            'status': 'success',
            'target': target,
            'postActionState': postActionState,
          }),
        );
      }

      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'No layout for target: $target',
      );
    });

    // -- ext.flutterpilot.enterText -------------------------------------------
    registerExtension('ext.flutterpilot.enterText', (method, parameters) async {
      final target = parameters['key'] ??
          parameters['target'] ??
          parameters['identifier'] ??
          parameters['text'];
      final text = parameters['text'] ?? parameters['value'];
      final isFocusedRequested = parameters['focused_element'] == 'true' ||
          target == 'focused' ||
          target == null ||
          target.isEmpty;

      if (text == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing text parameter',
        );
      }

      EditableTextState? editableTextState;

      // 1. Try focused element if requested or no target given
      if (isFocusedRequested) {
        final focusNode = FocusManager.instance.primaryFocus;
        final ctx = focusNode?.context;
        if (ctx != null) {
          ctx.visitAncestorElements((e) {
            if (e is StatefulElement && e.state is EditableTextState) {
              editableTextState = e.state as EditableTextState;
              return false;
            }
            return true;
          });
        }
      }

      // 2. If not found or target was explicit, find via widget inspector
      if (editableTextState == null && target != null && target.isNotEmpty) {
        var element = PilotWidgetInspector.findElement(target);
        if (element == null) {
          await ScrollSimulator.scrollUntilVisible(target);
          element = PilotWidgetInspector.findElement(target);
        }
        if (element == null) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionError,
            _makeWidgetNotFoundMessage(target),
          );
        }

        void findText(Element e) {
          if (editableTextState != null) return;
          if (e is StatefulElement && e.state is EditableTextState) {
            editableTextState = e.state as EditableTextState;
            return;
          }
          e.visitChildren(findText);
        }

        findText(element);
      }

      if (editableTextState != null) {
        editableTextState!.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
        WidgetsBinding.instance.scheduleFrame();
        await InteractionManager.pumpAndSettleAdaptive();

        if (FlutterPilot._isRecording) {
          FlutterPilot._recordAction('enterText', {
            'key': target ?? 'focused',
            'text': text,
          });
        }

        final postActionState = FlutterPilot.getPostActionState();
        return ServiceExtensionResponse.result(
          json.encode({
            'status': 'success',
            'text': text,
            'postActionState': postActionState,
          }),
        );
      }

      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'Could not find text input field for "${target ?? 'focused element'}"',
      );
    });

    // -- ext.flutterpilot.pressKey --------------------------------------------
    registerExtension('ext.flutterpilot.pressKey', (method, parameters) async {
      final key = parameters['key'];
      if (key == null || key.isEmpty) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key parameter (e.g. "enter", "tab", "backspace", "escape", "a")',
        );
      }
      final modifiersStr = parameters['modifiers'] ?? '';
      final modifiers = modifiersStr
          .split(',')
          .map((m) => m.trim())
          .where((m) => m.isNotEmpty)
          .toSet();

      try {
        await _keyboardSimulator.pressKey(key, modifiers: modifiers);
        if (FlutterPilot._isRecording) {
          FlutterPilot._recordAction('pressKey', {
            'key': key,
            'modifiers': modifiers.toList(),
          });
        }
        final postActionState = FlutterPilot.getPostActionState();
        return ServiceExtensionResponse.result(
          json.encode({
            'status': 'success',
            'key': key,
            'modifiers': modifiers.toList(),
            'postActionState': postActionState,
          }),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          e.toString(),
        );
      }
    });

    // -- ext.flutterpilot.getInteractiveElements ------------------------------
    registerExtension('ext.flutterpilot.getInteractiveElements', (
      method,
      parameters,
    ) async {
      final elements = PilotWidgetInspector.getInteractiveElements();
      return ServiceExtensionResponse.result(
        json.encode({
          'status': 'success',
          'count': elements.length,
          'elements': elements,
        }),
      );
    });

    // -- ext.flutterpilot.pinchZoomWidget -------------------------------------
    registerExtension('ext.flutterpilot.pinchZoomWidget', (
      method,
      parameters,
    ) async {
      final scaleStr = parameters['scale'];
      final scale = double.tryParse(scaleStr ?? '');
      if (scale == null || scale <= 0) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'scale must be a positive number (e.g. 1.5 to zoom in, 0.5 to zoom out)',
        );
      }

      Offset center;
      final xVal = double.tryParse(parameters['x'] ?? '');
      final yVal = double.tryParse(parameters['y'] ?? '');
      if (xVal != null && yVal != null) {
        center = Offset(xVal, yVal);
      } else {
        final target = parameters['key'] ?? parameters['target'];
        if (target != null && target.isNotEmpty) {
          final element = PilotWidgetInspector.findElement(target);
          if (element == null) {
            return ServiceExtensionResponse.error(
              ServiceExtensionResponse.extensionError,
              'Widget not found: $target',
            );
          }
          final ro = element.renderObject;
          if (ro is! RenderBox || !ro.hasSize) {
            return ServiceExtensionResponse.error(
              ServiceExtensionResponse.extensionError,
              'No layout for target: $target',
            );
          }
          center = ro.localToGlobal(ro.size.center(Offset.zero));
        } else {
          final view = WidgetsBinding.instance.platformDispatcher.implicitView;
          final size = view?.physicalSize ?? Size.zero;
          final ratio = view?.devicePixelRatio ?? 1.0;
          center = Offset(size.width / ratio / 2, size.height / ratio / 2);
        }
      }

      await InteractionManager.pinchZoomAt(center, scale: scale);
      final postActionState = FlutterPilot.getPostActionState();
      return ServiceExtensionResponse.result(
        json.encode({
          'status': 'success',
          'scale': scale,
          'center': {'x': center.dx, 'y': center.dy},
          'postActionState': postActionState,
        }),
      );
    });

    // -- ext.flutterpilot.scrollIntoView --------------------------------------
    registerExtension('ext.flutterpilot.scrollIntoView', (
      method,
      parameters,
    ) async {
      final target = parameters['key'] ??
          parameters['target'] ??
          parameters['identifier'] ??
          parameters['text'];
      if (target == null || target.isEmpty) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key or target parameter',
        );
      }
      final maxAttempts = int.tryParse(parameters['maxAttempts'] ?? '') ?? 8;
      final success = await ScrollSimulator.scrollUntilVisible(target, maxAttempts: maxAttempts);
      if (!success) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Could not scroll "$target" into visible view',
        );
      }
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success', 'target': target}),
      );
    });


    // -- ext.flutterpilot.doubleTapWidget -------------------------------------
    registerExtension('ext.flutterpilot.doubleTapWidget', (
      method,
      parameters,
    ) async {
      final target = parameters['key'] ?? parameters['target'];
      if (target == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing target',
        );
      }
      final element = PilotWidgetInspector.findElement(target);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $target',
        );
      }
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final pos = ro.localToGlobal(ro.size.center(Offset.zero));
        if (FlutterPilot._isRecording) {
          FlutterPilot._recordAction('doubleTapWidget', {'key': target});
        }
        await InteractionManager.doubleTapAt(pos, label: target);
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success'}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'No layout for widget: $target',
      );
    });

    // -- ext.flutterpilot.longPressWidget -------------------------------------
    registerExtension('ext.flutterpilot.longPressWidget', (
      method,
      parameters,
    ) async {
      final target = parameters['key'] ?? parameters['target'];
      final ms = int.tryParse(parameters['durationMs'] ?? '600') ?? 600;
      if (target == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing target',
        );
      }
      final element = PilotWidgetInspector.findElement(target);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $target',
        );
      }
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize) {
        final pos = ro.localToGlobal(ro.size.center(Offset.zero));
        if (FlutterPilot._isRecording) {
          FlutterPilot._recordAction('longPressWidget', {
            'key': target,
            'durationMs': ms,
          });
        }
        await InteractionManager.longPressAt(
          pos,
          duration: Duration(milliseconds: ms),
          label: target,
        );
        return ServiceExtensionResponse.result(
          json.encode({'status': 'success'}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'No layout for widget: $target',
      );
    });

    // -- ext.flutterpilot.swipeWidget -----------------------------------------
    registerExtension('ext.flutterpilot.swipeWidget', (
      method,
      parameters,
    ) async {
      final target = parameters['key'] ?? parameters['target'];
      final direction = parameters['direction'] ?? 'up';
      final distance =
          double.tryParse(parameters['distance'] ?? '200') ?? 200.0;
      if (target == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing target',
        );
      }
      final element = PilotWidgetInspector.findElement(target);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $target',
        );
      }
      final ro = element.renderObject;
      if (ro is! RenderBox || !ro.hasSize) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No layout for widget: $target',
        );
      }
      final start = ro.localToGlobal(ro.size.center(Offset.zero));
      final Offset end;
      switch (direction) {
        case 'up':
          end = start.translate(0, -distance);
        case 'down':
          end = start.translate(0, distance);
        case 'left':
          end = start.translate(-distance, 0);
        case 'right':
          end = start.translate(distance, 0);
        default:
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'direction must be up|down|left|right',
          );
      }
      if (FlutterPilot._isRecording) {
        FlutterPilot._recordAction('swipeWidget', {
          'key': target,
          'direction': direction,
          'distance': distance,
        });
      }
      await InteractionManager.swipeFromTo(start, end);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });

    // -- ext.flutterpilot.dragWidget ------------------------------------------
    registerExtension('ext.flutterpilot.dragWidget', (
      method,
      parameters,
    ) async {
      final fromTarget = parameters['fromKey'] ?? parameters['from'];
      final toTarget = parameters['toKey'] ?? parameters['to'];
      if (fromTarget == null || toTarget == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing from or to target',
        );
      }
      final fromEl = PilotWidgetInspector.findElement(fromTarget);
      final toEl = PilotWidgetInspector.findElement(toTarget);
      if (fromEl == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $fromTarget',
        );
      }
      if (toEl == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $toTarget',
        );
      }
      final fromRo = fromEl.renderObject;
      final toRo = toEl.renderObject;
      if (fromRo is! RenderBox ||
          !fromRo.hasSize ||
          toRo is! RenderBox ||
          !toRo.hasSize) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No layout for one or both widgets',
        );
      }
      final from = fromRo.localToGlobal(fromRo.size.center(Offset.zero));
      final to = toRo.localToGlobal(toRo.size.center(Offset.zero));
      if (FlutterPilot._isRecording) {
        FlutterPilot._recordAction('dragWidget', {
          'fromKey': fromTarget,
          'toKey': toTarget,
        });
      }
      await InteractionManager.dragFromTo(from, to);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });

    // -- ext.flutterpilot.clearTextField --------------------------------------
    registerExtension('ext.flutterpilot.clearTextField', (
      method,
      parameters,
    ) async {
      final target = parameters['key'] ?? parameters['target'];
      if (target == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: key or target',
        );
      }
      final element = PilotWidgetInspector.findElement(target);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $target',
        );
      }
      bool found = false;
      void clearText(Element e) {
        if (found) return;
        if (e is StatefulElement && e.state is EditableTextState) {
          try {
            final state = e.state;
            if (state is EditableTextState) {
              state.updateEditingValue(TextEditingValue.empty);
              found = true;
            }
          } catch (_) {
            try {
              (e.state as dynamic).controller.clear();
              found = true;
            } catch (_) {}
          }
          if (found && FlutterPilot._isRecording) {
            FlutterPilot._recordAction('clearTextField', {'key': target});
          }
          return;
        }
        e.visitChildren(clearText);
      }

      clearText(element);
      return found
          ? ServiceExtensionResponse.result(json.encode({'status': 'success'}))
          : ServiceExtensionResponse.error(
              ServiceExtensionResponse.extensionError,
              'No text field found under target: $target',
            );
    });

    // -- ext.flutterpilot.focusWidget -----------------------------------------
    registerExtension('ext.flutterpilot.focusWidget', (
      method,
      parameters,
    ) async {
      final target = parameters['key'] ?? parameters['target'];
      if (target == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: key or target',
        );
      }
      final element = PilotWidgetInspector.findElement(target);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $target',
        );
      }
      final renderObject = element.renderObject;
      if (renderObject is! RenderBox) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget "$target" has no renderable box',
        );
      }
      final offset = renderObject.localToGlobal(Offset.zero);
      final center =
          offset +
          Offset(renderObject.size.width / 2, renderObject.size.height / 2);
      await InteractionManager.tapAt(center, label: target);
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });

    // -- ext.flutterpilot.toggleCheckbox --------------------------------------
    registerExtension('ext.flutterpilot.toggleCheckbox', (
      method,
      parameters,
    ) async {
      final target = parameters['key'] ?? parameters['target'];
      if (target == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: key or target',
        );
      }
      final element = PilotWidgetInspector.findElement(target);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $target',
        );
      }
      RenderBox? renderBox;
      void findToggleable(Element e) {
        if (renderBox != null) return;
        final w = e.widget;
        if (w is Checkbox || w is Switch || w is Radio) {
          renderBox = e.renderObject as RenderBox?;
          return;
        }
        e.visitChildren(findToggleable);
      }

      if (element.widget is Checkbox ||
          element.widget is Switch ||
          element.widget is Radio) {
        renderBox = element.renderObject as RenderBox?;
      } else {
        findToggleable(element);
      }
      renderBox ??= element.renderObject as RenderBox?;
      if (renderBox == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget "$target" has no renderable box',
        );
      }
      final box = renderBox!;
      final offset = box.localToGlobal(Offset.zero);
      final center = offset + Offset(box.size.width / 2, box.size.height / 2);
      await InteractionManager.tapAt(center, label: target);
      if (FlutterPilot._isRecording) {
        FlutterPilot._recordAction('toggleCheckbox', {'key': target});
      }
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });

    // -- ext.flutterpilot.setSliderValue --------------------------------------
    registerExtension('ext.flutterpilot.setSliderValue', (
      method,
      parameters,
    ) async {
      final target = parameters['key'] ?? parameters['target'];
      final valueStr = parameters['value'];
      if (target == null || valueStr == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameters: target, value',
        );
      }
      final targetValue = double.tryParse(valueStr);
      if (targetValue == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'value must be a numeric string',
        );
      }
      final element = PilotWidgetInspector.findElement(target);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $target',
        );
      }
      Slider? sliderWidget;
      Element? sliderElement;
      void findSlider(Element e) {
        if (sliderWidget != null) return;
        if (e.widget is Slider) {
          sliderWidget = e.widget as Slider;
          sliderElement = e;
          return;
        }
        e.visitChildren(findSlider);
      }

      if (element.widget is Slider) {
        sliderWidget = element.widget as Slider;
        sliderElement = element;
      } else {
        findSlider(element);
      }
      if (sliderWidget == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'No Slider found under target: $target',
        );
      }
      final renderBox = sliderElement!.renderObject;
      if (renderBox is! RenderBox) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Slider not rendered',
        );
      }
      final slider = sliderWidget!;
      final min = slider.min;
      final max = slider.max;
      if (max <= min) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Slider min ($min) >= max ($max)',
        );
      }
      final clamped = targetValue.clamp(min, max);
      final fraction = (clamped - min) / (max - min);
      const trackPadding = 24.0;
      final trackWidth = renderBox.size.width - trackPadding * 2;
      if (trackWidth <= 0) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          json.encode({'error': 'Slider too narrow for tap simulation.'}),
        );
      }
      final globalOffset = renderBox.localToGlobal(Offset.zero);
      final tapX = globalOffset.dx + trackPadding + fraction * trackWidth;
      final tapY = globalOffset.dy + renderBox.size.height / 2;
      await InteractionManager.tapAt(Offset(tapX, tapY), label: target);
      if (FlutterPilot._isRecording) {
        FlutterPilot._recordAction('setSliderValue', {
          'key': target,
          'value': clamped,
        });
      }
      return ServiceExtensionResponse.result(
        json.encode({
          'status': 'success',
          'value': clamped,
          'fraction': fraction,
        }),
      );
    });

    // -- ext.flutterpilot.getWidgetProperties ---------------------------------
    registerExtension('ext.flutterpilot.getWidgetProperties', (
      method,
      parameters,
    ) async {
      final target = parameters['key'] ?? parameters['target'];
      if (target == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: key or target',
        );
      }
      final element = PilotWidgetInspector.findElement(target);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $target',
        );
      }
      final props = <String, dynamic>{
        'type': element.widget.runtimeType.toString(),
        'target': target,
      };
      FlutterPilot._extractWidgetProps(element, props);
      return ServiceExtensionResponse.result(json.encode(props));
    });

    // -- ext.flutterpilot.getWidgetTree ---------------------------------------
    registerExtension('ext.flutterpilot.getWidgetTree', (
      method,
      parameters,
    ) async {
      try {
        final ifMutation = int.tryParse(parameters['ifMutation'] ?? parameters['ifVersion'] ?? '');
        if (ifMutation != null &&
            ifMutation == FlutterPilot.screenMutationCount &&
            PilotWidgetInspector.lastCapturedTree != null) {
          return ServiceExtensionResponse.result(
            json.encode({
              'changed': false,
              'mutationCount': FlutterPilot.screenMutationCount,
            }),
          );
        }

        final maxDepth = int.tryParse(parameters['maxDepth'] ?? '');
        final compact = parameters['compact'] != 'false';
        final rootQuery = parameters['rootKey'] ?? parameters['rootSelector'] ?? parameters['root'];
        final tree = PilotWidgetInspector.captureWidgetTree(
          maxDepth: maxDepth,
          compact: compact,
          rootQuery: rootQuery,
        );
        PilotWidgetInspector.lastCapturedTree = tree;
        return ServiceExtensionResponse.result(
          json.encode({
            'changed': true,
            'tree': tree,
            'mutationCount': FlutterPilot.screenMutationCount,
          }),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Error: $e',
        );
      }
    });

    // -- ext.flutterpilot.getWidgetTreeDiff -----------------------------------
    registerExtension('ext.flutterpilot.getWidgetTreeDiff', (
      method,
      parameters,
    ) async {
      try {
        final maxDepth = int.tryParse(parameters['maxDepth'] ?? '');
        final compact = parameters['compact'] != 'false';
        final currentTree = PilotWidgetInspector.captureWidgetTree(
          maxDepth: maxDepth,
          compact: compact,
        );
        final oldTree = PilotWidgetInspector.lastCapturedTree ?? {'type': 'Empty'};
        final diff = PilotWidgetInspector.diffWidgetTrees(oldTree, currentTree);
        PilotWidgetInspector.lastCapturedTree = currentTree;
        return ServiceExtensionResponse.result(
          json.encode({
            'diff': diff,
            'mutationCount': FlutterPilot.screenMutationCount,
          }),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Error: $e',
        );
      }
    });

    // -- ext.flutterpilot.getScreenHash ---------------------------------------
    registerExtension('ext.flutterpilot.getScreenHash', (
      method,
      parameters,
    ) async {
      return ServiceExtensionResponse.result(
        json.encode({
          'mutationCount': FlutterPilot.screenMutationCount,
          'currentRoute': NavigationTracker.currentRoute,
        }),
      );
    });

    // -- ext.flutterpilot.assertWidgetVisible ---------------------------------
    registerExtension('ext.flutterpilot.assertWidgetVisible', (
      method,
      parameters,
    ) async {
      final target = parameters['key'] ?? parameters['target'];
      if (target == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing key or target',
        );
      }
      final element = PilotWidgetInspector.findElement(target);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'ASSERTION FAILED: widget "$target" not found in tree',
        );
      }
      final ro = element.renderObject;
      if (ro is! RenderBox || !ro.hasSize) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'ASSERTION FAILED: widget "$target" found but has no layout (off-screen?)',
        );
      }
      return ServiceExtensionResponse.result(
        json.encode({'status': 'passed', 'target': target}),
      );
    });

    // -- ext.flutterpilot.assertTextVisible -----------------------------------
    registerExtension('ext.flutterpilot.assertTextVisible', (
      method,
      parameters,
    ) async {
      final text = parameters['text'];
      final exact = parameters['exact'] == 'true';
      if (text == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing text',
        );
      }
      bool found = false;
      void findText(Element e) {
        if (found) return;
        if (e.widget is Text) {
          final data = (e.widget as Text).data ?? '';
          found = exact ? data == text : data.contains(text);
        } else if (e.widget is RichText) {
          final plain = (e.widget as RichText).text.toPlainText();
          found = exact ? plain == text : plain.contains(text);
        }
        if (!found) e.visitChildren(findText);
      }

      final root = WidgetsBinding.instance.rootElement;
      if (root != null) findText(root);
      if (found) {
        return ServiceExtensionResponse.result(
          json.encode({'status': 'passed', 'text': text}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'ASSERTION FAILED: text "$text" not visible on screen',
      );
    });

    // -- ext.flutterpilot.assertWidgetCount -----------------------------------
    registerExtension('ext.flutterpilot.assertWidgetCount', (
      method,
      parameters,
    ) async {
      final type = parameters['type'];
      final expectedStr = parameters['count'];
      if (type == null || expectedStr == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing type or count',
        );
      }
      final expected = int.tryParse(expectedStr);
      if (expected == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'count must be an integer',
        );
      }
      int actual = 0;
      void countWidgets(Element e) {
        if (e.widget.runtimeType.toString() == type) actual++;
        e.visitChildren(countWidgets);
      }

      final root = WidgetsBinding.instance.rootElement;
      if (root != null) countWidgets(root);
      if (actual == expected) {
        return ServiceExtensionResponse.result(
          json.encode({'status': 'passed', 'type': type, 'count': actual}),
        );
      }
      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'ASSERTION FAILED: expected $expected "$type" widgets but found $actual',
      );
    });

    // -- ext.flutterpilot.assertWidgetEnabled / assertWidgetDisabled ----------
    registerExtension('ext.flutterpilot.assertWidgetEnabled', (
      method,
      parameters,
    ) async {
      final target = parameters['key'] ?? parameters['target'];
      if (target == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: key or target',
        );
      }
      final element = PilotWidgetInspector.findElement(target);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $target',
        );
      }
      return FlutterPilot._assertWidgetState(
        element,
        target,
        shouldBeEnabled: true,
      );
    });

    registerExtension('ext.flutterpilot.assertWidgetDisabled', (
      method,
      parameters,
    ) async {
      final target = parameters['key'] ?? parameters['target'];
      if (target == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing required parameter: key or target',
        );
      }
      final element = PilotWidgetInspector.findElement(target);
      if (element == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Widget not found: $target',
        );
      }
      return FlutterPilot._assertWidgetState(
        element,
        target,
        shouldBeEnabled: false,
      );
    });

    // -- ext.flutterpilot.unfocusAll ------------------------------------------
    registerExtension('ext.flutterpilot.unfocusAll', (
      method,
      parameters,
    ) async {
      FocusManager.instance.primaryFocus?.unfocus();
      return ServiceExtensionResponse.result(
        json.encode({'status': 'success'}),
      );
    });

    // -- ext.flutterpilot.waitForCondition ------------------------------------
    registerExtension('ext.flutterpilot.waitForCondition', (
      method,
      parameters,
    ) async {
      final selector = parameters['selector'] ?? parameters['target'] ?? parameters['key'];
      final timeoutMs = int.tryParse(parameters['timeoutMs'] ?? '3000') ?? 3000;
      final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

      if (selector == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing selector/target parameter',
        );
      }

      while (DateTime.now().isBefore(deadline)) {
        final element = PilotWidgetInspector.findElement(selector);
        if (element != null) {
          return ServiceExtensionResponse.result(
            json.encode({
              'status': 'matched',
              'selector': selector,
              'elapsedMs': timeoutMs - deadline.difference(DateTime.now()).inMilliseconds,
            }),
          );
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      return ServiceExtensionResponse.error(
        ServiceExtensionResponse.extensionError,
        'Timeout: Element matching "$selector" did not appear within ${timeoutMs}ms',
      );
    });

    // -- ext.flutterpilot.fillForm --------------------------------------------
    registerExtension('ext.flutterpilot.fillForm', (method, parameters) async {
      final fieldsJson = parameters['fields'];
      final submitWith = parameters['submitWith'];
      if (fieldsJson == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing fields map',
        );
      }

      try {
        final dynamic decoded = json.decode(fieldsJson);
        final Map<String, dynamic> fields = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};

        int filledCount = 0;
        for (final entry in fields.entries) {
          final target = entry.key;
          final val = entry.value;
          final element = PilotWidgetInspector.findElement(target);
          if (element != null) {
            if (element.renderObject is! RenderBox || !(element.renderObject as RenderBox).hasSize) {
              try {
                await Scrollable.ensureVisible(
                  element,
                  duration: const Duration(milliseconds: 100),
                  alignment: 0.5,
                );
                await InteractionManager.pumpAndSettleAdaptive();
              } catch (_) {}
            }

            if (val is bool) {
              final ro = element.renderObject;
              if (ro is RenderBox && ro.hasSize) {
                final pos = ro.localToGlobal(ro.size.center(Offset.zero));
                await InteractionManager.tapAt(pos, label: target);
                filledCount++;
              }
            } else {
              final text = val.toString();
              bool entered = false;
              void findText(Element e) {
                if (entered) return;
                if (e is StatefulElement && e.state is EditableTextState) {
                  try {
                    final state = e.state as EditableTextState;
                    state.updateEditingValue(TextEditingValue(text: text));
                    entered = true;
                  } catch (_) {
                    try {
                      (e.state as dynamic).controller.text = text;
                      entered = true;
                    } catch (_) {}
                  }
                  if (entered && FlutterPilot._isRecording) {
                    FlutterPilot._recordAction('enterText', {'key': target, 'text': text});
                  }
                  return;
                }
                e.visitChildren(findText);
              }
              findText(element);
              if (entered) filledCount++;
            }
          }
        }

        bool submitted = false;
        if (submitWith != null && submitWith.isNotEmpty) {
          final submitElem = PilotWidgetInspector.findElement(submitWith);
          if (submitElem != null) {
            RenderObject? ro = submitElem.renderObject;
            if (ro is! RenderBox || !ro.hasSize || !ro.attached) {
              try {
                await Scrollable.ensureVisible(
                  submitElem,
                  duration: const Duration(milliseconds: 100),
                  alignment: 0.5,
                );
                await InteractionManager.pumpAndSettleAdaptive();
                ro = submitElem.renderObject;
              } catch (_) {}
            }
            if (ro is RenderBox && ro.hasSize && ro.attached) {
              final pos = ro.localToGlobal(ro.size.center(Offset.zero));
              if (FlutterPilot._isRecording) {
                FlutterPilot._recordAction('tapWidget', {'key': submitWith});
              }
              await InteractionManager.tapAt(pos, label: submitWith);
              submitted = true;
            }
          }
        }

        return ServiceExtensionResponse.result(
          json.encode({
            'status': 'success',
            'fieldsFilled': filledCount,
            'totalFields': fields.length,
            'submitted': submitted,
          }),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Form filling failed: $e',
        );
      }
    });

    // -- ext.flutterpilot.auditScreenHealth -----------------------------------
    registerExtension('ext.flutterpilot.auditScreenHealth', (
      method,
      parameters,
    ) async {
      final auditReport = UiHealthAuditor.audit();
      return ServiceExtensionResponse.result(
        json.encode(auditReport),
      );
    });

    // -- ext.flutterpilot.executeActionChain ----------------------------------
    registerExtension('ext.flutterpilot.executeActionChain', (
      method,
      parameters,
    ) async {
      final actionsJson = parameters['actions'];
      if (actionsJson == null) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Missing actions array',
        );
      }

      try {
        final decoded = json.decode(actionsJson);
        if (decoded is! List) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'actions must be a JSON array',
          );
        }

        int executedCount = 0;
        for (final item in decoded) {
          if (item is Map) {
            final action = item['action']?.toString();
            final target = item['target']?.toString() ?? item['key']?.toString();
            if (action == 'tap' && target != null) {
              final element = PilotWidgetInspector.findElement(target);
              if (element != null) {
                final ro = element.renderObject;
                if (ro is RenderBox && ro.hasSize) {
                  final pos = ro.localToGlobal(ro.size.center(Offset.zero));
                  await InteractionManager.tapAt(pos, label: target);
                  executedCount++;
                }
              }
            } else if (action == 'enterText' && target != null) {
              final text = item['text']?.toString() ?? '';
              final element = PilotWidgetInspector.findElement(target);
              if (element != null) {
                bool entered = false;
                void findText(Element e) {
                  if (entered) return;
                  if (e is StatefulElement && e.state is EditableTextState) {
                    try {
                      (e.state as EditableTextState).updateEditingValue(TextEditingValue(text: text));
                      entered = true;
                    } catch (_) {}
                    return;
                  }
                  e.visitChildren(findText);
                }
                findText(element);
                if (entered) executedCount++;
              }
            }
            await Future.delayed(const Duration(milliseconds: 50));
          }
        }

        return ServiceExtensionResponse.result(
          json.encode({'status': 'success', 'executedCount': executedCount, 'totalActions': decoded.length}),
        );
      } catch (e) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          'Action chain execution failed: $e',
        );
      }
    });

    // -- ext.flutterpilot.runChaosFuzzing -------------------------------------
    registerExtension('ext.flutterpilot.runChaosFuzzing', (
      method,
      parameters,
    ) async {
      final duration = int.tryParse(parameters['durationSeconds'] ?? '5') ?? 5;
      final rate = int.tryParse(parameters['eventRatePerSecond'] ?? '5') ?? 5;
      final report = await ChaosFuzzer.run(
        durationSeconds: duration,
        eventRatePerSecond: rate,
      );
      return ServiceExtensionResponse.result(json.encode(report));
    });

    // -- ext.flutterpilot.auditMemoryHealth ----------------------------------
    registerExtension('ext.flutterpilot.auditMemoryHealth', (
      method,
      parameters,
    ) async {
      final audit = MemoryAuditor.audit();
      return ServiceExtensionResponse.result(json.encode(audit));
    });
  }
}
