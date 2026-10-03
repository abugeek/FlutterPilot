import 'dart:io';

/// `"390x844"` (also `390×844`, `390 x 844`) as logical pixels, or null.
({int width, int height})? parseWindowSize(String value) {
  final match = RegExp(
    r'^\s*(\d{2,5})\s*[xX×]\s*(\d{2,5})\s*$',
  ).firstMatch(value);
  if (match == null) return null;
  return (width: int.parse(match[1]!), height: int.parse(match[2]!));
}

/// The AppleScript that resizes the first window of process [pid].
String macWindowScript(int pid, int width, int height) =>
    'tell application "System Events" to tell '
    '(first process whose unix id is $pid) to set size of window 1 to '
    '{$width, $height}';

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Resizes the app's window on the host (macOS desktop apps only): a
/// Flutter app cannot resize its own window without a plugin, and a layout
/// is only tested at the widths it is actually given.
///
/// Returns null on success, else why it could not be done.
Future<String?> resizeAppWindow({
  required String? operatingSystem,
  required int? pid,
  required int width,
  required int height,
  ProcessRunner run = Process.run,
}) async {
  if (operatingSystem != 'macos') {
    return 'the window can be resized on macOS desktop apps only '
        '(this app runs on ${operatingSystem ?? 'an unknown platform'}).';
  }
  if (pid == null) return 'the app\'s process id is unknown.';
  final ProcessResult result;
  try {
    result = await run('osascript', [
      '-e',
      macWindowScript(pid, width, height),
    ]);
  } on ProcessException catch (e) {
    return 'osascript could not be run: ${e.message}';
  }
  if (result.exitCode == 0) return null;
  final error = '${result.stderr}'.trim();
  // -1719 / -25211: the controlling program may not drive other apps.
  if (error.contains('assistive') ||
      error.contains('-1719') ||
      error.contains('-25211') ||
      error.contains('not allowed')) {
    return 'macOS did not allow it: give the program that runs this server '
        '(the terminal, IDE or agent app) Accessibility access under System '
        'Settings > Privacy & Security > Accessibility. ($error)';
  }
  return error.isEmpty ? 'osascript exited with ${result.exitCode}.' : error;
}
