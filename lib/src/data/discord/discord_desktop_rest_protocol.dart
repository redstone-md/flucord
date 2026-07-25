final class DiscordDesktopRestRequest {
  const DiscordDesktopRestRequest({
    required this.method,
    required this.path,
    this.query = const {},
    this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, Object?>? body;

  factory DiscordDesktopRestRequest.channelHistory({
    required String channelId,
    int limit = 50,
    String? before,
    String? after,
    String? around,
    bool? preload,
    String? feature,
  }) {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    return DiscordDesktopRestRequest(
      method: 'GET',
      path: '/channels/${_snowflake(channelId, 'channelId')}/messages',
      query: {
        if (_present(before)) 'before': before!,
        if (_present(after)) 'after': after!,
        if (_present(around)) 'around': around!,
        'limit': '$limit',
        if (preload != null) 'preload': '$preload',
        if (_present(feature)) 'feature': feature!,
      },
    );
  }

  factory DiscordDesktopRestRequest.createMessage({
    required String channelId,
    required String content,
    required String nonce,
    bool tts = false,
    int flags = 0,
    Map<String, Object?>? messageReference,
    Map<String, Object?>? allowedMentions,
    List<String> stickerIds = const [],
    Map<String, Object?>? poll,
    List<Map<String, Object?>> attachments = const [],
  }) {
    if (nonce.isEmpty || nonce.length > 25) {
      throw ArgumentError.value(nonce, 'nonce', 'Must contain 1-25 characters');
    }
    if (stickerIds.length > 3) {
      throw ArgumentError.value(stickerIds, 'stickerIds', 'Maximum is 3');
    }
    return DiscordDesktopRestRequest(
      method: 'POST',
      path: '/channels/${_snowflake(channelId, 'channelId')}/messages',
      body: {
        'content': content,
        'nonce': nonce,
        'tts': tts,
        'flags': flags,
        if (messageReference != null)
          'message_reference': Map.unmodifiable({...messageReference}),
        if (allowedMentions != null)
          'allowed_mentions': Map.unmodifiable({...allowedMentions}),
        if (stickerIds.isNotEmpty) 'sticker_ids': List.unmodifiable(stickerIds),
        if (poll != null) 'poll': Map.unmodifiable({...poll}),
        if (attachments.isNotEmpty)
          'attachments': List.unmodifiable(
            attachments.map((attachment) => Map.unmodifiable({...attachment})),
          ),
      },
    );
  }

  factory DiscordDesktopRestRequest.editMessage({
    required String channelId,
    required String messageId,
    required String content,
    List<Map<String, Object?>>? components,
    Map<String, Object?>? allowedMentions,
  }) => DiscordDesktopRestRequest(
    method: 'PATCH',
    path:
        '/channels/${_snowflake(channelId, 'channelId')}'
        '/messages/${_snowflake(messageId, 'messageId')}',
    body: {
      'content': content,
      if (components != null)
        'components': List.unmodifiable(
          components.map((component) => Map.unmodifiable({...component})),
        ),
      if (allowedMentions != null)
        'allowed_mentions': Map.unmodifiable({...allowedMentions}),
    },
  );

  factory DiscordDesktopRestRequest.deleteMessage({
    required String channelId,
    required String messageId,
  }) => DiscordDesktopRestRequest(
    method: 'DELETE',
    path:
        '/channels/${_snowflake(channelId, 'channelId')}'
        '/messages/${_snowflake(messageId, 'messageId')}',
  );

  factory DiscordDesktopRestRequest.ackMessage({
    required String channelId,
    required String messageId,
    String? readStateToken,
    int? lastViewed,
    int? flags,
  }) => DiscordDesktopRestRequest(
    method: 'POST',
    path:
        '/channels/${_snowflake(channelId, 'channelId')}'
        '/messages/${_snowflake(messageId, 'messageId')}/ack',
    body: {'token': readStateToken, 'last_viewed': lastViewed, 'flags': flags},
  );

  factory DiscordDesktopRestRequest.ackBulk(
    List<Map<String, Object?>> readStates,
  ) => DiscordDesktopRestRequest(
    method: 'POST',
    path: '/read-states/ack-bulk',
    body: {
      'read_states': List.unmodifiable(
        readStates.map((readState) => Map.unmodifiable({...readState})),
      ),
    },
  );

  factory DiscordDesktopRestRequest.openDirectMessage(
    Iterable<String> recipientIds,
  ) {
    final recipients = recipientIds
        .map((id) => _snowflake(id, 'recipientIds'))
        .toList(growable: false);
    if (recipients.isEmpty) {
      throw ArgumentError.value(
        recipientIds,
        'recipientIds',
        'Cannot be empty',
      );
    }
    return DiscordDesktopRestRequest(
      method: 'POST',
      path: '/users/@me/channels',
      body: {'recipients': List.unmodifiable(recipients)},
    );
  }

  static bool _present(String? value) => value != null && value.isNotEmpty;

  static String _snowflake(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty || int.tryParse(normalized) == null) {
      throw ArgumentError.value(value, name, 'Expected a numeric snowflake');
    }
    return normalized;
  }
}
