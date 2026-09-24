import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Resolved keyboard key representation.
typedef _KeyDef = ({
  PhysicalKeyboardKey physical,
  LogicalKeyboardKey logical,
  String? character,
});

/// Simulates hardware keyboard events against the currently focused element.
///
/// Produces genuine [KeyEvent]s that flow through [HardwareKeyboard] and the
/// Flutter focus system. That lets `Focus.onKeyEvent`, `Shortcuts`/`Actions`,
/// focus traversal (Tab), and editing intents (arrows, Backspace, Enter)
/// all respond exactly as they would to a physical keyboard.
class KeyboardSimulator {
  KeyboardSimulator();

  int _timeStampMicros = 0;

  static const supportedKeyNames = [
    'enter',
    'tab',
    'backspace',
    'delete',
    'escape',
    'arrowup',
    'arrowdown',
    'arrowleft',
    'arrowright',
    'home',
    'end',
    'pageup',
    'pagedown',
    'space',
  ];

  static const _modifierKeys = <String, _KeyDef>{
    'control': (
      physical: PhysicalKeyboardKey.controlLeft,
      logical: LogicalKeyboardKey.controlLeft,
      character: null,
    ),
    'shift': (
      physical: PhysicalKeyboardKey.shiftLeft,
      logical: LogicalKeyboardKey.shiftLeft,
      character: null,
    ),
    'alt': (
      physical: PhysicalKeyboardKey.altLeft,
      logical: LogicalKeyboardKey.altLeft,
      character: null,
    ),
    'meta': (
      physical: PhysicalKeyboardKey.metaLeft,
      logical: LogicalKeyboardKey.metaLeft,
      character: null,
    ),
  };

  /// Presses [keyName] once (down then up), optionally with [modifiers] held.
  Future<void> pressKey(
    String keyName, {
    Set<String> modifiers = const {},
  }) async {
    final keyDef = _resolveKey(keyName);
    if (keyDef == null) {
      throw ArgumentError(
        'Unknown key "$keyName". Supported keys: '
        '${supportedKeyNames.join(', ')}, plus single characters a-z and 0-9.',
      );
    }

    final modifierDefs = <_KeyDef>[];
    var hasShift = false;
    var hasNonShiftModifier = false;
    for (final modifier in modifiers) {
      final normalized = modifier.toLowerCase().trim();
      if (normalized.isEmpty) continue;
      final def = _modifierKeys[normalized];
      if (def == null) {
        throw ArgumentError(
          'Unknown modifier "$modifier". Supported modifiers: '
          '${_modifierKeys.keys.join(', ')}.',
        );
      }
      modifierDefs.add(def);
      if (normalized == 'shift') {
        hasShift = true;
      } else {
        hasNonShiftModifier = true;
      }
    }

    String? character;
    if (!hasNonShiftModifier && keyDef.character != null) {
      character =
          hasShift ? keyDef.character!.toUpperCase() : keyDef.character;
    }

    for (final modifier in modifierDefs) {
      _dispatch(_downEvent(modifier, character: null));
    }
    _dispatch(_downEvent(keyDef, character: character));
    _dispatch(_upEvent(keyDef));
    for (final modifier in modifierDefs.reversed) {
      _dispatch(_upEvent(modifier));
    }

    _performTextInputActionForEnter(keyDef, modifiers);
    WidgetsBinding.instance.scheduleFrame();
  }

  KeyEvent _downEvent(_KeyDef def, {required String? character}) =>
      KeyDownEvent(
        physicalKey: def.physical,
        logicalKey: def.logical,
        character: character,
        timeStamp: Duration(microseconds: _timeStampMicros++),
      );

  KeyEvent _upEvent(_KeyDef def) => KeyUpEvent(
        physicalKey: def.physical,
        logicalKey: def.logical,
        timeStamp: Duration(microseconds: _timeStampMicros++),
      );

  void _dispatch(KeyEvent event) {
    HardwareKeyboard.instance.handleKeyEvent(event);
    // Route to focus manager
    // ignore: deprecated_member_use
    ServicesBinding.instance.keyEventManager.keyMessageHandler
        // ignore: deprecated_member_use
        ?.call(KeyMessage(<KeyEvent>[event], null));
  }

  void _performTextInputActionForEnter(_KeyDef keyDef, Set<String> modifiers) {
    if (keyDef.logical != LogicalKeyboardKey.enter || modifiers.isNotEmpty) {
      return;
    }

    final focusNode = FocusManager.instance.primaryFocus;
    final context = focusNode?.context;
    if (context == null) return;

    EditableTextState? editableTextState;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        editableTextState = element.state as EditableTextState;
        return false;
      }
      return true;
    });

    if (editableTextState == null) return;

    final widget = editableTextState!.widget;
    final action = widget.textInputAction ??
        (widget.keyboardType == TextInputType.multiline
            ? TextInputAction.newline
            : TextInputAction.done);

    editableTextState!.performAction(action);
  }

  _KeyDef? _resolveKey(String name) {
    final clean = name.toLowerCase().replaceAll('_', '').trim();
    if (clean.length == 1) {
      final codeUnit = clean.codeUnitAt(0);
      if (codeUnit >= 97 && codeUnit <= 122) {
        // a-z
        return (
          physical: PhysicalKeyboardKey.findKeyByCode(0x00070004 + (codeUnit - 97)) ??
              PhysicalKeyboardKey.keyA,
          logical: LogicalKeyboardKey(0x00000061 + (codeUnit - 97)),
          character: clean,
        );
      }
      if (codeUnit >= 48 && codeUnit <= 57) {
        // 0-9
        return (
          physical: PhysicalKeyboardKey.findKeyByCode(
                  codeUnit == 48 ? 0x00070027 : 0x0007001e + (codeUnit - 49)) ??
              PhysicalKeyboardKey.digit0,
          logical: LogicalKeyboardKey(0x00000030 + (codeUnit - 48)),
          character: clean,
        );
      }
      if (clean == ' ') {
        return (
          physical: PhysicalKeyboardKey.space,
          logical: LogicalKeyboardKey.space,
          character: ' ',
        );
      }
    }

    return switch (clean) {
      'enter' || 'return' => (
          physical: PhysicalKeyboardKey.enter,
          logical: LogicalKeyboardKey.enter,
          character: '\n',
        ),
      'tab' => (
          physical: PhysicalKeyboardKey.tab,
          logical: LogicalKeyboardKey.tab,
          character: '\t',
        ),
      'backspace' => (
          physical: PhysicalKeyboardKey.backspace,
          logical: LogicalKeyboardKey.backspace,
          character: null,
        ),
      'delete' => (
          physical: PhysicalKeyboardKey.delete,
          logical: LogicalKeyboardKey.delete,
          character: null,
        ),
      'escape' || 'esc' => (
          physical: PhysicalKeyboardKey.escape,
          logical: LogicalKeyboardKey.escape,
          character: null,
        ),
      'arrowup' || 'up' => (
          physical: PhysicalKeyboardKey.arrowUp,
          logical: LogicalKeyboardKey.arrowUp,
          character: null,
        ),
      'arrowdown' || 'down' => (
          physical: PhysicalKeyboardKey.arrowDown,
          logical: LogicalKeyboardKey.arrowDown,
          character: null,
        ),
      'arrowleft' || 'left' => (
          physical: PhysicalKeyboardKey.arrowLeft,
          logical: LogicalKeyboardKey.arrowLeft,
          character: null,
        ),
      'arrowright' || 'right' => (
          physical: PhysicalKeyboardKey.arrowRight,
          logical: LogicalKeyboardKey.arrowRight,
          character: null,
        ),
      'home' => (
          physical: PhysicalKeyboardKey.home,
          logical: LogicalKeyboardKey.home,
          character: null,
        ),
      'end' => (
          physical: PhysicalKeyboardKey.end,
          logical: LogicalKeyboardKey.end,
          character: null,
        ),
      'pageup' => (
          physical: PhysicalKeyboardKey.pageUp,
          logical: LogicalKeyboardKey.pageUp,
          character: null,
        ),
      'pagedown' => (
          physical: PhysicalKeyboardKey.pageDown,
          logical: LogicalKeyboardKey.pageDown,
          character: null,
        ),
      'space' => (
          physical: PhysicalKeyboardKey.space,
          logical: LogicalKeyboardKey.space,
          character: ' ',
        ),
      _ => null,
    };
  }
}
