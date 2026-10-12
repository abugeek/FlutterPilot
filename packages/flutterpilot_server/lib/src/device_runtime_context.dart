import 'build_mode.dart';
import 'dart:async';

import 'package:vm_service/vm_service.dart';

import 'operation_scheduler.dart';
import 'screen_memory.dart';

/// Runtime-owned state for one Flutter VM-service connection.
///
/// Keeping this state together is important: an isolate cache, scheduler, and
/// reconnect generation must never be shared between two devices.
class DeviceRuntimeContext {
  DeviceRuntimeContext({required this.deviceId, required this.uri});

  String deviceId;
  String uri;
  final OperationScheduler scheduler = OperationScheduler();
  VmService? service;
  String? cachedMainIsolateId;
  int connectionGeneration = 0;
  StreamSubscription<Event>? extensionEvents;
  StreamSubscription<Event>? loggingEvents;
  StreamSubscription<Event>? stdoutEvents;
  StreamSubscription<Event>? serviceEvents;
  StreamSubscription<Event>? isolateEvents;
  StreamSubscription<Event>? debugEvents;

  /// Services registered on the VM service by `flutter run` (or an IDE debug
  /// session), e.g. `reloadSources` -> `s0.reloadSources`. Real hot reload and
  /// hot restart must go through these: only flutter_tools can recompile the
  /// edited sources.
  final Map<String, String> registeredServices = {};

  /// Whether the app registers FlutterPilot's SDK extensions; null until the
  /// connection has been checked. Without the SDK the server answers what it
  /// can from Flutter's own inspector extensions ("zero-code mode").
  bool? hasSdk;

  /// The app SDK's protocol number (sdk_protocol.dart); 1 for an SDK from
  /// before it had one. Null until checked, or without the SDK.
  int? sdkProtocol;

  /// Framework errors (`Flutter.Error` events) seen while [hasSdk] is false;
  /// with the SDK installed it reports errors itself.
  final List<Map<String, dynamic>> zeroCodeErrors = [];

  /// The isolate a Debug event said is stopped in a debugger; checked
  /// against the VM before a call is refused for it.
  String? pausedIsolateId;

  /// What the last action response listed as tappable on this device.
  final ScreenMemory screenMemory = ScreenMemory();

  /// The VM's `operatingSystem` (`ios`, `android`, `macos`, ...).
  String? operatingSystem;

  /// The VM's `targetCPU` (`Web`, `x64`, `arm64`, ...).
  String? targetCPU;

  /// Whether this connection targets a web app (DWDS / browser).
  bool get isWeb => targetCPU == 'Web' || operatingSystem == 'web';

  /// Debug or profile: what hot reload, source locations and timings can be
  /// trusted to do. Null until connected.
  BuildMode? buildMode;

  /// When the last hot reload or restart succeeded: files edited since are
  /// what a failed one is about.
  DateTime? lastReload;

  /// The app's last reported `AppLifecycleState` name (SDK apps only).
  String? lifecycle;

  bool get connected => service != null;

  Future<void> dispose() async {
    await extensionEvents?.cancel();
    await loggingEvents?.cancel();
    await stdoutEvents?.cancel();
    await serviceEvents?.cancel();
    await isolateEvents?.cancel();
    await debugEvents?.cancel();
    extensionEvents = null;
    loggingEvents = null;
    stdoutEvents = null;
    serviceEvents = null;
    isolateEvents = null;
    debugEvents = null;
    registeredServices.clear();
    hasSdk = null;
    sdkProtocol = null;
    zeroCodeErrors.clear();
    screenMemory.reset();
    pausedIsolateId = null;
    lifecycle = null;
    lastReload = null;
    await service?.dispose();
    service = null;
    cachedMainIsolateId = null;
    scheduler.reset();
  }
}
