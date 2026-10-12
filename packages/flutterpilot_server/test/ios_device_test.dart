import 'package:flutterpilot_server/src/ios_device.dart';
import 'package:test/test.dart';

void main() {
  const procs = '''{"result":{"runningProcesses":[
    {"executable":"file:///usr/libexec/x","processIdentifier":1},
    {"executable":"file:///private/var/containers/Bundle/Application/AAA/Runner.app/Runner","processIdentifier":35745},
    {"executable":"file:///private/var/containers/Bundle/Application/BBB/Runner.app/Runner","processIdentifier":27662}]}}''';
  const apps = '''{"result":{"apps":[
    {"bundleIdentifier":"com.other","url":"file:///private/var/containers/Bundle/Application/BBB/Runner.app/"},
    {"bundleIdentifier":"dev.flutterpilot.flutterPilotExample","url":"file:///private/var/containers/Bundle/Application/AAA/Runner.app/"}]}}''';

  test('parseIosBundleId matches the process folder to the installed app', () {
    expect(
      parseIosBundleId(procs, apps, 35745),
      'dev.flutterpilot.flutterPilotExample',
    );
    expect(parseIosBundleId(procs, apps, 27662), 'com.other');
    expect(parseIosBundleId(procs, apps, 1), isNull);
    expect(parseIosBundleId(procs, apps, 999), isNull);
    expect(parseIosBundleId('nope', apps, 1), isNull);
  });

  test('recentCrashReportNames: .ips after the time, newest first', () {
    const files = '''{"result":{"files":[
      {"name":"old.ips","relativePath":"old.ips","metadata":{"lastModDate":"2026-09-01T00:00:00.000Z"}},
      {"name":"a.ips","relativePath":"a.ips","metadata":{"lastModDate":"2026-10-12T10:00:00.000Z"}},
      {"name":"b.ips","relativePath":"b.ips","metadata":{"lastModDate":"2026-10-12T11:00:00.000Z"}},
      {"name":"c.txt","relativePath":"c.txt","metadata":{"lastModDate":"2026-10-12T12:00:00.000Z"}}]}}''';
    expect(recentCrashReportNames(files, DateTime.utc(2026, 10, 1)), [
      'b.ips',
      'a.ips',
    ]);
    expect(recentCrashReportNames('x', DateTime.utc(2026)), isEmpty);
  });
}
