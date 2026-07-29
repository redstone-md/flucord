import '../../domain/chat_models.dart';
import 'discord_call_api.dart';
import 'discord_desktop_rest_protocol.dart';
import 'discord_age_verification_repository.dart';
import 'discord_auth_session_repository.dart';
import 'discord_family_centre_repository.dart';
import 'discord_guild_management_repository.dart';
import 'discord_mfa_repository.dart';
import 'discord_moderation_repository.dart';
import 'discord_safety_hub_repository.dart';
import 'discord_multipart_body.dart';
import 'discord_read_state_repository.dart';
import 'discord_rest_client.dart';
import 'discord_application_command_service.dart';
import 'discord_gif_service.dart';
import 'discord_message_component_service.dart';
import 'discord_soundboard_service.dart';
import 'discord_stage_service.dart';
import 'discord_thread_membership_service.dart';
import 'discord_user_profile_repository.dart';
import 'discord_user_settings_transport.dart';

final class DiscordDesktopApiClient
    implements
        DiscordCallApi,
        DiscordUserProfileTransport,
        DiscordThreadMembershipTransport,
        DiscordStageTransport,
        DiscordSoundboardTransport,
        DiscordGifTransport,
        DiscordApplicationCommandTransport,
        DiscordComponentTransport,
        DiscordUserSettingsTransport,
        DiscordReadStateTransport {
  DiscordDesktopApiClient({
    required String authorization,
    required Map<String, String> headers,
    DiscordHttpTransport? transport,
    DelayFunction? delay,
    Uri? baseUri,
  }) : _rest = DiscordRestClient(
         authorization: DiscordDesktopAuthorization(authorization),
         additionalHeaders: headers,
         transport: transport,
         delay: delay,
         baseUri: baseUri ?? Uri.parse('https://discord.com/api/v9'),
       );

  final DiscordRestClient _rest;

  /// The guild-administration routes, sharing this session's credentials.
  ///
  /// Built lazily and kept, so the settings window's sections all talk to one
  /// object rather than each minting its own over the same socket.
  late final DiscordGuildManagementRepository guildManagement =
      DiscordGuildManagementRepository(_rest);

  late final DiscordModerationRepository moderation =
      DiscordModerationRepository(_rest);

  late final DiscordSafetyHubRepository safetyHub = DiscordSafetyHubRepository(
    _rest,
  );

  late final DiscordFamilyCentreRepository familyCentre =
      DiscordFamilyCentreRepository(_rest);

  late final DiscordAuthSessionRepository authSessions =
      DiscordAuthSessionRepository(_rest);

  late final DiscordMfaRepository multiFactorAuth = DiscordMfaRepository(_rest);

  late final DiscordAgeVerificationRepository ageVerification =
      DiscordAgeVerificationRepository(_rest);

  /// The guild's scheduled events, with the interested counts Discord's own
  /// client asks for.
  Future<List<Map<String, Object?>>> getGuildScheduledEvents(String guildId) =>
      _rest.getList(
        '/guilds/$guildId/scheduled-events',
        query: const {'with_user_count': 'true'},
      );

  Future<Map<String, Object?>> createGuildScheduledEvent({
    required String guildId,
    required Map<String, Object?> body,
  }) => _rest.requestObject(
    'POST',
    '/guilds/$guildId/scheduled-events',
    body: body,
  );

  Future<Map<String, Object?>> editGuildScheduledEvent({
    required String guildId,
    required String eventId,
    required Map<String, Object?> body,
  }) => _rest.requestObject(
    'PATCH',
    '/guilds/$guildId/scheduled-events/$eventId',
    body: body,
  );

  Future<void> deleteGuildScheduledEvent({
    required String guildId,
    required String eventId,
  }) => _rest.requestEmpty(
    'DELETE',
    '/guilds/$guildId/scheduled-events/$eventId',
  );

  /// `PUT`/`DELETE /guilds/{id}/scheduled-events/{event}[/{exception}]/users/@me`.
  ///
  /// The response value is Discord's own: 1 for interested. Withdrawing sends
  /// no body at all, which is how one route carries both answers.
  Future<void> setGuildScheduledEventInterest({
    required String guildId,
    required String eventId,
    required bool interested,
    String? exceptionId,
  }) {
    final occurrence = exceptionId == null || exceptionId.isEmpty
        ? ''
        : '/$exceptionId';
    final path =
        '/guilds/$guildId/scheduled-events/$eventId$occurrence/users/@me';
    return interested
        ? _rest.requestEmpty('PUT', path, body: const {'response': 1})
        : _rest.requestEmpty('DELETE', path);
  }

  Future<List<Map<String, Object?>>> getChannelMessages(
    String channelId, {
    int limit = 100,
    String? beforeMessageId,
  }) => _rest.getList(
    '/channels/$channelId/messages',
    query: {'limit': '${limit.clamp(1, 100)}', 'before': ?beforeMessageId},
  );

  Future<List<Map<String, Object?>>> getChannelPins(String channelId) async {
    final payload = await _rest.requestObject(
      'GET',
      '/channels/$channelId/messages/pins',
      query: const {'limit': '50'},
    );
    final items = payload['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) {
          final message = item['message'];
          return message is Map
              ? {...message.cast<String, Object?>(), 'pinned': true}
              : <String, Object?>{};
        })
        .where((message) => message.isNotEmpty)
        .toList(growable: false);
  }

  /// Runs one classic message-search request against [path].
  ///
  /// Unlike every other route here the caller needs the raw answer rather than
  /// the decoded body: a search whose corpus Discord has not finished indexing
  /// comes back `202 Accepted` with a `Retry-After` header, and both the status
  /// and that header are part of the flow.
  Future<DiscordApiResponse> searchMessages(
    String path,
    Map<String, Object?> query,
  ) => _rest.requestDetailed('GET', path, query: query);

  Future<Map<String, Object?>> createDirectMessageChannel(String recipientId) =>
      _rest.requestObject(
        'POST',
        '/users/@me/channels',
        body: {
          'recipients': [recipientId],
        },
      );

  Future<Map<String, Object?>> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) => _rest.requestObject(
    'POST',
    '/channels/$channelId/messages/$messageId/threads',
    body: {'name': name, 'auto_archive_duration': autoArchiveDurationMinutes},
  );

  /// Moves this account between a stage's audience and its speakers.
  ///
  /// `request_to_speak_timestamp` is three-valued on the wire: absent leaves
  /// the hand as it is, a timestamp raises it, and an explicit null lowers it.
  /// Collapsing the last two would make cancelling a request indistinguishable
  /// from not touching it.
  @override
  Future<void> patchSelfVoiceState(
    String guildId, {
    required String channelId,
    bool? suppress,
    String? requestToSpeakTimestamp,
    bool clearRequestToSpeak = false,
  }) => _rest.requestEmpty(
    'PATCH',
    '/guilds/$guildId/voice-states/@me',
    body: {
      'channel_id': channelId,
      'suppress': ?suppress,
      if (clearRequestToSpeak)
        'request_to_speak_timestamp': null
      else
        'request_to_speak_timestamp': ?requestToSpeakTimestamp,
    },
  );

  /// The channel's command index. `include_applications` is what brings the
  /// bot's name and avatar back with each command, so the list can show who
  /// owns one without a second lookup.
  @override
  Future<Map<String, Object?>> searchApplicationCommands(
    String channelId, {
    required String query,
    required int type,
  }) => _rest.requestObject(
    'GET',
    '/channels/$channelId/application-commands/search',
    query: {
      'type': '$type',
      'query': query,
      'limit': '25',
      'include_applications': 'true',
    },
  );

  @override
  Future<void> postInteraction(Map<String, Object?> body) =>
      _rest.requestEmpty('POST', '/interactions', body: body);

  /// Discord's own provider proxy. The client never talks to Tenor or Giphy
  /// directly, and neither does this.
  @override
  Future<Map<String, Object?>> getTrendingGifs({
    required String mediaFormat,
    required String provider,
  }) => _rest.requestObject(
    'GET',
    '/gifs/trending',
    query: {'media_format': mediaFormat, 'provider': provider},
  );

  @override
  Future<List<Map<String, Object?>>> searchGifs({
    required String query,
    required String mediaFormat,
    required String provider,
    int limit = 50,
  }) => _rest.getList(
    '/gifs/search',
    query: {
      'q': query,
      'media_format': mediaFormat,
      'provider': provider,
      'limit': '$limit',
    },
  );

  @override
  Future<List<Object?>> suggestGifs({
    required String query,
    int limit = 8,
  }) async {
    final payload = await _rest.request(
      'GET',
      '/gifs/suggest',
      query: {'q': query, 'limit': '$limit'},
    );
    return payload is List ? payload : const [];
  }

  @override
  Future<List<Map<String, Object?>>> listDefaultSounds() =>
      _rest.getList('/soundboard-default-sounds');

  @override
  Future<Map<String, Object?>> listGuildSounds(String guildId) =>
      _rest.requestObject('GET', '/guilds/$guildId/soundboard-sounds');

  /// `source_guild_id` goes out only for a server's own sound; Discord rejects
  /// it on a default one.
  @override
  Future<void> sendSoundboardSound(
    String channelId, {
    required String soundId,
    String? emojiId,
    String? emojiName,
    String? sourceGuildId,
  }) => _rest.requestEmpty(
    'POST',
    '/channels/$channelId/send-soundboard-sound',
    body: {
      'sound_id': soundId,
      'emoji_id': emojiId,
      'emoji_name': emojiName,
      'source_guild_id': ?sourceGuildId,
    },
  );

  /// The moderator's half of the voice-state route.
  @override
  Future<void> patchMemberVoiceState(
    String guildId, {
    required String userId,
    required String channelId,
    required bool suppress,
  }) => _rest.requestEmpty(
    'PATCH',
    '/guilds/$guildId/voice-states/$userId',
    body: {'channel_id': channelId, 'suppress': suppress},
  );

  /// `privacy_level` is sent as guild-only: Discord retired the public value
  /// and rejects a stage created with it.
  @override
  Future<Map<String, Object?>> createStageInstance({
    required String channelId,
    required String topic,
    bool sendStartNotification = false,
  }) => _rest.requestObject(
    'POST',
    '/stage-instances',
    body: {
      'channel_id': channelId,
      'topic': topic,
      'privacy_level': 2,
      'send_start_notification': sendStartNotification,
    },
  );

  @override
  Future<Map<String, Object?>> updateStageInstance(
    String channelId, {
    required String topic,
  }) => _rest.requestObject(
    'PATCH',
    '/stage-instances/$channelId',
    body: {'topic': topic},
  );

  @override
  Future<void> deleteStageInstance(String channelId) =>
      _rest.requestEmpty('DELETE', '/stage-instances/$channelId');

  /// `GET /channels/{id}/thread-members`, with the guild member attached so a
  /// name and avatar can be shown without a second lookup.
  @override
  Future<List<Map<String, Object?>>> listThreadMembers(String threadId) =>
      _rest.getList(
        '/channels/$threadId/thread-members',
        query: const {'with_member': 'true', 'limit': '100'},
      );

  /// The desktop client posts rather than puts here, and so does this.
  @override
  Future<void> joinThread(String threadId) =>
      _rest.requestEmpty('POST', '/channels/$threadId/thread-members/@me');

  @override
  Future<void> leaveThread(String threadId) =>
      _rest.requestEmpty('DELETE', '/channels/$threadId/thread-members/@me');

  Future<Map<String, Object?>> createMessage({
    required String channelId,
    required String content,
    required String nonce,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    bool suppressNotifications = false,
  }) async {
    final payload = <String, Object?>{
      'content': content,
      'nonce': nonce,
      'tts': false,
      'flags': suppressNotifications ? 4096 : 0,
      if (replyToMessageId != null)
        'message_reference': {'message_id': replyToMessageId},
      if (attachments.isNotEmpty)
        'attachments': [
          for (var index = 0; index < attachments.length; index++)
            {'id': index, 'filename': attachments[index].name},
        ],
    };
    if (attachments.isEmpty) {
      return _rest.requestObject(
        'POST',
        '/channels/$channelId/messages',
        body: payload,
      );
    }
    final multipart = await DiscordMultipartBody.build(payload, attachments);
    final response = await _rest.request(
      'POST',
      '/channels/$channelId/messages',
      rawBody: multipart.bytes,
      contentType: multipart.contentType,
    );
    if (response is! Map) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a message object',
      );
    }
    return response.cast<String, Object?>();
  }

  Future<Map<String, Object?>> editMessage({
    required String channelId,
    required String messageId,
    required String content,
  }) => _rest.requestObject(
    'PATCH',
    '/channels/$channelId/messages/$messageId',
    body: {'content': content},
  );

  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) =>
      _rest.requestEmpty('DELETE', '/channels/$channelId/messages/$messageId');

  /// Acts on one AutoMod alert. Discord reads which message tripped the rule
  /// from the alert, so the body names the alert rather than the offence.
  Future<void> resolveAutoModAlert({
    required String guildId,
    required String channelId,
    required String messageId,
    required int actionType,
  }) => _rest.requestEmpty(
    'POST',
    '/guilds/$guildId/auto-moderation/alert-action',
    body: {
      'message_id': messageId,
      'channel_id': channelId,
      'alert_action_type': actionType,
    },
  );

  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _rest.requestEmpty(
    'PUT',
    '/channels/$channelId/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}/@me',
  );

  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _rest.requestEmpty(
    'DELETE',
    '/channels/$channelId/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}/@me',
  );

  Future<void> setPinned({
    required String channelId,
    required String messageId,
    required bool pinned,
  }) => _rest.requestEmpty(
    pinned ? 'PUT' : 'DELETE',
    '/channels/$channelId/messages/pins/$messageId',
  );

  Future<void> startTyping(String channelId) =>
      _rest.requestEmpty('POST', '/channels/$channelId/typing');

  /// Pre-flight before ringing a channel (R08: `GET /channels/{id}/call`).
  ///
  /// The renderer reads exactly one field off the response, `ringable`, and
  /// treats a failed request as "not ringable" rather than an error — a DM with
  /// somebody who is not a friend answers with a rejection, and the desktop
  /// client turns that into an "add as a friend" prompt.
  @override
  Future<bool> isChannelRingable(String channelId) async {
    final payload = await _rest.requestObject(
      'GET',
      '/channels/$channelId/call',
    );
    return payload['ringable'] == true;
  }

  /// Rings [recipients], or everybody in the channel when it is null.
  ///
  /// R08 shows `recipients` sent explicitly as null for the ring-everybody
  /// case, unlike `stop-ringing` where the key is dropped.
  @override
  Future<void> ringChannel(
    String channelId, {
    List<String>? recipients,
    required String analyticsLocation,
  }) => _rest.request(
    'POST',
    '/channels/$channelId/call/ring',
    body: {'recipients': recipients, 'analytics_location': analyticsLocation},
  );

  /// Stops a ring. With no [recipients] this is the local user's decline, and
  /// the key is omitted entirely rather than sent as null.
  @override
  Future<void> stopRingingChannel(
    String channelId, {
    List<String>? recipients,
  }) => _rest.request(
    'POST',
    '/channels/$channelId/call/stop-ringing',
    body: {'recipients': ?recipients},
  );

  /// Reads one settings blob. A missing `settings` string is an account that
  /// has never stored anything for this type, not a transport failure.
  @override
  Future<Map<String, Object?>> readCurrentUser() =>
      _rest.getObject('/users/@me');

  @override
  Future<Map<String, Object?>> patchCurrentUser(Map<String, Object?> body) =>
      _rest.requestObject('PATCH', '/users/@me', body: body);

  @override
  Future<String?> readSettingsProto(int type) async {
    final payload = await _rest.getObject(
      '/users/@me/settings-proto/${_settingsType(type)}',
    );
    final settings = payload['settings'];
    return settings is String ? settings : null;
  }

  @override
  Future<DiscordSettingsWriteResult> writeSettingsProto({
    required int type,
    required String settings,
  }) async {
    final payload = await _rest.requestObject(
      'PATCH',
      '/users/@me/settings-proto/${_settingsType(type)}',
      body: {'settings': settings},
    );
    final merged = payload['settings'];
    return DiscordSettingsWriteResult(
      settings: merged is String ? merged : null,
      outOfDate: payload['out_of_date'] == true,
    );
  }

  static int _settingsType(int type) {
    if (type < 1 || type > 3) {
      throw ArgumentError.value(type, 'type', 'Unknown settings proto type');
    }
    return type;
  }

  /// Sends a request the read-state protocol built.
  ///
  /// The read-state routes go through [DiscordDesktopRestRequest] rather than
  /// being spelled out here, because two of them encode the read-state type
  /// into the path in an order that is easy to invert; keeping the rendering in
  /// the protocol description is what lets a test pin the exact path.
  @override
  Future<Map<String, Object?>?> sendReadStateRequest(
    DiscordDesktopRestRequest request,
  ) async {
    final payload = await _rest.request(
      request.method,
      request.path,
      query: request.query.isEmpty ? null : request.query,
      body: request.body,
    );
    return payload is Map ? payload.cast<String, Object?>() : null;
  }

  Future<String> getGatewayUrl() async {
    final payload = await _rest.getObject('/gateway');
    final url = payload['url'];
    if (url is! String || url.isEmpty) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Gateway URL missing from response',
      );
    }
    return url;
  }

  void close() => _rest.close();
}
