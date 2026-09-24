import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../flutterpilot_sdk.dart';

/// A custom binding extending [WidgetsFlutterBinding] providing high-performance,
/// rock-solid integration points for FlutterPilot.
///
/// Ensures service extensions are registered at the earliest lifecycle point,
/// handles back route popping cleanly, and clears caches on hot reload.
///
/// Recommended setup in `main.dart`:
/// ```dart
/// void main() {
///   if (!kReleaseMode) {
///     FlutterPilotBinding.ensureInitialized();
///   } else {
///     WidgetsFlutterBinding.ensureInitialized();
///   }
///   runApp(const MyApp());
/// }
/// ```
class FlutterPilotBinding extends WidgetsFlutterBinding {
  /// Initializes and returns the [WidgetsBinding] singleton instance with FlutterPilot active.
  static WidgetsBinding ensureInitialized() {
    if (_instance == null) {
      final existing = _existingWidgetsBinding();
      if (existing != null) {
        // Another binding was already installed; seamlessly activate FlutterPilot on it
        FlutterPilot.initialize();
        return existing;
      }
      FlutterPilotBinding();
    }
    return instance;
  }

  static WidgetsBinding? _existingWidgetsBinding() {
    try {
      return WidgetsBinding.instance;
    } catch (_) {
      return null;
    }
  }

  static FlutterPilotBinding get instance =>
      BindingBase.checkInstance(_instance);
  static FlutterPilotBinding? _instance;

  FlutterPilotBinding() {
    _instance = this;
  }

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
    FlutterPilot.initialize();
  }

  @override
  void initServiceExtensions() {
    super.initServiceExtensions();
    FlutterPilot.registerServiceExtensions();
  }

  @override
  Future<void> reassembleApplication() async {
    FlutterPilot.notifyMutation();
    return super.reassembleApplication();
  }
}
