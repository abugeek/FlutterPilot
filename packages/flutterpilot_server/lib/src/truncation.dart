/// The one-line note a capped list ends with (task 07, from the curator skill's
/// response shaping). Written once so every tool says the same thing:
///
///     Showing 100 of 342 log lines. Narrow with level, query, sinceSeconds or
///     logger, or raise limit (max 500).
///
/// Without it an agent reads a cut list as complete ("there are no errors after
/// 14:02") or calls again with no change.
///
/// [shown] is how many the response keeps, [total] how many exist, [what] the
/// items (say which end was kept when it is not obvious) and [how] the
/// arguments to see more or narrow. A null [total] means the rest was not
/// counted — at least [shown] + 1 exist — so pass it only when something was
/// cut. A known [total] that is not more than [shown] gives null: the list is
/// complete and gets no note.
String? truncationNote({
  required int shown,
  int? total,
  required String what,
  required String how,
}) {
  if (total != null && total <= shown) return null;
  final of = total == null ? 'at least ${shown + 1}' : '$total';
  return 'Showing $shown of $of $what. $how';
}
