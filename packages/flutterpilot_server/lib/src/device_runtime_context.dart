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

  bool get connected => service != null;

  Future<void> dispose() async {
    await extensionEvents?.cancel();
    await loggingEvents?.cancel();
    await stdoutEvents?.cancel();
    extensionEvents = null;
    loggingEvents = null;
    stdoutEvents = null;
    await service?.dispose();
    service = null;
    cachedMainIsolateId = null;
  }
}
