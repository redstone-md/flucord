import 'dart:async';

import '../../domain/chat_models.dart';
import '../../domain/read_state.dart';
import '../../domain/read_state_repository.dart';
import 'discord_desktop_rest_protocol.dart';
import 'discord_read_state_ack_queue.dart';
import 'discord_read_state_codec.dart';
import 'discord_read_state_store.dart';
import 'discord_rest_client.dart';

/// The REST calls the read-state repository needs, and nothing else.
///
/// Narrow on purpose: this is the whole surface a fake has to implement, so
/// the acknowledgement rules can be tested without an HTTP client anywhere in
/// sight.
abstract interface class DiscordReadStateTransport {
  Future<Map<String, Object?>?> sendReadStateRequest(
    DiscordDesktopRestRequest request,
  );
}

/// Server-owned read state for the desktop-user session.
///
/// The division of labour is the point: [DiscordReadStateStore] decides what is
/// true, [DiscordReadStateAckQueue] decides what leaves the machine and when,
/// and this class is the seam between them — every mutation is applied locally
/// first so the sidebar reacts to the click rather than to the round trip, and
/// then sent.
final class DiscordReadStateRepository implements ReadStateRepository {
  DiscordReadStateRepository(
    DiscordReadStateTransport transport, {
    DelayFunction? delay,
    Duration? ackDebounce,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _queue = DiscordReadStateAckQueue(
         send: transport.sendReadStateRequest,
         delay: delay,
         debounce: ackDebounce ?? const Duration(seconds: 3),
       );

  final DiscordReadStateStore _store = DiscordReadStateStore();
  final DiscordReadStateAckQueue _queue;
  final DateTime Function() _clock;
  final StreamController<ReadStateSnapshot> _updates =
      StreamController.broadcast();

  Set<String> _privateChannelIds = const {};
  ReadStateSnapshot _snapshot = ReadStateSnapshot.empty;

  @override
  Stream<ReadStateSnapshot> get updates => _updates.stream;

  @override
  ReadStateSnapshot get current => _snapshot;

  /// The rolling ACK token, exposed for diagnostics and tests only.
  String? get ackToken => _queue.token;

  /// R03/R09: the largest ack cursor across every read state.
  ///
  /// IDENTIFY echoes it back as `highest_last_message_id` so the server can
  /// answer a reconnect with a delta instead of the whole read-state block.
  /// The read-state store folds both shapes: a `partial: true` block merges,
  /// a full one replaces.
  String get highestLastMessageId => _snapshot.highestLastMessageId;

  /// R09: the same maximum over private-channel read states only.
  String get privateChannelsVersion =>
      _snapshot.privateChannelsVersion(_privateChannelIds);

  /// The `client_state` block a re-IDENTIFY should carry.
  ///
  /// The negotiated contract has the account echo the four versions its caches
  /// can vouch for: the two counters, and the two snowflake cursors over all
  /// and over private channels. The store can apply every delta those unlock.
  /// R03: a client that cannot vouch for its cache collapses the block to
  /// `guild_versions` alone, which is exactly the position we are in before the
  /// first `READY`.
  Map<String, Object?> identifyClientState() {
    final snapshot = _snapshot;
    if (snapshot.readStateVersion <= 0 &&
        snapshot.userGuildSettingsVersion <= 0) {
      return const {'guild_versions': <String, Object?>{}};
    }
    final highest = snapshot.highestLastMessageId;
    final privateChannels = _snapshot.privateChannelsVersion(
      _privateChannelIds,
    );
    return {
      'guild_versions': const <String, Object?>{},
      if (snapshot.readStateVersion > 0)
        'read_state_version': snapshot.readStateVersion,
      if (snapshot.userGuildSettingsVersion > 0)
        'user_guild_settings_version': snapshot.userGuildSettingsVersion,
      // "0" is the wire's way of saying "nothing acked"; echoing it would
      // vouch for a cursor the account never reached.
      if (highest != '0') 'highest_last_message_id': highest,
      if (privateChannels != '0') 'private_channels_version': privateChannels,
    };
  }

  /// Tells the store which channels are direct messages, for
  /// [privateChannelsVersion].
  void setPrivateChannelIds(Iterable<String> ids) =>
      _privateChannelIds = Set.unmodifiable(ids.toSet());

  /// Rebinds the account this store belongs to, resetting the ack token.
  void setCurrentUserId(String? userId) => _queue.bindSession(userId);

  /// Feeds one gateway dispatch in.
  void acceptGatewayDispatch(String name, Map<String, Object?> data) {
    if (name == 'MESSAGE_ACK' && data['manual'] == true) {
      final channelId = data['channel_id'];
      // Another session deliberately rewound this channel. A debounced ack of
      // ours would undo that the moment its timer fired.
      if (channelId is String) _queue.cancel(channelId);
    }
    if (_store.accept(name, data)) _emit();
  }

  /// Folds the read-state entries one guild carries, as a join's hydration
  /// step.
  ///
  /// The desktop route answers the same block a `READY.read_state` does, so
  /// the same fold runs over it: the guild's channels keep the cursors the
  /// account had before it joined here. A block that arrives without a
  /// version is a delta either way, and one that fails to arrive is not a
  /// failed join.
  Future<void> hydrateReadState(String guildId) async {
    if (guildId.trim().isEmpty || int.tryParse(guildId.trim()) == null) {
      return;
    }
    final payload = await _queue.sendForPayload(
      DiscordDesktopRestRequest(
        method: 'GET',
        path: '/guilds/${guildId.trim()}/read-state',
      ),
    );
    if (payload == null) return;
    final block = payload['read_state'];
    if (block is! Map) return;
    final envelope = block.cast<String, Object?>();
    final changed = _store.accept('STATE_UPDATE', {'read_state': envelope});
    if (changed) _emit();
  }

  @override
  Future<void> acknowledge(
    ConversationChannel channel, {
    required String messageId,
    bool immediate = false,
  }) async {
    final previous = _store.channelState(channel.id);
    final lastViewed = readStateLastViewedFor(_clock());
    final flags = ReadStateFlags.forChannel(channel);
    final moved = previous.isBehind(messageId);
    // R04's only reason to ack a channel that is already read is a changed
    // day counter, so a repeat visit on the same day sends nothing at all.
    if (!moved && lastViewed == previous.lastViewed) return;
    _store.put(
      previous
          .acknowledged(messageId, lastViewed: lastViewed)
          .copyWith(flags: flags),
    );
    _emit();
    _queue.schedule(
      DiscordPendingAck(
        channelId: channel.id,
        messageId: messageId,
        lastViewed: lastViewed,
        // R04: the field is sent only when the recomputed value differs from
        // the one the read state already carries.
        flags: flags == previous.flags ? null : flags,
      ),
      immediate: immediate || previous.hasMentions,
    );
  }

  @override
  Future<void> markUnread(
    ConversationChannel channel, {
    required String messageId,
    int mentionCount = 0,
  }) async {
    _queue.cancel(channel.id);
    _store.put(
      _store
          .channelState(channel.id)
          .copyWith(
            lastAckedId: messageId,
            mentionCount: mentionCount < 0 ? 0 : mentionCount,
          ),
    );
    _emit();
    await _queue.sendNow(
      DiscordDesktopReadStateRequests.markUnread(
        channelId: channel.id,
        messageId: messageId,
        mentionCount: mentionCount < 0 ? 0 : mentionCount,
      ),
    );
  }

  @override
  Future<void> markSpaceRead(
    String spaceId,
    Iterable<ConversationChannel> channels,
  ) async {
    final entries = <Map<String, Object?>>[];
    for (final channel in channels) {
      if (channel.spaceId != spaceId) continue;
      final lastMessageId = channel.lastMessageId;
      if (lastMessageId == null) continue;
      final state = _store.channelState(channel.id);
      if (!state.isBehind(lastMessageId) && !state.hasMentions) continue;
      _queue.cancel(channel.id);
      _store.put(state.acknowledged(lastMessageId).copyWith(mentionCount: 0));
      entries.add({
        'channel_id': channel.id,
        'message_id': lastMessageId,
        'read_state_type': ReadStateType.channel.wireValue,
      });
    }
    if (entries.isNotEmpty) {
      _emit();
      _queue.enqueueBulk(entries);
    }
    if (spaceId == CommunitySpace.directMessagesId) return;
    // R04 folds a guild's scheduled events and onboarding questions into the
    // same "mark as read". Their dedicated ack route is used rather than a
    // synthetic bulk entry, because the bulk entry's `message_id` for a
    // non-channel type is not something the corpus establishes.
    for (final type in const [
      ReadStateType.guildEvent,
      ReadStateType.guildOnboardingQuestion,
    ]) {
      // Only ack what is actually unread. Firing both routes unconditionally
      // meant marking a guild read cost two requests whatever its state, and
      // marking every guild read multiplied that by the guild count.
      final existing = _store.entityState(type, spaceId);
      if (existing.lastAckedId == spaceId && existing.mentionCount == 0) {
        continue;
      }
      _store.put(
        _store
            .entityState(type, spaceId)
            .copyWith(lastAckedId: spaceId, mentionCount: 0),
      );
      unawaited(
        _queue
            .sendNow(
              DiscordDesktopReadStateRequests.ackGuildEntity(
                guildId: spaceId,
                readStateType: type.wireValue,
                entityId: spaceId,
              ),
            )
            .catchError((_) {}),
      );
    }
    _emit();
  }

  @override
  Future<void> acknowledgeMessageRequest(String channelId) =>
      _acknowledgeUserEntity(
        type: ReadStateType.messageRequests,
        entityId: channelId,
      );

  @override
  Future<void> acknowledgeNotificationCentre(String spaceId) =>
      _acknowledgeUserEntity(
        type: ReadStateType.notificationCenter,
        entityId: spaceId,
      );

  /// The account-scoped ack: optimistic locally, then the one request the
  /// route carries. The acked id is the entity itself, which is what a
  /// `USER_NON_CHANNEL_ACK` from another session carries back.
  Future<void> _acknowledgeUserEntity({
    required ReadStateType type,
    required String entityId,
  }) async {
    _store.put(
      _store
          .entityState(type, entityId)
          .copyWith(lastAckedId: entityId, mentionCount: 0),
    );
    _emit();
    await _queue.sendNow(
      DiscordDesktopReadStateRequests.ackUserEntity(
        readStateType: type.wireValue,
        entityId: entityId,
      ),
    );
  }

  @override
  Future<void> collectGarbage({DateTime? now}) async {
    final channelIds = ReadStateCollector.collectableChannelIds(
      _store.snapshot,
      now ?? _clock(),
    );
    for (final channelId in channelIds) {
      // The local pass goes first so the cache shrinks on the same stroke
      // whether or not the request lands; a failed delete is re-read from the
      // next READY, which is how every other optimistic mutation behaves.
      _store.removeChannelState(channelId);
      await _queue.sendNow(
        DiscordDesktopReadStateRequests.deleteReadState(
          channelId: channelId,
          readStateType: ReadStateType.channel.wireValue,
        ),
      );
    }
    if (channelIds.isNotEmpty) _emit();
  }

  @override
  Future<void> updateSpaceNotificationSettings(
    String spaceId,
    GuildNotificationSettingsPatch patch,
  ) async {
    if (patch.isEmpty) return;
    _store.putSettings(
      DiscordReadStateCodec.applyGuildPatch(_store.settingsFor(spaceId), patch),
    );
    _emit();
    await _patchSettings(
      spaceId,
      DiscordReadStateCodec.guildSettingsBody(patch),
    );
  }

  @override
  Future<void> updateChannelNotificationOverride({
    required String spaceId,
    required String channelId,
    required ChannelNotificationOverridePatch patch,
  }) async {
    if (patch.isEmpty) return;
    final settings = _store.settingsFor(spaceId);
    _store.putSettings(
      settings.withOverride(
        channelId,
        DiscordReadStateCodec.applyOverridePatch(
          settings.overrideFor(channelId) ??
              ChannelNotificationOverride(channelId: channelId),
          patch,
        ),
      ),
    );
    _emit();
    await _patchSettings(spaceId, {
      'channel_overrides': {
        channelId: DiscordReadStateCodec.channelOverrideBody(patch),
      },
    });
  }

  /// R04: only the DM pseudo-guild uses the single-guild route. Every real
  /// guild goes through the bulk route with a one-entry map, which is what
  /// Discord's own client does even for a single toggle.
  Future<void> _patchSettings(String spaceId, Map<String, Object?> body) =>
      _queue.sendNow(
        spaceId == CommunitySpace.directMessagesId
            ? DiscordDesktopReadStateRequests.guildNotificationSettings(
                guildId: DiscordDesktopReadStateRequests.directMessagesGuildKey,
                settings: body,
              )
            : DiscordDesktopReadStateRequests.bulkNotificationSettings({
                spaceId: body,
              }),
      );

  @override
  Future<void> flush() => _queue.flush();

  Future<void> close() async {
    await _queue.close();
    _store.clear();
    await _updates.close();
  }

  void _emit() {
    _snapshot = _store.snapshot;
    if (!_updates.isClosed) _updates.add(_snapshot);
  }
}
