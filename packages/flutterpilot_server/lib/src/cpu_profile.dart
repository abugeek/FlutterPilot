/// CPU profile of one action (ROADMAP §5.2): which code the UI isolate ran
/// while an agent's tap/scroll/text entry was handled, attributed to the
/// app's own functions with file:line.
library;

import 'package:vm_service/vm_service.dart';

/// Whose code a frame belongs to.
enum CodeOwner { app, flutterpilot, other }

/// Tells app code from FlutterPilot's and everything else by resolved URL.
///
/// The VM reports path dependencies and the Flutter SDK as file paths, not
/// `package:` URIs, so paths are mapped back to packages with the app's
/// `package_config.json` ([packageLibs]).
class CodeClassifier {
  CodeClassifier({
    required this.appPackages,
    this.appRoot,
    Map<String, String> packageLibs = const {},
  }) : _libs = (packageLibs.entries.toList()
         ..sort((a, b) => b.key.length.compareTo(a.key.length)));

  /// Reads `.dart_tool/package_config.json` [json] found at [configUri].
  factory CodeClassifier.fromPackageConfig({
    required Set<String> appPackages,
    String? appRoot,
    required Map<String, dynamic> json,
    required Uri configUri,
  }) {
    final libs = <String, String>{};
    for (final p in (json['packages'] as List? ?? const []).whereType<Map>()) {
      final name = p['name']?.toString();
      final rootUri = p['rootUri']?.toString();
      if (name == null || rootUri == null) continue;
      var root = configUri.resolve(rootUri);
      if (!root.path.endsWith('/')) root = root.replace(path: '${root.path}/');
      final lib = root.resolve(p['packageUri']?.toString() ?? 'lib/').path;
      libs[lib.endsWith('/') ? lib : '$lib/'] = name;
    }
    return CodeClassifier(
      appPackages: appPackages,
      appRoot: appRoot,
      packageLibs: libs,
    );
  }

  /// `package:` names of the app (from its pubspec / root library).
  final Set<String> appPackages;

  /// The app's directory, for `file:` URLs of its libraries.
  final String? appRoot;

  /// Package `lib/` directories (ending in `/`) -> package name, longest
  /// first.
  final List<MapEntry<String, String>> _libs;

  /// `package:name/rest` for [url], or null outside any package.
  String? packageUri(String url) {
    if (url.startsWith('package:')) return url;
    final path = url.startsWith('file://')
        ? Uri.parse(url).path
        : url.startsWith('/')
        ? url
        : null;
    if (path == null) return null;
    for (final MapEntry(key: lib, value: name) in _libs) {
      if (path.startsWith(lib)) {
        return 'package:$name/${path.substring(lib.length)}';
      }
    }
    return null;
  }

  CodeOwner ownerOf(String? url) {
    if (url == null || url.isEmpty) return CodeOwner.other;
    final package = packageUri(url);
    if (package != null) {
      final name = package.substring(8).split('/').first;
      if (name.startsWith('flutterpilot')) return CodeOwner.flutterpilot;
      if (appPackages.contains(name)) return CodeOwner.app;
      return CodeOwner.other;
    }
    final root = appRoot;
    if (root != null && (url.startsWith('file://') || url.startsWith('/'))) {
      final path = url.startsWith('/') ? url : Uri.parse(url).path;
      if (path.startsWith('$root/') &&
          !path.contains('/.dart_tool/') &&
          !path.contains('/.pub-cache/')) {
        return CodeOwner.app;
      }
    }
    return CodeOwner.other;
  }

  /// Short form: `lib/ui/tile.dart` for the app, `package:flutter/...`
  /// for packages, `dart:core/...`-style for the SDK.
  String display(String url) {
    final package = packageUri(url);
    if (package != null) {
      return ownerOf(url) == CodeOwner.app
          ? 'lib/${package.substring(package.indexOf('/') + 1)}'
          : package;
    }
    final root = appRoot;
    final path = url.startsWith('file://') ? Uri.parse(url).path : url;
    if (root != null && path.startsWith('$root/')) {
      return path.substring(root.length + 1);
    }
    // org-dartlang-sdk:///flutter/third_party/dart/sdk/lib/_internal/vm/lib/x.dart
    final sdk = path.indexOf('/sdk/lib/');
    if (url.startsWith('org-dartlang-sdk:') && sdk >= 0) {
      return 'dart:${path.substring(sdk + 9)}';
    }
    // org-dartlang-sdk:///flutter/lib/ui/text.dart
    final ui = path.indexOf('/lib/ui/');
    if (url.startsWith('org-dartlang-sdk:') && ui >= 0) {
      return 'dart:ui/${path.substring(ui + 8)}';
    }
    return path;
  }
}

/// A function's share of the profiled samples.
class FunctionCost {
  FunctionCost(this.index, this.name, this.url);

  /// Index into [CpuSamples.functions].
  final int index;
  final String name;
  final String? url;

  /// Samples where it was on top of the stack (self time).
  int self = 0;

  /// Samples where it was anywhere on the stack (total time).
  int total = 0;

  /// For framework functions: the app function nearest below it on the
  /// stack, per sample — who in the app caused this work.
  final Map<int, int> appCallers = {};

  int? get topAppCaller {
    if (appCallers.isEmpty) return null;
    return (appCallers.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .first
        .key;
  }
}

/// The samples of one profiled window, attributed by [CodeClassifier].
class ActionProfile {
  ActionProfile._(this.samplePeriodMicros, this.functions);

  final int samplePeriodMicros;
  final List<FunctionCost> functions;

  /// Samples running Dart code, split by whose code was nearest the top.
  int dartSamples = 0;
  int appSamples = 0;
  int flutterpilotSamples = 0;

  /// Samples with no Dart frame (GC, VM or engine work on this thread).
  int nativeSamples = 0;

  double ms(int samples) => samples * samplePeriodMicros / 1000;

  /// Samples whose work FlutterPilot itself started (reading the screen
  /// after the action) are left out of every function's cost.
  static ActionProfile analyze(CpuSamples cpu, CodeClassifier classifier) {
    final fns = cpu.functions ?? const <ProfileFunction>[];
    final costs = [
      for (var i = 0; i < fns.length; i++)
        FunctionCost(i, functionName(fns[i].function), fns[i].resolvedUrl),
    ];
    final owners = [for (final f in fns) classifier.ownerOf(f.resolvedUrl)];
    final isDart = [for (final f in fns) f.kind == 'Dart'];
    final profile = ActionProfile._(cpu.samplePeriod ?? 1000, costs);

    for (final sample in cpu.samples ?? const <CpuSample>[]) {
      final stack = sample.stack ?? const <int>[];
      final dart = [
        for (final i in stack)
          if (i >= 0 && i < fns.length && isDart[i]) i,
      ];
      if (dart.isEmpty) {
        profile.nativeSamples++;
        continue;
      }
      // Nearest owner from the top: a tree walk FlutterPilot runs inside
      // framework code is FlutterPilot's; an app tap handler FlutterPilot's
      // synthetic pointer event reached is the app's.
      final owner = dart
          .map((i) => owners[i])
          .firstWhere(
            (o) => o != CodeOwner.other,
            orElse: () => CodeOwner.other,
          );
      if (owner == CodeOwner.flutterpilot) {
        profile.flutterpilotSamples++;
        continue;
      }
      profile.dartSamples++;
      if (owner == CodeOwner.app) profile.appSamples++;
      costs[dart.first].self++;
      final nearestApp = dart.firstWhere(
        (i) => owners[i] == CodeOwner.app,
        orElse: () => -1,
      );
      if (nearestApp >= 0 && owners[dart.first] != CodeOwner.app) {
        final top = costs[dart.first];
        top.appCallers[nearestApp] = (top.appCallers[nearestApp] ?? 0) + 1;
      }
      for (final i in dart.toSet()) {
        costs[i].total++;
      }
    }
    return profile;
  }

  /// App functions by self time, then total time.
  List<FunctionCost> topApp(CodeClassifier classifier, {int limit = 8}) =>
      (functions
              .where(
                (f) =>
                    f.total > 0 && classifier.ownerOf(f.url) == CodeOwner.app,
              )
              .toList()
            ..sort(
              (a, b) => b.self != a.self
                  ? b.self.compareTo(a.self)
                  : b.total.compareTo(a.total),
            ))
          .take(limit)
          .toList();

  /// Any function by self time.
  List<FunctionCost> topSelf({int limit = 6}) =>
      (functions.where((f) => f.self > 0).toList()
            ..sort((a, b) => b.self.compareTo(a.self)))
          .take(limit)
          .toList();
}

/// `StoryTile.build`, `FeedScreen.build.<anonymous closure>`, `main`.
String functionName(Object? function) {
  if (function is FuncRef) {
    final name = function.name ?? '?';
    final owner = function.owner;
    if (owner is ClassRef) return '${owner.name}.$name';
    if (owner is FuncRef) return '${functionName(owner)}.$name';
    return name;
  }
  if (function is NativeFunction) return function.name ?? '[native]';
  if (function is Map) return '${function['name'] ?? '?'}';
  try {
    final name = (function as dynamic).name;
    if (name is String) return name;
  } catch (_) {}
  return '?';
}
