import 'dart:async';
import 'package:flucord/src/domain/user_profile.dart';

import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_management_repository.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flucord/src/domain/message_search_repository.dart';
import 'package:flucord/src/domain/moderation_repository.dart';
import 'package:flucord/src/domain/permission_overwrite.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flucord/src/domain/read_state.dart';
import 'package:flucord/src/domain/read_state_repository.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flutter_test/flutter_test.dart';

part 'chat_controller_read_state_unread_cases.dart';
part 'chat_controller_read_state_command_cases.dart';

const _guildId = '111111111111111111';
const _generalId = '222222222222222222';
const _hiddenId = '333333333333333333';
const _memberId = '987654321098765432';
const _olderMessage = '123456789012345678';
const _newerMessage = '234567890123456789';

/// The fixture snowflake pool is a short allow-list, so this literal does
/// double duty: here it is the other participant, elsewhere the older message.
const _authorId = '123456789012345678';

void main() {
  _unreadCases();
  _commandCases();
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final class _FakeReadStateRepository implements ReadStateRepository {
  _FakeReadStateRepository({this.failing = false});

  final bool failing;
  final StreamController<ReadStateSnapshot> _updates =
      StreamController.broadcast();

  final List<(String, String)> acknowledged = [];
  final List<(String, String, int)> unread = [];
  final List<(String, List<String>)> spaceReads = [];
  final List<(String, GuildNotificationSettingsPatch)> spacePatches = [];
  final List<(String, String, ChannelNotificationOverridePatch)> overrides = [];

  ReadStateSnapshot _current = ReadStateSnapshot.empty;

  void publish(ReadStateSnapshot snapshot) {
    _current = snapshot;
    _updates.add(snapshot);
  }

  @override
  Stream<ReadStateSnapshot> get updates => _updates.stream;

  @override
  ReadStateSnapshot get current => _current;

  @override
  Future<void> acknowledge(
    ConversationChannel channel, {
    required String messageId,
    bool immediate = false,
  }) async {
    _refuseWhenFailing();
    acknowledged.add((channel.id, messageId));
  }

  @override
  Future<void> markUnread(
    ConversationChannel channel, {
    required String messageId,
    int mentionCount = 0,
  }) async {
    _refuseWhenFailing();
    unread.add((channel.id, messageId, mentionCount));
  }

  @override
  Future<void> markSpaceRead(
    String spaceId,
    Iterable<ConversationChannel> channels,
  ) async {
    _refuseWhenFailing();
    spaceReads.add((
      spaceId,
      channels.map((channel) => channel.id).toList(growable: false),
    ));
  }

  @override
  Future<void> updateSpaceNotificationSettings(
    String spaceId,
    GuildNotificationSettingsPatch patch,
  ) async {
    _refuseWhenFailing();
    spacePatches.add((spaceId, patch));
  }

  @override
  Future<void> updateChannelNotificationOverride({
    required String spaceId,
    required String channelId,
    required ChannelNotificationOverridePatch patch,
  }) async {
    _refuseWhenFailing();
    overrides.add((spaceId, channelId, patch));
  }

  @override
  Future<void> flush() async {}

  void _refuseWhenFailing() {
    if (failing) throw StateError('read state is unavailable');
  }
}

final class _Repository implements ChatRepository {
  @override
  UserProfileRepository? get userProfile => null;

  _Repository({
    bool failing = false,
    this.withReadState = true,
    this.channelLastMessageId = _newerMessage,
  }) : readStateStore = _FakeReadStateRepository(failing: failing);

  final _FakeReadStateRepository readStateStore;
  final bool withReadState;
  final String channelLastMessageId;
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();

  void emit(ChatRepositoryEvent event) => _events.add(event);

  @override
  Stream<ChatRepositoryEvent> get events => _events.stream;

  @override
  ReadStateRepository? get readState => withReadState ? readStateStore : null;

  @override
  VoiceSignalingService? get voiceSignaling => null;

  @override
  UserSettingsRepository? get userSettings => null;

  @override
  DirectCallService? get directCalls => null;

  // Nothing but read state is wired up here: this fake exists to drive the
  // unread boundary, and a capability it cannot serve says so rather than
  // handing back a plane whose every call would fail.
  @override
  GuildManagementRepository? get guildManagement => null;

  @override
  ModerationRepository? get moderation => null;

  @override
  MessageSearchRepository? get messageSearch => null;

  @override
  PresenceService? get presence => null;

  @override
  Future<ChatWorkspace> loadWorkspace() async =>
      _workspace(channelLastMessageId);

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
  }) async => ChannelHistoryPage(
    // The seeded messages come back so that opening a channel does not wipe
    // the very history these tests measure the unread boundary against.
    history: ChannelHistory(
      channelId: channelId,
      messages: _workspace(channelLastMessageId).messagesFor(channelId),
      members: const [],
    ),
    hasMore: false,
  );

  @override
  Future<ChannelHistory> loadPinnedMessages(String channelId) async =>
      ChannelHistory(
        channelId: channelId,
        messages: const [],
        members: const [],
      );

  @override
  Future<DirectConversation> openDirectConversation(String recipientId) =>
      throw UnimplementedError();

  @override
  Future<ConversationChannel> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) => throw UnimplementedError();

  @override
  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    bool suppressNotifications = false,
  }) => throw UnimplementedError();

  @override
  Future<ChatMessage> editMessage({
    required String channelId,
    required String messageId,
    required String body,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) async {}

  @override
  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) async {}

  @override
  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) async {}

  @override
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) async {}

  @override
  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  }) async {}

  @override
  Future<void> startTyping(String channelId) async {}

  @override
  Future<void> saveChannelActivity(ConversationChannel channel) async {}

  @override
  Future<void> close() async {
    await _events.close();
  }
}

ChatWorkspace _workspace(String channelLastMessageId) => ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: _guildId,
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  roles: [
    CommunityRole(
      id: _guildId,
      spaceId: _guildId,
      name: '@everyone',
      position: 0,
      permissions: DiscordPermissions.viewChannel,
    ),
  ],
  channels: [
    ConversationChannel(
      id: _generalId,
      spaceId: _guildId,
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
      lastMessageId: channelLastMessageId,
    ),
    ConversationChannel(
      id: _hiddenId,
      spaceId: _guildId,
      name: 'staff',
      topic: '',
      kind: ChannelKind.text,
      position: 1,
      lastMessageId: channelLastMessageId,
      permissionOverwrites: {
        _guildId: DiscordPermissionOverwrite(
          id: _guildId,
          kind: PermissionOverwriteKind.role,
          allow: DiscordPermissions.none,
          deny: DiscordPermissions.viewChannel,
        ),
      },
    ),
  ],
  members: const [
    Member(
      id: _memberId,
      displayName: 'Flucord',
      initials: 'FL',
      role: 'Bot',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      spaceIds: {_guildId},
      membershipsBySpace: {_guildId: GuildMembership()},
    ),
  ],
  messages: [
    ChatMessage(
      id: _olderMessage,
      channelId: _generalId,
      authorId: _authorId,
      body: 'read',
      sentAt: DateTime.utc(2026, 7, 20),
    ),
    if (channelLastMessageId == _newerMessage)
      ChatMessage(
        id: _newerMessage,
        channelId: _generalId,
        authorId: _authorId,
        body: 'unread',
        sentAt: DateTime.utc(2026, 7, 21),
      ),
  ],
  currentMemberId: _memberId,
);
