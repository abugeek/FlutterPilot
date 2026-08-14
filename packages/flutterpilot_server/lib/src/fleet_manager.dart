import 'dart:convert';

/// Manages multiple running Flutter instances across devices (iOS, Android, Web).
class FleetManager {
  final Map<String, String> _devices = {};
  String? _activeDeviceId;

  /// Registers or updates a device with its VM Service URI.
  void registerDevice(String name, String uri) {
    _devices[name] = uri;
    _activeDeviceId ??= name;
  }

  /// Sets the currently active device.
  bool switchDevice(String name) {
    if (_devices.containsKey(name)) {
      _activeDeviceId = name;
      return true;
    }
    return false;
  }

  /// Returns the VM Service URI of the active device.
  String? get activeUri =>
      _activeDeviceId != null ? _devices[_activeDeviceId] : null;

  /// Returns the ID/name of the currently active device.
  String? get activeDeviceId => _activeDeviceId;

  /// Returns the registered VM-service URI for [name], if present.
  String? uriFor(String name) => _devices[name];

  /// Lists all registered devices and the active status.
  Map<String, dynamic> listDevices() {
    return {
      'activeDevice': _activeDeviceId,
      'devices': _devices.entries
          .map(
            (e) => {
              'id': e.key,
              'uri': e.value,
              'isActive': e.key == _activeDeviceId,
            },
          )
          .toList(),
      'total': _devices.length,
    };
  }

  /// Serializes device list to formatted JSON.
  String toJsonString() => jsonEncode(listDevices());
}
