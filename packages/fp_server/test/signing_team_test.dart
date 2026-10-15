import 'dart:io';

import 'package:fp_server/src/signing_team.dart';
import 'package:test/test.dart';

void main() {
  test('team from an openssl subject', () {
    expect(
      teamFromCertificateSubject(
        'subject= /UID=X/CN=Apple Development: a@b.c (K1)/OU=JVSN9NMGVQ/O=A B/C=US',
      ),
      'JVSN9NMGVQ',
    );
    expect(teamFromCertificateSubject('subject=CN=x'), isNull);
  });

  test('real iPhones are told from simulators', () {
    expect(isPhysicalIosDeviceId('00008130-001210260C04001C'), isTrue);
    expect(
      isPhysicalIosDeviceId('A19686F7-499C-45BD-B6B0-45E3F0F2EB84'),
      isFalse,
    );
    expect(isPhysicalIosDeviceId('macos'), isFalse);
  });

  test('a project that names a team keeps it; the environment wins', () async {
    final dir = Directory.systemTemp.createTempSync('fp_team');
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(projectHasTeam(dir), isFalse);
    final proj = Directory('${dir.path}/ios/Runner.xcodeproj')
      ..createSync(recursive: true);
    File(
      '${proj.path}/project.pbxproj',
    ).writeAsStringSync('DEVELOPMENT_TEAM = ABCDE12345;');
    expect(projectHasTeam(dir), isTrue);
    const phone = '00008130-001210260C04001C';
    expect(await signingTeamFor(dir, device: phone), isNull);
    expect(await signingTeamFor(dir, device: 'macos'), isNull);
    File('${proj.path}/project.pbxproj').writeAsStringSync('');
    expect(
      await signingTeamFor(
        dir,
        device: phone,
        environment: {'FLUTTER_XCODE_DEVELOPMENT_TEAM': 'X'},
      ),
      isNull,
    );
  });
}
