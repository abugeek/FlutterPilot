import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Signing a debug build for a real iPhone needs a Team. Xcode takes it from
/// the project; a Flutter app that never opened Xcode has none, and the build
/// fails with "No profiles for …". With a single Apple Development
/// certificate on this Mac there is nothing to choose, so the launcher passes
/// that team as `FLUTTER_XCODE_DEVELOPMENT_TEAM` (a build setting Flutter
/// forwards), without touching the project.

/// The team id (`OU=`) of an `openssl x509 -subject` line, else null.
String? teamFromCertificateSubject(String subject) =>
    RegExp(r'OU\s*=\s*([A-Z0-9]{10})\b').firstMatch(subject)?.group(1);

/// `flutter devices` ids of real iPhones: `00008130-001210260C04001C`, or
/// the older 40-digit UDID. Simulators have a dashed UUID.
bool isPhysicalIosDeviceId(String id) =>
    RegExp(r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$').hasMatch(id) ||
    RegExp(r'^[0-9A-Fa-f]{40}$').hasMatch(id);

/// Whether the iOS project already names a team.
bool projectHasTeam(Directory root) {
  try {
    final text = File(
      p.join(root.path, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
    ).readAsStringSync();
    return RegExp(r'DEVELOPMENT_TEAM = [A-Z0-9]{10};').hasMatch(text);
  } catch (_) {
    return false;
  }
}

/// The one team of the valid Apple Development certificates in the keychain;
/// null when there are none or several (then the user chooses).
Future<String?> detectSigningTeam() async {
  if (!Platform.isMacOS) return null;
  try {
    final pem = await Process.run('security', [
      'find-certificate',
      '-a',
      '-c',
      'Apple Development',
      '-p',
    ]).timeout(const Duration(seconds: 10));
    if (pem.exitCode != 0) return null;
    final certs = RegExp(
      r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',
      dotAll: true,
    ).allMatches('${pem.stdout}').map((m) => m.group(0)!).toList();
    final teams = <String>{};
    for (final cert in certs) {
      final openssl = await Process.start('openssl', [
        'x509',
        '-noout',
        '-subject',
        '-checkend',
        '0',
      ]);
      openssl.stdin.write(cert);
      await openssl.stdin.close();
      final out = await openssl.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      // `-checkend 0` exits 1 once the certificate has expired.
      if (await openssl.exitCode != 0) continue;
      if (teamFromCertificateSubject(out) case final team?) teams.add(team);
    }
    return teams.length == 1 ? teams.single : null;
  } catch (_) {
    return null;
  }
}

/// The team to build with for [device] in [root], or null when none is
/// needed or knowable: not a real iPhone, a project that names a team, or
/// the environment (or launch.json) already decides.
Future<String?> signingTeamFor(
  Directory root, {
  required String? device,
  Map<String, String>? environment,
}) async {
  if (device == null || !isPhysicalIosDeviceId(device)) return null;
  if ((environment ?? Platform.environment).containsKey(
    'FLUTTER_XCODE_DEVELOPMENT_TEAM',
  )) {
    return null;
  }
  if (projectHasTeam(root)) return null;
  return detectSigningTeam();
}
