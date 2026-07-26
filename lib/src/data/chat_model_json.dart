import 'dart:convert';

import '../domain/chat_models.dart';
import '../domain/discord_permissions.dart';
import '../domain/guild_membership.dart';
import '../domain/message_embed.dart';
import '../domain/permission_overwrite.dart';
import 'message_attachment_codec.dart';
import 'message_embed_codec.dart';
import 'message_poll_codec.dart';
import 'message_sticker_codec.dart';

final class ChatModelJson {
  const ChatModelJson._();

  static String attachments(List<MessageAttachment> values) =>
      MessageAttachmentCodec.encode(values);

  static List<MessageAttachment> attachmentsFrom(String source) =>
      MessageAttachmentCodec.decode(source);

  static String embeds(List<MessageEmbed> values) =>
      MessageEmbedCodec.encode(values);

  static List<MessageEmbed> embedsFrom(String source) =>
      MessageEmbedCodec.decode(source);

  static String? poll(MessagePoll? value) => MessagePollCodec.encode(value);

  static MessagePoll? pollFrom(String? source) =>
      MessagePollCodec.decode(source);

  static String stickers(List<MessageSticker> value) =>
      MessageStickerCodec.encode(value);

  static List<MessageSticker> stickersFrom(String source) =>
      MessageStickerCodec.decode(source);

  static String? reply(MessageReply? value) => value == null
      ? null
      : jsonEncode({
          'message_id': value.messageId,
          'author_id': value.authorId,
          'body': value.body,
        });

  static MessageReply? replyFrom(String? source) {
    if (source == null) return null;
    final raw = jsonDecode(source) as Map;
    return MessageReply(
      messageId: raw['message_id'] as String,
      authorId: raw['author_id'] as String,
      body: raw['body'] as String,
    );
  }

  static String reactions(List<MessageReaction> values) => jsonEncode([
    for (final value in values)
      {
        'name': value.emojiName,
        'id': value.emojiId,
        'count': value.count,
        'normal_count': value.normalCount,
        'burst_count': value.burstCount,
        'animated': value.animated,
        'me': value.reactedByCurrentUser,
        'me_burst': value.burstByCurrentUser,
        'burst_colors': value.burstColorValues,
      },
  ]);

  static List<MessageReaction> reactionsFrom(String source) =>
      (jsonDecode(source) as List)
          .whereType<Map>()
          .map(
            (raw) => MessageReaction(
              emojiName: raw['name'] as String,
              emojiId: raw['id'] as String?,
              count: raw['count'] as int,
              normalCount: raw['normal_count'] as int?,
              burstCount: raw['burst_count'] as int? ?? 0,
              animated: raw['animated'] as bool,
              reactedByCurrentUser: raw['me'] as bool,
              burstByCurrentUser: raw['me_burst'] as bool? ?? false,
              burstColorValues: (raw['burst_colors'] as List? ?? const [])
                  .whereType<int>()
                  .toList(),
            ),
          )
          .toList(growable: false);

  static String strings(Iterable<String> values) => jsonEncode(values.toList());

  static Set<String> stringsFrom(String source) =>
      (jsonDecode(source) as List).whereType<String>().toSet();

  static String stringMap(Map<String, String> values) => jsonEncode(values);

  static Map<String, String> stringMapFrom(String source) =>
      (jsonDecode(source) as Map).map(
        (key, value) => MapEntry(key as String, value as String),
      );

  static String forumTags(List<ForumTag> values) => jsonEncode([
    for (final value in values)
      {
        'id': value.id,
        'name': value.name,
        'moderated': value.moderated,
        'emoji_id': value.emojiId,
        'emoji_name': value.emojiName,
      },
  ]);

  static List<ForumTag> forumTagsFrom(String source) => List.unmodifiable(
    (jsonDecode(source) as List).whereType<Map>().map(
      (raw) => ForumTag(
        id: raw['id'] as String,
        name: raw['name'] as String,
        moderated: raw['moderated'] as bool,
        emojiId: raw['emoji_id'] as String?,
        emojiName: raw['emoji_name'] as String?,
      ),
    ),
  );

  static List<String> stringListFrom(String source) =>
      List.unmodifiable((jsonDecode(source) as List).whereType<String>());

  /// Overwrites are cached in Discord's own wire shape so the same reader
  /// serves the gateway payload and the cache row.
  static String permissionOverwrites(
    Map<String, DiscordPermissionOverwrite> values,
  ) => jsonEncode([
    for (final value in values.values)
      {
        'id': value.id,
        'type': value.kind.discordValue,
        'allow': DiscordPermissions.encode(value.allow),
        'deny': DiscordPermissions.encode(value.deny),
      },
  ]);

  static Map<String, DiscordPermissionOverwrite> permissionOverwritesFrom(
    String? source,
  ) => source == null
      ? const {}
      : DiscordPermissionOverwrite.mapFromJson(jsonDecode(source));

  static String memberships(Map<String, GuildMembership> values) => jsonEncode({
    for (final entry in values.entries)
      entry.key: {
        'roles': entry.value.roleIds,
        'flags': entry.value.flags,
        'pending': entry.value.isPending,
        'timeout': entry.value.timeoutUntil?.toIso8601String(),
      },
  });

  static Map<String, GuildMembership> membershipsFrom(String? source) {
    if (source == null) return const {};
    final decoded = jsonDecode(source);
    if (decoded is! Map) return const {};
    return {
      for (final entry in decoded.entries)
        if (entry.key is String && entry.value is Map)
          entry.key as String: _membershipFrom(
            (entry.value as Map).cast<String, Object?>(),
          ),
    };
  }

  static GuildMembership _membershipFrom(Map<String, Object?> raw) {
    final timeout = raw['timeout'] as String?;
    return GuildMembership(
      roleIds: (raw['roles'] as List? ?? const []).whereType<String>().toList(
        growable: false,
      ),
      flags: raw['flags'] as int? ?? 0,
      isPending: raw['pending'] as bool? ?? false,
      timeoutUntil: timeout == null ? null : DateTime.tryParse(timeout),
    );
  }
}
