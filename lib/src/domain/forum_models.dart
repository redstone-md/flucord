part of 'chat_models.dart';

enum ForumSortOrder { latestActivity, creationDate }

enum ForumLayout { notSet, listView, galleryView }

final class ForumTag {
  const ForumTag({
    required this.id,
    required this.name,
    required this.moderated,
    this.emojiId,
    this.emojiName,
  });

  final String id;
  final String name;
  final bool moderated;
  final String? emojiId;
  final String? emojiName;
}
