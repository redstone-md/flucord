part of 'discord_mapper.dart';

extension DiscordChannelMapper on DiscordMapper {
  ConversationChannel? channel(Map<String, Object?> payload, String guildId) {
    final type = payload['type'] as int?;
    final rawThreadMetadata = payload['thread_metadata'];
    final threadMetadata = rawThreadMetadata is Map
        ? rawThreadMetadata.cast<String, Object?>()
        : const <String, Object?>{};
    final archiveTimestamp = threadMetadata['archive_timestamp'] as String?;
    final availableTags = (payload['available_tags'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (raw) => ForumTag(
            id: raw['id']! as String,
            name: raw['name'] as String? ?? '',
            moderated: raw['moderated'] == true,
            emojiId: raw['emoji_id'] as String?,
            emojiName: raw['emoji_name'] as String?,
          ),
        )
        .toList(growable: false);
    final appliedTagIds = (payload['applied_tags'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final kind = switch (type) {
      0 || 5 || 10 || 11 || 12 => ChannelKind.text,
      2 || 13 => ChannelKind.voice,
      15 => ChannelKind.forum,
      16 => ChannelKind.media,
      _ => null,
    };
    if (kind == null) return null;
    return ConversationChannel(
      id: payload['id']! as String,
      spaceId: guildId,
      name: payload['name'] as String? ?? 'unnamed',
      topic:
          payload['topic'] as String? ??
          (kind == ChannelKind.voice ? 'Discord voice channel' : ''),
      kind: kind,
      position: payload['position'] as int? ?? 0,
      parentId: payload['parent_id'] as String?,
      isThread: type == 10 || type == 11 || type == 12,
      isArchived: threadMetadata['archived'] as bool? ?? false,
      isLocked: threadMetadata['locked'] as bool? ?? false,
      archiveTimestamp: archiveTimestamp == null
          ? null
          : DateTime.tryParse(archiveTimestamp)?.toLocal(),
      autoArchiveDurationMinutes:
          threadMetadata['auto_archive_duration'] as int?,
      availableTags: List.unmodifiable(availableTags),
      appliedTagIds: List.unmodifiable(appliedTagIds),
      defaultAutoArchiveDurationMinutes:
          payload['default_auto_archive_duration'] as int?,
      defaultSortOrder: switch (payload['default_sort_order']) {
        0 => ForumSortOrder.latestActivity,
        1 => ForumSortOrder.creationDate,
        _ => null,
      },
      defaultForumLayout: switch (payload['default_forum_layout']) {
        0 => ForumLayout.notSet,
        1 => ForumLayout.listView,
        2 => ForumLayout.galleryView,
        _ => null,
      },
      permissionOverwrites: DiscordPermissionOverwrite.mapFromJson(
        payload['permission_overwrites'],
      ),
      unread: false,
      lastMessageId: _lastMessageId(payload),
    );
  }
}

/// A channel's newest-message pointer, which unread is a comparison against.
///
/// Discord spells "no messages here" as a null, as an empty string and as the
/// literal `0`; all three have to read as absent, or the zero would compare
/// as a real snowflake and mark an empty channel unread forever.
String? _lastMessageId(Map<String, Object?> payload) {
  final id = payload['last_message_id'];
  if (id is int) return id == 0 ? null : '$id';
  if (id is! String || id.isEmpty || DiscordSnowflake.isZero(id)) return null;
  return id;
}
