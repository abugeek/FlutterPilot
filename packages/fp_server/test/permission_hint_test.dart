import 'package:fp_server/src/permission_hint.dart';
import 'package:test/test.dart';

void main() {
  test('names the permission calls the app made, newest last', () {
    final hint = permissionCallsHint([
      {'channel': 'plugins.flutter.io/shared_preferences', 'method': 'getAll'},
      {
        'channel': 'flutter.baseflow.com/permissions/methods',
        'method': 'requestPermissions',
        'outcome': 'platform',
      },
      {
        'channel': 'flutter.baseflow.com/geolocator',
        'method': 'checkPermission',
        'outcome': 'mocked',
      },
    ])!;
    expect(
      hint,
      contains('flutter.baseflow.com/permissions/methods / requestPermissions'),
    );
    expect(hint, isNot(contains('shared_preferences')));
    expect(hint, isNot(contains('geolocator')), reason: 'already mocked');
    expect(hint, contains('mock_platform_channel'));
  });

  test('no permission call, no hint', () {
    expect(permissionCallsHint([]), isNull);
    expect(
      permissionCallsHint([
        {'channel': 'plugins.flutter.io/battery', 'method': 'level'},
      ]),
      isNull,
    );
  });
}
