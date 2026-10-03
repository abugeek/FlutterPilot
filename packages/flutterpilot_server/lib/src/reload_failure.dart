/// What hot_reload / hot restart tells the agent when flutter_tools fails:
/// the error without flutter_tools' own stack frames, and a hint for the
/// cause that can be told from the message.
String reloadFailureText(String service, String details) {
  final message = details
      .split('\n')
      .where((line) => !_toolFrame.hasMatch(line))
      .where((line) => line.trim() != '<asynchronous suspension>')
      .join('\n')
      .trim();
  return '$service failed: $message\n${_hintFor(message)}';
}

/// A frame of flutter_tools' stack trace: `#12  HotRunner._updateDevFS (…)`.
final _toolFrame = RegExp(r'^\s*#\d+\s');

String _hintFor(String message) {
  // flutter_tools copies the compiled kernel straight into the app's temp
  // directory. For a sandboxed macOS app that is inside the app's container,
  // which macOS keeps other processes out of unless the one that ran
  // `flutter run` was allowed to manage apps.
  if (message.contains('failed to create file') &&
      message.contains('/Library/Containers/')) {
    return 'HINT: not a compile error. macOS stopped the process that ran '
        '`flutter run` from writing into this sandboxed app\'s container. '
        'Allow that program (the terminal, IDE or agent app) under System '
        'Settings > Privacy & Security > App Management (or Full Disk '
        'Access), then start `flutter run` again. Until then, stop the app '
        'and launch it again after each edit.';
  }
  return 'HINT: usually a compile error — run `dart analyze` on the edited '
      'files, fix, and retry. Some changes (main(), static initializers) '
      'need hot_reload(restart: true).';
}
