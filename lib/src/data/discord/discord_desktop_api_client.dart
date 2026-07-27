import '../../domain/chat_models.dart';
import 'discord_call_api.dart';
import 'discord_desktop_rest_protocol.dart';
import 'discord_guild_management_repository.dart';
import 'discord_moderation_repository.dart';
import 'discord_multipart_body.dart';
import 'discord_read_state_repository.dart';
import 'discord_rest_client.dart';
import 'discord_user_settings_transport.dart';

final class DiscordDesktopApiClient
    implements
        DiscordCallApi,
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
