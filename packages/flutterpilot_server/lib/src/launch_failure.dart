/// What a failed `flutter run` on a phone usually means, from the end of its
/// output, so the agent gets the fix instead of "Could not build the
/// precompiled application".
String? explainLaunchFailure(String log) {
  final text = log.toLowerCase();
  final hints = <String>[
    if (text.contains('could not code sign') ||
        text.contains('no development team') ||
        text.contains('requires a development team') ||
        text.contains('no profiles for') ||
        text.contains('signing for "runner" requires') ||
        text.contains('no xcode build settings have been found'))
      'On a real iPhone this is usually iOS signing (or the phone being '
          'locked). Open '
          'ios/Runner.xcworkspace once and pick a Team under Signing & '
          'Capabilities, or set FLUTTER_XCODE_DEVELOPMENT_TEAM=<team id> in '
          'flutterpilot/launch.json: {"command": ["env", '
          '"FLUTTER_XCODE_DEVELOPMENT_TEAM=<team id>", "flutter", "run", '
          '"-d", "<device>"]}.',
    if (text.contains('needs to be unlocked') ||
        text.contains('device is locked') ||
        text.contains('is locked'))
      'The iPhone is locked: unlock it (and keep it unlocked while the app '
          'installs and starts).',
    if (text.contains('developer mode'))
      'Developer Mode is off on the iPhone: Settings → Privacy & Security → '
          'Developer Mode, then restart it.',
    if (text.contains('untrusted developer') ||
        text.contains('profile has not been explicitly trusted'))
      'Trust the developer profile on the iPhone: Settings → General → VPN & '
          'Device Management.',
    if (text.contains('unauthorized') && text.contains('adb'))
      'The Android phone has not authorized this Mac: unlock it and accept '
          '"Allow USB debugging".',
    if (text.contains('install_failed_user_restricted') ||
        text.contains('install canceled by user'))
      'The phone refused the install: allow "Install via USB" in the '
          'developer options (some Xiaomi/Oppo/Vivo phones ask on screen).',
    if (text.contains('insufficient_storage') ||
        text.contains('install_failed_insufficient_storage'))
      'The phone is out of storage: free some space.',
  ];
  return hints.isEmpty ? null : hints.join('\n');
}
