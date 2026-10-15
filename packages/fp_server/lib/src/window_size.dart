import 'dart:io';

/// `"390x844"` (also `390×844`, `390 x 844`) as logical pixels, or null.
({int width, int height})? parseWindowSize(String value) {
  final match = RegExp(
    r'^\s*(\d{2,5})\s*[xX×]\s*(\d{2,5})\s*$',
  ).firstMatch(value);
  if (match == null) return null;
  return (width: int.parse(match[1]!), height: int.parse(match[2]!));
}

// Not `window 1`: a system alert or dialog of the app can be in front.
const _appWindow = '(first window whose subrole is "AXStandardWindow")';

/// The AppleScript that resizes the app window of process [pid].
String macWindowScript(int pid, int width, int height) =>
    'tell application "System Events" to tell '
    '(first process whose unix id is $pid) to set size of $_appWindow to '
    '{$width, $height}';

/// The AppleScript that reads the size of the app window of process [pid].
String macWindowSizeScript(int pid) =>
    'tell application "System Events" to tell '
    '(first process whose unix id is $pid) to get size of $_appWindow';

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// The PowerShell that gives the window of process [pid] a client area (the
/// app's viewport) of [width] x [height] logical pixels. A maximised or
/// minimised window is restored first: it has no size of its own to change.
String windowsWindowScript(int pid, int width, int height) =>
    r'''
$ErrorActionPreference = 'Stop'
Add-Type -Name Win -Namespace FlutterPilot -MemberDefinition '
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }'
$w = [FlutterPilot.Win]
$h = (Get-Process -Id PID).MainWindowHandle
if ($h -eq [IntPtr]::Zero) { [Console]::Error.WriteLine('no window'); exit 2 }
if ($w::IsZoomed($h) -or $w::IsIconic($h)) { [void]$w::ShowWindow($h, 9) }
$d = $w::GetDpiForWindow($h) / 96.0
$o = New-Object 'FlutterPilot.Win+RECT'; $c = New-Object 'FlutterPilot.Win+RECT'
[void]$w::GetWindowRect($h, [ref]$o); [void]$w::GetClientRect($h, [ref]$c)
$cx = [int][Math]::Round(WIDTH * $d) + ($o.R - $o.L) - $c.R
$cy = [int][Math]::Round(HEIGHT * $d) + ($o.B - $o.T) - $c.B
[void]$w::SetWindowPos($h, [IntPtr]::Zero, 0, 0, $cx, $cy, 0x0016)
'''
        .replaceAll('PID', '$pid')
        .replaceAll('WIDTH', '$width')
        .replaceAll('HEIGHT', '$height');

/// Resizes the app's window on the host (macOS and Windows desktop apps): a
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
  if (operatingSystem != 'macos' && operatingSystem != 'windows') {
    return 'the window can be resized on macOS and Windows desktop apps '
        'only (this app runs on '
        '${operatingSystem ?? 'an unknown platform'}).';
  }
  if (pid == null) return 'the app\'s process id is unknown.';
  if (operatingSystem == 'windows') {
    final ProcessResult result;
    try {
      result = await run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        windowsWindowScript(pid, width, height),
      ]);
    } on ProcessException catch (e) {
      return 'powershell could not be run: ${e.message}';
    }
    if (result.exitCode == 0) return null;
    final error = '${result.stderr}'.trim();
    return error.contains('no window')
        ? 'the app has no window (it runs hidden, or has not shown one yet).'
        : error.isEmpty
        ? 'powershell exited with ${result.exitCode}.'
        : error.split('\n').first.trim();
  }
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

/// The size macOS reports for the app's window (`"700x600"`), or null when
/// it cannot be read.
Future<String?> readAppWindowSize(
  int pid, {
  ProcessRunner run = Process.run,
}) async {
  try {
    final result = await run('osascript', ['-e', macWindowSizeScript(pid)]);
    if (result.exitCode != 0) return null;
    final size = RegExp(r'(\d+),\s*(\d+)').firstMatch('${result.stdout}');
    return size == null ? null : '${size[1]}x${size[2]}';
  } on ProcessException {
    return null;
  }
}
