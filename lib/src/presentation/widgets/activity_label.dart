/// What a screen reader says for a server or a channel with [name].
///
/// Mentions come first, because they ask for the reader's attention most.
String activityLabel(
  String name, {
  required int mentionCount,
  required bool muted,
  required bool unread,
}) {
  if (mentionCount == 1) return '$name, 1 mention';
  if (mentionCount > 1) return '$name, $mentionCount mentions';
  if (muted) return '$name, muted';
  return unread ? '$name, unread' : name;
}
