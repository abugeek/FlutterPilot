/// `get_state(history: true)`: the app's recent state and route changes as
/// lines, oldest first — `12:04:12.110  riverpod  cart: 3 → 0`.
///
/// [type] keeps one plugin's changes (and the route changes between them).
String formatStateHistory(
  List<Map<String, Object?>> changes, {
  int dropped = 0,
  String? type,
  bool cleared = false,
}) {
  final shown = [
    for (final c in changes)
      if (type == null || c['source'] == type || c['source'] == 'navigation') c,
  ];
  if (shown.isEmpty) {
    return 'No state changes observed since the app started'
        '${cleared ? '' : ' (or since the history was cleared)'}.';
  }
  final lines = [
    'State changes, oldest first (${shown.length}'
        '${dropped > 0 ? '; $dropped older ones dropped' : ''}):',
    for (final c in shown) _line(c),
    if (cleared) 'History cleared.',
  ];
  return lines.join('\n');
}

String _line(Map<String, Object?> c) {
  // 2026-10-05T01:04:12.110123 → 01:04:12.110
  final at = '${c['at']}';
  final time = at.length >= 23 ? at.substring(11, 23) : at;
  final head = '$time  ${c['source']}  ';
  if (c['source'] == 'navigation') {
    return '$head${c['name']}${c['to'] == null ? '' : ' ${c['to']}'}';
  }
  final from = c['from'];
  if (c['disposed'] == true) {
    return '$head${c['name']}: disposed${from == null ? '' : ' (was $from)'}';
  }
  return from == null
      ? '$head${c['name']}: created ${c['to']}'
      : '$head${c['name']}: $from → ${c['to']}';
}
