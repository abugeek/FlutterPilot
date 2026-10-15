/// Whether the running app still runs the code on disk. In field sessions an
/// agent checked out a PR and tested it against an app still running main,
/// and others rebuilt the app when a hot reload would have loaded the edit.
library;

import 'dart:io';

import 'reload_failure.dart';

/// Files a hot reload or restart cannot load: a change means building the
/// app again. Relative to the app folder.
const relaunchFiles = [
  'pubspec.yaml',
  'pubspec.lock',
  'ios/Podfile.lock',
  'ios/Runner/Info.plist',
  'macos/Podfile.lock',
  'macos/Runner/Info.plist',
  'macos/Runner/DebugProfile.entitlements',
  'android/build.gradle',
  'android/build.gradle.kts',
  'android/app/build.gradle',
  'android/app/build.gradle.kts',
  'android/app/src/main/AndroidManifest.xml',
  'linux/CMakeLists.txt',
  'windows/CMakeLists.txt',
  'web/index.html',
];

/// What changed on disk since the app loaded it.
class CodeFreshness {
  const CodeFreshness({required this.dart, required this.relaunch});

  /// Dart files edited since the last hot reload, restart or launch.
  final List<String> dart;

  /// [relaunchFiles] changed since the app was built and started.
  final List<String> relaunch;

  bool get fresh => dart.isEmpty && relaunch.isEmpty;

  /// One line for the app summary, or null when the app runs what is on
  /// disk. [hotReload] is false for a profile build.
  String? note({required bool hotReload}) {
    if (relaunch.isNotEmpty) {
      return '${_list(relaunch)} changed since the app was built: a hot '
          'reload cannot load that. launch_app(relaunch: true) builds it '
          'again.';
    }
    if (dart.isEmpty) return null;
    final files =
        '${dart.length} Dart file${dart.length == 1 ? '' : 's'} '
        '(${_list(dart)}) edited since the app loaded its code';
    return hotReload
        ? '$files: the app is running the old code. hot_reload loads it '
              '(restart: true after a git checkout or for main()/initializers).'
        : '$files, and a profile build cannot hot reload: '
              'launch_app(relaunch: true) builds it again.';
  }

  static String _list(List<String> files) => files.length <= 3
      ? files.join(', ')
      : '${files.take(3).join(', ')}, +${files.length - 3}';
}

/// Compares [root] with a running app: Dart files newer than [codeLoaded]
/// (the last reload, restart or launch) and [relaunchFiles] newer than
/// [appStarted].
CodeFreshness codeFreshness(
  String root, {
  required DateTime codeLoaded,
  required DateTime appStarted,
}) {
  // With forward slashes, the way app files are named everywhere else in a
  // tool's answer: `Directory.list` gives `lib\ui\tile.dart` on Windows
  // (field test #341).
  String relative(String path) {
    final posix = path.replaceAll(r'\', '/');
    final prefix = '${root.replaceAll(r'\', '/')}/';
    return posix.startsWith(prefix) ? posix.substring(prefix.length) : posix;
  }

  // The build itself writes files a moment before the app starts.
  final builtBy = appStarted.add(const Duration(seconds: 2));
  final relaunch = <String>[];
  for (final name in relaunchFiles) {
    try {
      final file = File('$root/$name');
      if (file.existsSync() && file.lastModifiedSync().isAfter(builtBy)) {
        relaunch.add(name);
      }
    } catch (_) {}
  }
  return CodeFreshness(
    dart: [
      for (final path in dartFilesChangedSince(
        root,
        codeLoaded.add(const Duration(seconds: 1)),
      ))
        relative(path),
    ],
    relaunch: relaunch,
  );
}
