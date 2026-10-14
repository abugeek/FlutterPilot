/// Splits uncaught exceptions by the last hot reload (or restart) of their
/// device, for the two tools that answer "is the app healthy now?" (field
/// test #334).
///
/// A hot reload keeps the app's error buffer: after the agent fixes the code
/// and reloads, the error that prompted the fix is still the newest entry, so
/// `get_app_summary`'s "Uncaught Errors" and `get_errors` both listed an error
/// the reload may have fixed — while `get_errors(report: true)`, whose report
/// needs an exception seen since the last reload, said there was none.
///
/// [errors] are the app's entries and [lastReload] when its device last
/// reloaded. No reload since the server connected (null) means nothing is
/// "before" it: no claim is made about entries the server cannot date. An
/// entry that cannot be dated itself counts as [since] for the same reason.
({List<Map<String, dynamic>> since, List<Map<String, dynamic>> before})
errorsByReload(List<Map<String, dynamic>> errors, DateTime? lastReload) {
  if (lastReload == null) return (since: errors, before: const []);
  final since = <Map<String, dynamic>>[];
  final before = <Map<String, dynamic>>[];
  for (final error in errors) {
    final at = DateTime.tryParse('${error['timestamp']}');
    (at != null && at.isBefore(lastReload) ? before : since).add(error);
  }
  return (since: since, before: before);
}

/// How both tools mark the entries [errorsByReload] put before the reload:
/// they are still in the app's buffer, but the reload may have fixed them.
String beforeReloadNote(int count) =>
    '$count uncaught exception${count == 1 ? '' : 's'} from before the last '
    'reload (the reload may have fixed ${count == 1 ? 'it' : 'them'})';
