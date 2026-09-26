import 'dart:async';

import 'package:vm_service/vm_service.dart';

import 'operation_scheduler.dart';

/// Runtime-owned state for one Flutter VM-service connection.
///
/// Keeping this state together is important: an isolate cache, scheduler, and
/// reconnect generation must never be shared between two devices.
class DeviceRuntimeContext {
  DeviceRuntimeContext({required this.deviceId, required this.uri});

  final String deviceId;
  String uri;
  final OperationScheduler scheduler = OperationScheduler();
  VmService? service;
  String? cachedMainIsolateId;
  int connectionGeneration = 0;
  StreamSubscription<Event>? extensionEvents;
  StreamSubscription<Event>? loggingEvents;
  StreamSubscription<Event>? stdoutEvents;
  StreamSubscription<Event>? serviceEvents;

  /// Services registered on the VM service by `flutter run` (or an IDE debug
  /// session), e.g. `reloadSources` -> `s0.reloadSources`. Real hot reload and
  /// hot restart must go through these: only flutter_tools can recompile the
  /// edited sources.
  final Map<String, String> registeredServices = {};

  bool get connected => service != null;

  Future<void> dispose() async {
    await extensionEvents?.cancel();
    await loggingEvents?.cancel();
    await stdoutEvents?.cancel();
    await serviceEvents?.cancel();
    extensionEvents = null;
    loggingEvents = null;
    stdoutEvents = null;
    serviceEvents = null;
    registeredServices.clear();
    await service?.dispose();
    service = null;
    cachedMainIsolateId = null;
    scheduler.reset();
  }
}
