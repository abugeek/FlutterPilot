import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'restart_store_stub.dart'
    if (dart.library.io) 'restart_store_io.dart'
    as store;

/// Data the server leaves for the app across a hot restart (which clears
/// every Dart variable): a scenario's mocked responses must be in place
/// before the app's first requests (ROADMAP §7). Kept in a file named after
/// the process in the system temp folder; read once, then deleted.
class RestartStore {
  static Map<String, dynamic>? _data;

  static void save(Map<String, dynamic> data) => store.write(json.encode(data));

  /// The value the server left under [key] before the last hot restart,
  /// once.
  static Object? take(String key) {
    load();
    return _data!.remove(key);
  }

  /// As after a restart: the next [take] reads the file.
  @visibleForTesting
  static void debugReset() => _data = null;

  /// Reads (and deletes) the file now: at startup, so it never lingers.
  static void load() {
    if (_data == null) {
      final raw = store.readAndDelete();
      try {
        _data = raw == null
            ? {}
            : (json.decode(raw) as Map).cast<String, dynamic>();
      } catch (_) {
        _data = {};
      }
    }
  }
}
