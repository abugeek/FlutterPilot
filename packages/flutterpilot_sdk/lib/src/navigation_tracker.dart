import 'package:flutter/widgets.dart';

/// Manages navigation state and route tracking for FlutterPilot.
class NavigationTracker extends NavigatorObserver {
  static final List<String?> _stack = [];
  
  /// Callback for logging state changes to the central FlutterPilot system.
  static void Function(String source, String name, dynamic value)? onStateChange;

  /// Retrieves the current navigation stack.
  static List<String?> get stack => List.unmodifiable(_stack);

  /// Retrieves the current route name.
  static String get currentRoute => _stack.isNotEmpty ? (_stack.last ?? 'Unknown') : 'Unknown';

  /// Resets the navigation stack. Used for testing and re-initialization.
  static void reset() {
    _stack.clear();
    onStateChange = null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _stack.add(route.settings.name);
    onStateChange?.call('navigation', 'push', route.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_stack.isNotEmpty) _stack.removeLast();
    onStateChange?.call('navigation', 'pop', route.settings.name);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    // Use lastIndexOf to remove the correct occurrence when duplicate names exist
    final index = _stack.lastIndexOf(route.settings.name);
    if (index != -1) _stack.removeAt(index);
    onStateChange?.call('navigation', 'remove', route.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final index = _stack.lastIndexOf(oldRoute?.settings.name);
    if (index != -1) {
      _stack[index] = newRoute?.settings.name;
    }
    onStateChange?.call('navigation', 'replace', newRoute?.settings.name);
  }
}
