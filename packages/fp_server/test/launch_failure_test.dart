import 'package:fp_server/src/launch_failure.dart';
import 'package:test/test.dart';

void main() {
  test('signing, locked, developer mode, authorization', () {
    expect(
      explainLaunchFailure('Error: could not code sign the application.'),
      contains('FLUTTER_XCODE_DEVELOPMENT_TEAM'),
    );
    expect(
      explainLaunchFailure('No Xcode build settings have been found.'),
      contains('FLUTTER_XCODE_DEVELOPMENT_TEAM'),
    );
    expect(
      explainLaunchFailure('iPhone needs to be unlocked to enable development'),
      contains('iPhone is locked'),
    );
    expect(
      explainLaunchFailure(
        'Error (Xcode): No Accounts: Add a new account in Accounts settings.',
      ),
      contains('Apple ID'),
    );
    expect(
      explainLaunchFailure('Developer Mode is disabled'),
      contains('Developer Mode'),
    );
    expect(
      explainLaunchFailure('adb: device unauthorized'),
      contains('Allow USB debugging'),
    );
    expect(
      explainLaunchFailure('INSTALL_FAILED_USER_RESTRICTED'),
      contains('Install via USB'),
    );
  });

  test('an unknown failure has no hint', () {
    expect(explainLaunchFailure('Gradle task assembleDebug failed'), isNull);
  });
}
