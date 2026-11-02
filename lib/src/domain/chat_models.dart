import 'dart:collection';

import 'discord_snowflake.dart';
import 'go_live_stream.dart';
import 'message_component.dart';
import 'guild_membership.dart';
import 'message_embed.dart';
import 'permission_overwrite.dart';

part 'community_space.dart';
part 'message_models.dart';
part 'message_poll.dart';
part 'message_sticker.dart';
part 'channel_category.dart';
part 'conversation_channel.dart';
part 'forum_models.dart';
part 'guild_emoji.dart';
part 'guild_sticker.dart';
part 'guild_scheduled_event.dart';
part 'guild_scheduled_event_attendee.dart';
part 'guild_scheduled_event_exception.dart';
part 'guild_scheduled_event_recurrence.dart';
part 'guild_scheduled_event_editing.dart';
part 'held_messages.dart';
part 'user_activity.dart';
part 'user_presence.dart';
part 'workspace_member.dart';

enum ChannelKind { text, voice, forum, media }

final class PendingAttachment {
  static const maxCount = 10;

  const PendingAttachment({
    required this.name,
    required this.path,
    required this.size,
  });

  final String name;
  final String path;
  final int size;

  /// Whether this file is tagged as a spoiler.
  ///
  /// The tag is the name: Discord's convention is a `SPOILER_` prefix on the
  /// filename, applied at attach time so the upload carries it and the
  /// receiver reads it back off the stored name.
  bool get isSpoiler => name.startsWith(MessageAttachment.spoilerPrefix);

  /// The same file with the spoiler tag applied or removed.
  PendingAttachment asSpoiler({required bool spoiler}) {
    if (spoiler == isSpoiler) return this;
    final prefix = MessageAttachment.spoilerPrefix;
    return PendingAttachment(
      name: spoiler ? '$prefix$name' : name.substring(prefix.length),
      path: path,
      size: size,
    );
  }
}

final class ChatWorkspace {
  /// The most messages a channel keeps while it is not open: two pages of
  /// history. So a channel read once can take a page of new messages and still
  /// open at once.
  static const notOpenChannelCap = 200;

  ChatWorkspace({
    required List<CommunitySpace> spaces,
    required List<ConversationChannel> channels,
    required List<Member> members,
    required List<ChatMessage> messages,
    required String currentMemberId,
    List<CommunityRole> roles = const [],
    List<ChannelCategory> categories = const [],
    List<GuildEmoji> emojis = const [],
    List<GuildSticker> stickers = const [],
  }) : this._(
         spaces: spaces,
         channels: channels,
         members: members,
         held: _HeldMessages.of(messages),
         currentMemberId: currentMemberId,
         roles: roles,
         categories: categories,
         emojis: emojis,
         stickers: stickers,
       );

  ChatWorkspace._({
    required List<CommunitySpace> spaces,
    required List<ConversationChannel> channels,
    required List<Member> members,
    required _HeldMessages held,
    required this.currentMemberId,
    required List<CommunityRole> roles,
    required List<ChannelCategory> categories,
    required List<GuildEmoji> emojis,
    required List<GuildSticker> stickers,
  }) : spaces = _sealed(spaces),
       channels = _sealed(channels),
       members = _sealed(members),
       _held = held,
       roles = _sealed(roles),
       categories = _sealed(categories),
       emojis = _sealed(emojis),
       stickers = _sealed(stickers);

  /// Seals [items] against change, and hands back a list already sealed by an
  /// earlier workspace as it stands.
  ///
  /// Every change to a workspace rebuilds it through [copyWith], which passes
  /// the seven collections it did not touch straight back. Copying those again
  /// meant one arriving message copied every message, member and channel the
  /// client held. Reusing the sealed list also keeps its identity stable, which
  /// is what lets anything downstream tell "the same channels as last time"
  /// from "a new set of channels".
  static List<T> _sealed<T>(List<T> items) => items is UnmodifiableListView<T>
      ? items
      : UnmodifiableListView(List.of(items, growable: false));

  final List<CommunitySpace> spaces;
  final List<ConversationChannel> channels;
  final List<Member> members;
  final _HeldMessages _held;
  final List<CommunityRole> roles;
  final List<ChannelCategory> categories;
  final List<GuildEmoji> emojis;
  final List<GuildSticker> stickers;
  final String currentMemberId;

  /// Every message the workspace holds, oldest first. The first read after a
  /// change builds it from all channels, so code on the chat path reads
  /// [messagesFor] instead.
  List<ChatMessage> get messages => _held.flat;

  /// Lookup tables over the lists above.
  ///
  /// Scanning a list per lookup costs a full pass, which an account with a
  /// couple of hundred spaces pays thousands of times per frame, so each table
  /// is built on first use and answers every later lookup in constant time.
  ///
  /// Each table is remembered against the list it was built from, not against
  /// the workspace, so workspaces that share a list share its table. That is
  /// the usual case: a change rebuilds the workspace but leaves the lists it
  /// did not touch as they were, and a presence arriving from one of a couple
  /// of hundred spaces leaves every channel and category where it was.
  static final _spaceTables = Expando<Map<String, CommunitySpace>>();
  static final _channelTables = Expando<Map<String, ConversationChannel>>();
  static final _memberTables = Expando<Map<String, Member>>();
  static final _roleTables = Expando<Map<String, CommunityRole>>();
  static final _categoryTables = Expando<Map<String, ChannelCategory>>();
  static final _channelsBySpaceTables =
      Expando<Map<String, List<ConversationChannel>>>();
  static final _categoriesBySpaceTables =
      Expando<Map<String, List<ChannelCategory>>>();

  Map<String, CommunitySpace> get _spaceById =>
      _spaceTables[spaces] ??= _byId(spaces, (space) => space.id);
  Map<String, ConversationChannel> get _channelById =>
      _channelTables[channels] ??= _byId(channels, (channel) => channel.id);
  Map<String, Member> get _memberById =>
      _memberTables[members] ??= _byId(members, (member) => member.id);
  Map<String, CommunityRole> get _roleById =>
      _roleTables[roles] ??= _byId(roles, (role) => role.id);
  Map<String, ChannelCategory> get _categoryById =>
      _categoryTables[categories] ??= _byId(
        categories,
        (category) => category.id,
      );
  Map<String, List<ConversationChannel>> get _channelsBySpaceId =>
      _channelsBySpaceTables[channels] ??= _groupBy(
        channels,
        (channel) => channel.spaceId,
      );
  Map<String, List<ChannelCategory>> get _categoriesBySpaceId =>
      _categoriesBySpaceTables[categories] ??= _groupBy(
        categories,
        (category) => category.spaceId,
      );

  static Map<String, T> _byId<T>(List<T> items, String Function(T item) idOf) =>
      {for (final item in items) idOf(item): item};

  static Map<String, List<T>> _groupBy<T>(
    List<T> items,
    String Function(T item) keyOf,
  ) {
    final grouped = <String, List<T>>{};
    for (final item in items) {
      grouped.putIfAbsent(keyOf(item), () => <T>[]).add(item);
    }
    return {
      for (final entry in grouped.entries)
        entry.key: List.unmodifiable(entry.value),
    };
  }

  /// Hands out the group itself rather than a copy of it.
  ///
  /// A lookup runs several times per frame, so copying it made every one of
  /// those cost the length of the channel. The group cannot be written to, so
  /// sharing it is safe, and the same list coming back each time is what lets
  /// a caller tell an unchanged channel by identity.
  static List<T> _group<T>(Map<String, List<T>> groups, String key) =>
      groups[key] ?? const [];

  List<ConversationChannel> channelsFor(String spaceId) =>
      _group(_channelsBySpaceId, spaceId);

  List<ChatMessage> messagesFor(String channelId) => _held.of(channelId);

  List<ChannelCategory> categoriesFor(String spaceId) =>
      _group(_categoriesBySpaceId, spaceId);

  CommunitySpace spaceById(String id) => _spaceById[id]!;

  ConversationChannel channelById(String id) => _channelById[id]!;

  Member memberById(String id) => _memberById[id]!;

  Member? memberOrNull(String id) => _memberById[id];

  ConversationChannel? channelOrNull(String id) => _channelById[id];

  CommunityRole? roleOrNull(String id) => _roleById[id];

  CommunitySpace? spaceOrNull(String id) => _spaceById[id];

  ChannelCategory? categoryOrNull(String id) => _categoryById[id];

  ChatWorkspace copyWith({
    List<CommunitySpace>? spaces,
    List<ConversationChannel>? channels,
    List<Member>? members,
    List<ChatMessage>? messages,
    List<CommunityRole>? roles,
    List<ChannelCategory>? categories,
    List<GuildEmoji>? emojis,
    List<GuildSticker>? stickers,
    String? currentMemberId,
  }) => _copy(
    spaces: spaces,
    channels: channels,
    members: members,
    held: messages == null ? null : _HeldMessages.of(messages),
    roles: roles,
    categories: categories,
    emojis: emojis,
    stickers: stickers,
    currentMemberId: currentMemberId,
  );

  /// [copyWith] for the folds in this file. It takes the stored messages as they
  /// are, where [copyWith] takes a flat list and has to group it.
  ChatWorkspace _copy({
    List<CommunitySpace>? spaces,
    List<ConversationChannel>? channels,
    List<Member>? members,
    _HeldMessages? held,
    List<CommunityRole>? roles,
    List<ChannelCategory>? categories,
    List<GuildEmoji>? emojis,
    List<GuildSticker>? stickers,
    String? currentMemberId,
  }) => ChatWorkspace._(
    spaces: spaces ?? this.spaces,
    channels: channels ?? this.channels,
    members: members ?? this.members,
    held: held ?? _held,
    roles: roles ?? this.roles,
    categories: categories ?? this.categories,
    emojis: emojis ?? this.emojis,
    stickers: stickers ?? this.stickers,
    currentMemberId: currentMemberId ?? this.currentMemberId,
  );

  ChatWorkspace retainDirectMessagesFrom(ChatWorkspace? cached) {
    if (cached == null || cached.currentMemberId != currentMemberId) {
      return this;
    }
    final directSpaceIds = cached.spaces
        .where((space) => space.isDirectMessages)
        .map((space) => space.id)
        .toSet();
    final directChannels = cached.channels
        .where((channel) => directSpaceIds.contains(channel.spaceId))
        .toList();
    final directChannelIds = directChannels
        .map((channel) => channel.id)
        .toSet();
    final directMemberIds = <String>{
      currentMemberId,
      for (final channel in directChannels) ?channel.recipientId,
      for (final channelId in directChannelIds)
        for (final message in cached.messagesFor(channelId)) message.authorId,
    };
    final memberMap = {for (final member in members) member.id: member};
    for (final member in cached.members) {
      if (directMemberIds.contains(member.id)) {
        memberMap[member.id] = _mergeMember(
          member,
          memberMap[member.id] ?? member,
        );
      }
    }
    return _copy(
      spaces:
          [
                ...spaces.where((space) => space.isDirectMessages),
                ...cached.spaces.where((space) => space.isDirectMessages),
                ...spaces.where((space) => !space.isDirectMessages),
              ]
              .fold(<String, CommunitySpace>{}, (map, space) {
                map[space.id] = space;
                return map;
              })
              .values
              .toList(),
      channels: [
        ...directChannels,
        ...channels.where((channel) => !directChannelIds.contains(channel.id)),
      ],
      members: memberMap.values.toList(),
      held: _held.withChannelsOf(cached._held, directChannelIds),
    );
  }

  ChatWorkspace restoreChannelActivityFrom(ChatWorkspace? cached) {
    if (cached == null || cached.currentMemberId != currentMemberId) {
      return this;
    }
    final cachedChannels = {
      for (final channel in cached.channels) channel.id: channel,
    };
    return copyWith(
      channels: [
        for (final channel in channels)
          channel.withActivityOf(cachedChannels[channel.id] ?? channel),
      ],
    );
  }

  ChatWorkspace mergeHistory(
    ChannelHistory history, {
    bool replaceChannel = true,
  }) {
    final memberMap = {for (final member in members) member.id: member};
    for (final member in history.members) {
      memberMap[member.id] = _mergeMember(memberMap[member.id], member);
    }
    return _copy(
      members: memberMap.values.toList(),
      held: _held.merge(
        history.channelId,
        history.messages,
        replace: replaceChannel,
      ),
    );
  }

  ChatWorkspace mergeInitialHistory(
    ChannelHistory history, {
    bool retainExisting = false,
  }) => mergeHistory(
    history,
    replaceChannel:
        !retainExisting &&
        channelById(history.channelId).firstUnreadMessageId == null,
  );

  ChatWorkspace upsertMessage(ChatMessage message, {Member? member}) {
    final nextMembers = member == null
        ? members
        : _mergeMemberInto(members, member);
    // Unread is decided by comparing this pointer against the read state's ack
    // cursor, so a message that arrives without advancing it would be invisible
    // to every unread surface until the next gateway channel update.
    return _copy(
      held: _held.upsert(message),
      members: nextMembers,
    ).recordLatestMessage(message.channelId, message.id);
  }

  /// Keeps only the newest [notOpenChannelCap] messages of [channelId]. Answers
  /// this same workspace when the channel holds no more than that, so a caller
  /// can tell whether the channel lost anything.
  ///
  /// An unread boundary on a dropped message moves to the oldest message kept,
  /// so the channel still opens on its NEW line.
  ChatWorkspace capChannel(String channelId) {
    final held = _held.capped(channelId, notOpenChannelCap);
    if (identical(held, _held)) return this;
    final capped = _copy(held: held);
    final kept = held.of(channelId);
    final boundary = channelOrNull(channelId)?.firstUnreadMessageId;
    if (boundary == null || kept.any((message) => message.id == boundary)) {
      return capped;
    }
    return capped.updateChannel(
      channelId,
      (channel) => channel.copyWith(firstUnreadMessageId: kept.first.id),
    );
  }

  /// Records [messageId] as the newest message in [channelId].
  ChatWorkspace recordLatestMessage(String channelId, String messageId) =>
      updateChannel(
        channelId,
        (channel) => channel.withLatestMessage(messageId),
      );

  ChatWorkspace upsertMember(Member member) =>
      copyWith(members: _mergeMemberInto(members, member));

  /// Folds a batch of members in with one pass over the member table.
  ///
  /// A member-list page carries up to a hundred members at once; upserting
  /// them one at a time would rebuild the whole table per member and turn a
  /// single roster page into quadratic work.
  ChatWorkspace upsertMembers(Iterable<Member> incoming) {
    if (incoming.isEmpty) return this;
    final merged = <String, Member>{
      for (final member in members) member.id: member,
    };
    for (final member in incoming) {
      merged[member.id] = _mergeMember(merged[member.id], member);
    }
    return copyWith(members: merged.values.toList(growable: false));
  }

  ChatWorkspace upsertSpace(CommunitySpace space) =>
      copyWith(spaces: _withSpace(space));

  /// [spaces] with [space] in place of its earlier copy, so a server keeps its
  /// place on the rail when it changes. A new one goes last.
  List<CommunitySpace> _withSpace(CommunitySpace space) =>
      spaceOrNull(space.id) == null
      ? [...spaces, space]
      : [
          for (final existing in spaces)
            existing.id == space.id ? space : existing,
        ];

  ChatWorkspace upsertCategory(ChannelCategory category) => copyWith(
    categories: [
      ...categories.where((existing) => existing.id != category.id),
      category,
    ],
  );

  /// Folds one gained guild in, whole: space, channels, categories, roles and
  /// the members the join learned about.
  ///
  /// Joining must fill the rail and the channel tree without a restart, so
  /// this is the one fold that touches every collection at once. Each piece
  /// replaces anything the workspace already held under the same id, so a
  /// hydration answer that arrives twice lands the same as one that arrives
  /// once. A channel it already held keeps its unread state, because
  /// `GUILD_CREATE` also arrives for a server the account is already in.
  ChatWorkspace mergeGuild(JoinedGuild guild) => copyWith(
    spaces: _withSpace(guild.space),
    channels: [
      ...channels.where((channel) => channel.spaceId != guild.space.id),
      for (final channel in guild.channels)
        channel.withActivityOf(channelOrNull(channel.id) ?? channel),
    ],
    categories: [
      ...categories.where((category) => category.spaceId != guild.space.id),
      ...guild.categories,
    ],
    roles: [
      ...roles.where((role) => role.spaceId != guild.space.id),
      ...guild.roles,
    ],
    members: _withSpaceIds(members, guild),
  );

  /// Merges [guild]'s members into [current], adding the guild to every
  /// member it names. The member merge follows [upsertMembers], so a member
  /// the join introduces keeps the spaces and presences the workspace
  /// already knew them under.
  static List<Member> _withSpaceIds(List<Member> current, JoinedGuild guild) {
    if (guild.members.isEmpty) return current;
    final merged = {for (final member in current) member.id: member};
    for (final member in guild.members) {
      merged[member.id] = _mergeMember(merged[member.id], member);
    }
    return merged.values.toList(growable: false);
  }

  /// Drops one guild whole: the space, its channels, categories, roles, the
  /// messages those channels held, and the guild from every member's record.
  ///
  /// Leaving a server must leave no trace on the rail, and a cached member
  /// whose membership outlived the guild would rehydrate a permission record
  /// for a server the account cannot open, so the membership is dropped here
  /// too.
  ChatWorkspace removeGuild(String spaceId) {
    final channelIds = {
      for (final channel in channels)
        if (channel.spaceId == spaceId) channel.id,
    };
    return _copy(
      spaces: spaces.where((space) => space.id != spaceId).toList(),
      channels: channels
          .where((channel) => channel.spaceId != spaceId)
          .toList(),
      categories: categories
          .where((category) => category.spaceId != spaceId)
          .toList(),
      roles: roles.where((role) => role.spaceId != spaceId).toList(),
      members: [for (final member in members) ?member.withoutSpace(spaceId)],
      held: _held.withoutChannels(channelIds),
    );
  }

  ChatWorkspace removeCategory(String categoryId) => copyWith(
    categories: categories
        .where((category) => category.id != categoryId)
        .toList(),
  );

  /// Applies a gateway presence to the member it names.
  ///
  /// A presence for somebody the member table has never heard of is dropped
  /// rather than turned into a nameless row: Discord streams presence for
  /// friends and for every subscribed guild, so an unmatched id is routine.
  ChatWorkspace applyPresence(String memberId, UserPresence presence) =>
      copyWith(
        members: [
          for (final member in members)
            member.id == memberId ? member.withPresence(presence) : member,
        ],
      );

  /// Applies a batch of presences with one pass over the member table.
  ///
  /// `READY_SUPPLEMENTAL` alone carries a presence for every online friend and
  /// every subscribed guild member, and folding them in one at a time would
  /// rebuild the table once per presence.
  ChatWorkspace applyPresences(Map<String, UserPresence> presences) {
    if (presences.isEmpty) return this;
    var touched = false;
    final next = <Member>[];
    for (final member in members) {
      final presence = presences[member.id];
      if (presence == null) {
        next.add(member);
        continue;
      }
      touched = true;
      next.add(member.withPresence(presence));
    }
    return touched ? copyWith(members: next) : this;
  }

  ChatWorkspace removeMemberFromSpace(String memberId, String spaceId) {
    final next = <Member>[];
    for (final member in members) {
      if (member.id != memberId) {
        next.add(member);
        continue;
      }
      final without = member.withoutSpace(spaceId);
      if (without != null) next.add(without);
    }
    return copyWith(members: next);
  }

  ChatWorkspace markChannelRead(String channelId) =>
      updateChannel(channelId, (channel) => channel.markRead());

  ChatWorkspace clearChannelUnreadBoundary(String channelId) =>
      updateChannel(channelId, (channel) => channel.clearUnreadBoundary());

  ChatWorkspace markChannelUnread(
    String channelId, {
    required String messageId,
    required bool mention,
  }) => updateChannel(
    channelId,
    (channel) => channel.markUnread(messageId: messageId, mention: mention),
  );

  ChatWorkspace updateChannel(
    String channelId,
    ConversationChannel Function(ConversationChannel channel) update,
  ) => copyWith(
    channels: [
      for (final channel in channels)
        channel.id == channelId ? update(channel) : channel,
    ],
  );

  /// Replaces a held message with [update]'s answer. It stays where it is in its
  /// channel, and a message that is not held is left out.
  ChatWorkspace updateMessage(
    String messageId,
    ChatMessage Function(ChatMessage message) update,
  ) {
    final held = _held.update(messageId, update);
    return identical(held, _held) ? this : _copy(held: held);
  }

  ChatWorkspace removeMessage(String messageId) => removeMessages({messageId});

  ChatWorkspace removeMessages(Set<String> messageIds) => _copy(
    held: _held.without(messageIds),
    channels: [
      for (final channel in channels)
        messageIds.contains(channel.firstUnreadMessageId)
            ? channel.clearUnreadBoundary()
            : channel,
    ],
  );

  /// A channel the workspace holds keeps its place and its unread state. A new
  /// DM is the newest conversation, so it goes first in the list.
  ChatWorkspace upsertChannel(ConversationChannel channel) {
    final previous = channelOrNull(channel.id);
    if (previous == null) {
      return copyWith(
        channels: channel.isDirectMessage
            ? [channel, ...channels]
            : [...channels, channel],
      );
    }
    final next = channel.withActivityOf(previous);
    return copyWith(
      channels: [
        for (final existing in channels)
          existing.id == channel.id ? next : existing,
      ],
    );
  }

  ChatWorkspace removeChannel(String channelId) {
    final nextChannels = channels
        .where((channel) => channel.id != channelId)
        .toList();
    return _copy(
      channels: nextChannels,
      held: _held.withoutChannels({channelId}),
    );
  }

  static List<Member> _mergeMemberInto(List<Member> current, Member incoming) {
    final existing = current.where((member) => member.id == incoming.id);
    if (existing.isEmpty) return [...current, incoming];
    final merged = _mergeMember(existing.first, incoming);
    return [...current.where((member) => member.id != incoming.id), merged];
  }

  static Member _mergeMember(Member? previous, Member incoming) {
    if (previous == null) return incoming;
    return incoming.copyWith(
      spaceIds: {...previous.spaceIds, ...incoming.spaceIds},
      rolesBySpace: {...previous.rolesBySpace, ...incoming.rolesBySpace},
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
      // A member payload carries no presence, so the mapper defaults it to
      // offline; letting that erase a presence the gateway already reported
      // would blank out every activity the moment the member is re-mapped.
      presenceDetail: incoming.presenceDetail ?? previous.presenceDetail,
    );
  }
}

final class ChannelHistory {
  ChannelHistory({
    required this.channelId,
    required List<ChatMessage> messages,
    required List<Member> members,
  }) : messages = List.unmodifiable(messages),
       members = List.unmodifiable(members);

  final String channelId;
  final List<ChatMessage> messages;
  final List<Member> members;
}

final class ChannelHistoryPage {
  const ChannelHistoryPage({required this.history, required this.hasMore});

  final ChannelHistory history;
  final bool hasMore;
}

/// One gained guild, hydrated the way a user reads it on the rail.
///
/// Joining and creating both answer with the whole server: the space itself,
/// its channels, categories, roles, and the members the transport learned.
/// That is what lets the rail and the channel tree fill without a restart.
final class JoinedGuild {
  const JoinedGuild({
    required this.space,
    required this.channels,
    required this.categories,
    required this.roles,
    this.members = const [],
  });

  final CommunitySpace space;
  final List<ConversationChannel> channels;
  final List<ChannelCategory> categories;

  /// The guild's roles, permission bits included, which is what lets the
  /// channel tree answer visibility questions at once.
  final List<CommunityRole> roles;

  /// Members the answer learned about. On the desktop transport that is
  /// normally just this account's own membership, which is exactly what the
  /// permission model needs.
  final List<Member> members;
}
