import 'dart:convert';
import '../../domain/message_component.dart';
import 'discord_message_component_service.dart';

import '../../domain/chat_models.dart';
import '../../domain/discord_permissions.dart';
import '../../domain/discord_rgb.dart';
import '../../domain/discord_snowflake.dart';
import '../../domain/guild_membership.dart';
import '../../domain/message_search.dart';
import '../../domain/monogram.dart';
import '../../domain/permission_overwrite.dart';
import '../message_attachment_codec.dart';
import '../message_embed_codec.dart';
import 'discord_cdn.dart';
import 'discord_color.dart';
import 'discord_mention_matcher.dart';

part 'discord_poll_mapper.dart';
part 'discord_message_mapper.dart';
part 'discord_message_search_mapper.dart';
part 'discord_message_snapshot_mapper.dart';
part 'discord_sticker_mapper.dart';
part 'discord_scheduled_event_mapper.dart';
part 'discord_channel_mapper.dart';

final class DiscordMapper {
  static const directMessagesSpaceId = CommunitySpace.directMessagesId;

  ChatWorkspace workspace({
    required Map<String, Object?> currentUser,
    required List<Map<String, Object?>> guilds,
    required Map<String, List<Map<String, Object?>>> channelsByGuild,
    Map<String, List<Map<String, Object?>>> threadsByGuild = const {},
    Map<String, List<Map<String, Object?>>> membersByGuild = const {},
    Map<String, List<Map<String, Object?>>> rolesByGuild = const {},
    Map<String, List<Map<String, Object?>>> emojisByGuild = const {},
    Map<String, List<Map<String, Object?>>> stickersByGuild = const {},
    List<Map<String, Object?>> directChannels = const [],
    bool includeDirectMessagesSpace = false,
    String currentUserRole = 'Discord bot',
  }) {
    final spaces = <CommunitySpace>[];
    final channels = <ConversationChannel>[];
    final categories = <ChannelCategory>[];
    final roles = <CommunityRole>[];
    final emojis = <GuildEmoji>[];
    final stickers = <GuildSticker>[];
    final members = <String, Member>{};
    if (includeDirectMessagesSpace || directChannels.isNotEmpty) {
      spaces.add(directMessagesSpace);
    }
    for (final payload in directChannels) {
      final mapped = directMessage(payload, currentUser['id']! as String);
      if (mapped == null) continue;
      channels.add(mapped.channel);
      for (final recipient in mapped.recipients) {
        members[recipient.id] = recipient;
      }
    }
    for (final guild in guilds) {
      final guildId = guild['id']! as String;
      final rawChannels = [
        ...(channelsByGuild[guildId] ?? const []),
        ...(threadsByGuild[guildId] ?? const []),
      ];
      final mappedChannels = rawChannels
          .map((channel) => this.channel(channel, guildId))
          .whereType<ConversationChannel>()
          .toList();
      if (mappedChannels.isEmpty) continue;
      spaces.add(_space(guild));
      channels.addAll(mappedChannels);
      categories.addAll(
        rawChannels
            .map((channel) => category(channel, guildId))
            .whereType<ChannelCategory>(),
      );
      roles.addAll(
        (rolesByGuild[guildId] ?? const []).map(
          (payload) => role(payload, guildId),
        ),
      );
      emojis.addAll(
        (emojisByGuild[guildId] ?? const []).map(
          (payload) => emoji(payload, guildId),
        ),
      );
      stickers.addAll(
        (stickersByGuild[guildId] ?? const []).map(
          (payload) => guildSticker(payload, guildId),
        ),
      );
      for (final payload in membersByGuild[guildId] ?? const []) {
        final mapped = guildMember(payload, guildId);
        members[mapped.id] = _mergeMembers(members[mapped.id], mapped);
      }
    }
    final currentMember = member(
      currentUser,
      role: currentUserRole,
      presence: Presence.online,
      spaceIds: spaces.map((space) => space.id).toSet(),
    );
    members[currentMember.id] = _mergeMembers(
      members[currentMember.id],
      currentMember,
    );
    return ChatWorkspace(
      spaces: spaces,
      channels: channels,
      roles: roles,
      categories: categories,
      members: members.values.toList(),
      messages: const [],
      emojis: emojis,
      stickers: stickers,
      currentMemberId: currentMember.id,
    );
  }

  CommunitySpace get directMessagesSpace =>
      const CommunitySpace.directMessages();

  GuildEmoji emoji(Map<String, Object?> payload, String guildId) {
    final id = payload['id']! as String;
    final animated = payload['animated'] as bool? ?? false;
    return GuildEmoji(
      id: id,
      spaceId: guildId,
      name: payload['name']! as String,
      animated: animated,
      available: payload['available'] as bool? ?? true,
      imageUrl: DiscordCdn.customEmoji(id, animated: animated, size: 64),
    );
  }

  /// A DM from Discord's private channel: a one-to-one DM (type 1) or a
  /// group DM (type 3). Null for any other type, and for a one-to-one DM that
  /// names nobody.
  DirectConversation? directMessage(
    Map<String, Object?> payload,
    String currentUserId,
  ) {
    final type = payload['type'];
    if (type != 1 && type != 3) return null;
    final recipients = (payload['recipients'] as List? ?? const [])
        .whereType<Map>()
        .map((recipient) => recipient.cast<String, Object?>())
        .where((recipient) => recipient['id'] != currentUserId)
        .map(
          (recipient) => member(
            recipient,
            role: 'Direct message',
            spaceIds: const {directMessagesSpaceId},
          ),
        )
        .toList(growable: false);
    if (type == 1 && recipients.isEmpty) return null;
    final id = payload['id']! as String;
    final name = type == 1
        ? recipients.first.displayName
        : _groupName(payload['name'], recipients);
    return DirectConversation(
      recipients: recipients,
      channel: ConversationChannel(
        id: id,
        spaceId: directMessagesSpaceId,
        name: name,
        topic: type == 1 ? 'Direct message with $name' : '',
        kind: ChannelKind.text,
        recipientIds: [for (final recipient in recipients) recipient.id],
        isGroupDirectMessage: type == 3,
        iconUrl: DiscordCdn.channelIcon(id, payload['icon'] as String?),
        isMessageRequest: payload['is_message_request'] as bool? ?? false,
        messageRequestedAt: _messageRequestTimestamp(
          payload['is_message_request_timestamp'],
        ),
        lastMessageId: _lastMessageId(payload),
      ),
    );
  }

  /// A group DM's own name, or its recipients' names when it has none, the
  /// way Discord titles an unnamed group.
  static String _groupName(Object? name, List<Member> recipients) {
    if (name is String && name.trim().isNotEmpty) return name;
    if (recipients.isEmpty) return 'Unnamed group';
    return recipients.map((recipient) => recipient.displayName).join(', ');
  }

  /// The request's own timestamp, promoted out of its ISO string. Discord
  /// sorts unanswered requests on it, and the folder does the same; a value
  /// that will not parse is dropped rather than guessed at.
  static DateTime? _messageRequestTimestamp(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  ChannelHistory history(
    String channelId,
    List<Map<String, Object?>> payloads, {
    String? currentMemberId,
  }) {
    final members = <String, Member>{};
    final messages = <ChatMessage>[];
    for (final payload in payloads.reversed) {
      final authorPayload = (payload['author']! as Map).cast<String, Object?>();
      final author = member(authorPayload);
      members[author.id] = author;
      messages.add(message(payload, currentMemberId: currentMemberId));
    }
    return ChannelHistory(
      channelId: channelId,
      messages: messages,
      members: members.values.toList(),
    );
  }

  MessageAttachment _attachment(Map<String, Object?> payload) =>
      MessageAttachmentCodec.fromMap(payload);

  MessageReaction _reaction(Map<String, Object?> payload) {
    final emoji =
        (payload['emoji'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    final counts =
        (payload['count_details'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    final count = payload['count'] as int? ?? 0;
    final burstCount = counts['burst'] as int? ?? 0;
    return MessageReaction(
      emojiName: emoji['name'] as String? ?? '?',
      emojiId: emoji['id'] as String?,
      animated: emoji['animated'] as bool? ?? false,
      count: count,
      normalCount: counts['normal'] as int? ?? count - burstCount,
      burstCount: burstCount,
      reactedByCurrentUser: payload['me'] as bool? ?? false,
      burstByCurrentUser: payload['me_burst'] as bool? ?? false,
      burstColorValues: (payload['burst_colors'] as List? ?? const [])
          .whereType<String>()
          .map(DiscordColor.parseHex)
          .whereType<int>()
          .toList(growable: false),
    );
  }

  MessageReply? _reply(Map<String, Object?> payload) {
    final id = payload['id'] as String?;
    final author = payload['author'];
    final authorId = author is Map ? author['id'] as String? : null;
    if (id == null || authorId == null) return null;
    return MessageReply(
      messageId: id,
      authorId: authorId,
      body: payload['content'] as String? ?? '',
    );
  }

  /// The members carried by a `GUILD_MEMBERS_CHUNK`.
  ///
  /// Each row is a guild member wrapping a user, and the guild is named once
  /// on the chunk rather than on every row, so it is threaded in here. A row
  /// with no user is dropped: it names nobody to mention.
  List<Member> membersFromChunk(Map<String, Object?> payload) {
    final guildId = payload['guild_id'];
    final rows = payload['members'];
    if (guildId is! String || guildId.isEmpty || rows is! List) {
      return const [];
    }
    return [
      for (final row in rows.whereType<Map>())
        if (row['user'] case final Map user when user['id'] is String)
          _chunkMember(user.cast<String, Object?>(), row, guildId),
    ];
  }

  /// One row of a chunk. The guild nickname wins where there is one: it is
  /// the name that guild knows somebody by, and the name everybody there sees.
  Member _chunkMember(
    Map<String, Object?> user,
    Map<Object?, Object?> row,
    String guildId,
  ) {
    return _withGuildStanding(
      member(user, spaceIds: {guildId}),
      row.cast<String, Object?>(),
      guildId,
    );
  }

  /// [mapped] with what a guild member payload adds: the nickname, and the
  /// roles the name's colour comes from.
  Member _withGuildStanding(
    Member mapped,
    Map<String, Object?> guildMember,
    String guildId,
  ) {
    final nickname = switch (guildMember['nick']) {
      final String nick when nick.isNotEmpty => nick,
      _ => null,
    };
    return mapped.copyWith(
      displayName: nickname,
      initials: nickname == null ? null : monogramOf(nickname),
      membershipsBySpace: {guildId: membership(guildMember)},
    );
  }

  Member member(
    Map<String, Object?> payload, {
    String role = 'Member',
    Presence presence = Presence.offline,
    Set<String> spaceIds = const {},
    int? colorValue,
  }) {
    final username =
        payload['global_name'] as String? ??
        payload['username'] as String? ??
        'Unknown';
    final id = payload['id']! as String;
    return Member(
      id: id,
      displayName: username,
      initials: monogramOf(username),
      role: role,
      presence: presence,
      colorValue: colorValue ?? monogramColorOf(id),
      spaceIds: spaceIds,
      avatarUrl: DiscordCdn.userAvatar(id, payload['avatar'] as String?),
      tags: tags(payload),
      username: _username(payload),
    );
  }

  /// The username and tags of a whole user, or null for a partial one that
  /// names the user by id alone.
  MemberIdentity? identity(Map<String, Object?> user) =>
      switch (_username(user)) {
        final username? => MemberIdentity(username: username, tags: tags(user)),
        null => null,
      };

  static String? _username(Map<String, Object?> user) =>
      switch (user['username']) {
        final String username when username.isNotEmpty => username,
        _ => null,
      };

  /// The tags on [user]. A user object without `primary_guild`,
  /// `collectibles` or `display_name_styles` says nothing about that part;
  /// one where it is null says there is none.
  static MemberTags tags(Map<String, Object?> user) => MemberTags(
    isBot: user['bot'] == true,
    clanTag: _clanTag(user),
    nameplate: _nameplate(user['collectibles']),
    nameStyle: _nameStyle(user['display_name_styles']),
    unsaid: {
      if (!user.containsKey('primary_guild')) TagPart.clanTag,
      if (!user.containsKey('collectibles')) TagPart.nameplate,
      if (!user.containsKey('display_name_styles')) TagPart.nameStyle,
    },
  );

  /// The nameplate in a user's `collectibles`. Collectibles without one say
  /// the user has none.
  static Nameplate? _nameplate(Object? collectibles) => collectibles is Map
      ? Nameplate.fromJson(collectibles['nameplate'])
      : null;

  static NameStyle? _nameStyle(Object? styles) {
    if (styles is! Map) return null;
    return NameStyle(
      colors: [
        for (final color in styles['colors'] as List? ?? const [])
          if (color is int) DiscordRgb(color).opaque,
      ],
      fontId: styles['font_id'] as int?,
      effectId: styles['effect_id'] as int?,
    );
  }

  /// The server tag [user] shows, or null when it shows none.
  ///
  /// Discord keeps a tag the user turned off, with `identity_enabled` false or
  /// null. Such a tag is not drawn anywhere, so it is dropped here.
  static ClanTag? _clanTag(Map<String, Object?> user) {
    final clan = user['primary_guild'];
    if (clan is! Map || clan['identity_enabled'] != true) return null;
    final tag = clan['tag'];
    final guildId = clan['identity_guild_id'];
    if (tag is! String || tag.isEmpty || guildId is! String) return null;
    return ClanTag(
      tag: tag,
      guildId: guildId,
      badgeUrl: DiscordCdn.clanBadge(guildId, clan['badge'] as String?),
    );
  }

  /// A guild member. Their roles are kept as ids in [GuildMembership]; the
  /// name, place and colour of each role are read from the workspace, so a
  /// role change shows on every member who holds it. See [HeldRoles].
  Member guildMember(Map<String, Object?> payload, String guildId) {
    final user = (payload['user']! as Map).cast<String, Object?>();
    final username =
        payload['nick'] as String? ??
        user['global_name'] as String? ??
        user['username'] as String? ??
        'Unknown';
    final id = user['id']! as String;
    final guildAvatarUrl = DiscordCdn.guildMemberAvatar(
      guildId,
      id,
      payload['avatar'] as String?,
    );
    return Member(
      id: id,
      displayName: username,
      initials: monogramOf(username),
      role: 'Member',
      presence: Presence.offline,
      colorValue: monogramColorOf(id),
      spaceIds: {guildId},
      avatarUrl: DiscordCdn.userAvatar(id, user['avatar'] as String?),
      avatarUrlsBySpace: {guildId: ?guildAvatarUrl},
      membershipsBySpace: {guildId: membership(payload)},
      tags: tags(user),
      username: _username(user),
    );
  }

  /// The permission-relevant half of a guild member payload.
  GuildMembership membership(Map<String, Object?> payload) {
    final timeout = payload['communication_disabled_until'] as String?;
    final joined = payload['joined_at'] as String?;
    return GuildMembership(
      roleIds: (payload['roles'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      flags: payload['flags'] as int? ?? 0,
      isPending: payload['pending'] as bool? ?? false,
      timeoutUntil: timeout == null ? null : DateTime.tryParse(timeout),
      joinedAt: joined == null ? null : DateTime.tryParse(joined),
    );
  }

  /// The coarse status a member row carries until a full presence arrives.
  ///
  /// It reads the wire value rather than folding `dnd` into `idle`: the two
  /// paint different colours, and a roster page that arrived after a presence
  /// frame would otherwise turn a red dot yellow until the next frame.
  Presence presence(String status) => Presence.fromWire(status);

  CommunityRole role(Map<String, Object?> payload, String guildId) {
    final rawColor = payload['color'] as int? ?? 0;
    return CommunityRole(
      id: payload['id']! as String,
      spaceId: guildId,
      name: payload['name'] as String? ?? 'unknown-role',
      position: payload['position'] as int? ?? 0,
      colorValue: rawColor == 0 ? null : 0xff000000 | rawColor,
      hoist: payload['hoist'] == true,
      // Left null rather than zeroed when the field is absent: a role that
      // grants nothing and a role we were told nothing about lead to opposite
      // decisions once permissions are computed.
      permissions: DiscordPermissions.tryParse(payload['permissions']),
    );
  }

  ChannelCategory? category(Map<String, Object?> payload, String guildId) {
    if (payload['type'] != 4) return null;
    return ChannelCategory(
      id: payload['id']! as String,
      spaceId: guildId,
      name: payload['name'] as String? ?? 'Unnamed category',
      position: payload['position'] as int? ?? 0,
    );
  }

  static Member _mergeMembers(Member? previous, Member incoming) {
    if (previous == null) return incoming;
    return incoming.copyWith(
      spaceIds: {...previous.spaceIds, ...incoming.spaceIds},
      avatarUrl: incoming.avatarUrl ?? previous.avatarUrl,
      avatarUrlsBySpace: {
        ...previous.avatarUrlsBySpace,
        ...incoming.avatarUrlsBySpace,
      },
      membershipsBySpace: {
        ...previous.membershipsBySpace,
        ...incoming.membershipsBySpace,
      },
      presence: incoming.presence == Presence.offline
          ? previous.presence
          : incoming.presence,
      username: incoming.username ?? previous.username,
      tags: incoming.tags.over(previous.tags),
    );
  }

  CommunitySpace _space(Map<String, Object?> payload) {
    final id = payload['id']! as String;
    // The desktop session splits the guild record into a `properties` object
    // while the REST guild list keeps everything flat, so permission-relevant
    // fields are read from whichever of the two carried them.
    final properties = payload['properties'];
    final core = properties is Map
        ? properties.cast<String, Object?>()
        : payload;
    // The name and the icon live in there too, which is why every server on a
    // desktop session was drawn as "Unnamed server" with a blank badge.
    final name =
        (payload['name'] ?? core['name']) as String? ?? 'Unnamed server';
    final icon = (payload['icon'] ?? core['icon']) as String?;
    return CommunitySpace(
      id: id,
      name: name,
      monogram: monogramOf(name),
      colorValue: monogramColorOf(id),
      iconUrl: DiscordCdn.guildIcon(id, icon),
      ownerId: (payload['owner_id'] ?? core['owner_id']) as String?,
      requiresMultiFactorAuth: (payload['mfa_level'] ?? core['mfa_level']) == 1,
      premiumTier:
          (payload['premium_tier'] ?? core['premium_tier']) as int? ?? 0,
      memberCount: (payload['member_count'] ?? core['member_count']) as int?,
      joinedAt: switch (payload['joined_at'] ?? core['joined_at']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
    );
  }

  /// The same projection for the join and create answers, which must draw a
  /// joined server exactly like one the session was opened with.
  CommunitySpace spaceFromGuildPayload(Map<String, Object?> payload) =>
      _space(payload);
}
