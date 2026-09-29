import 'dart:io';

File get _file =>
    File('${Directory.systemTemp.path}/flutterpilot_restart_$pid.json');

void write(String data) => _file.writeAsStringSync(data);

String? readAndDelete() {
  try {
    final f = _file;
    if (!f.existsSync()) return null;
    final data = f.readAsStringSync();
    f.deleteSync();
    return data;
  } catch (_) {
    return null;
  }
}
