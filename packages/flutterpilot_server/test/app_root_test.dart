import 'package:flutterpilot_server/src/app_root.dart';
import 'package:test/test.dart';

void main() {
  test('a POSIX path is unchanged', () {
    expect(creationLocationRoot('/Users/me/app'), '/Users/me/app');
    expect(creationLocationRoot('/Users/me/app/'), '/Users/me/app');
  });

  test('a Windows path becomes the path of its file URI', () {
    expect(creationLocationRoot(r'D:\projects\app'), '/D:/projects/app');
    expect(creationLocationRoot(r'D:\projects\app\'), '/D:/projects/app');
    expect(creationLocationRoot('C:/projects/app'), '/C:/projects/app');
  });

  test('a creation location under the root starts with it', () {
    final location = Uri.parse('file:///D:/projects/my%20app/tool/main.dart');
    expect(
      location.path.startsWith(creationLocationRoot(r'D:\projects\my app')),
      isTrue,
    );
  });
}
