/// A system permission dialog is not in the Flutter tree, and on a real
/// iPhone nothing here can tap it (idb drives simulators only). What does
/// work: answer the plugin's platform call ourselves so the dialog never
/// opens. [calls] are the app's platform-channel calls (`channel`, `method`,
/// `outcome`), as `ext.flutterpilot.platformChannel` lists them.
String? permissionCallsHint(List<Object?> calls) {
  final looksLikePermission = RegExp(
    r'permission|authoriz|location|camera|microphone|photo|contacts?|'
    r'notification|bluetooth|geolocator|tracking',
    caseSensitive: false,
  );
  final candidates = <String>[
    for (final c in calls.whereType<Map>())
      if (looksLikePermission.hasMatch('${c['channel']} ${c['method']}') &&
          c['outcome'] != 'mocked')
        '${c['channel']}${c['method'] == null ? '' : ' / ${c['method']}'}',
  ];
  if (candidates.isEmpty) return null;
  final last = candidates.reversed.take(3).toList().reversed;
  return 'Likely cause, the app asked: ${last.join('; ')}. Dismiss the '
      'dialog on the phone, or answer that call so it never opens '
      '(mock_platform_channel(channel:, method:, result:) with the granted '
      'value; the mock is lost on a hot restart).';
}
