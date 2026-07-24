part of 'discord_api_client.dart';

extension DiscordApiClientMessages on DiscordApiClient {
  Future<Map<String, Object?>> createMessage({
    required String channelId,
    required String content,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    PendingPoll? poll,
    List<String> stickerIds = const [],
    String? nonce,
    bool enforceNonce = false,
    bool suppressNotifications = false,
  }) {
    if (stickerIds.length > 3) {
      throw ArgumentError.value(stickerIds, 'stickerIds', 'maximum is 3');
    }
    _validateNonce(nonce, enforceNonce: enforceNonce);
    final payload = <String, Object?>{
      'content': content,
      if (replyToMessageId != null)
        'message_reference': {'message_id': replyToMessageId},
      if (poll != null) 'poll': DiscordPollCodec.request(poll),
      if (stickerIds.isNotEmpty) 'sticker_ids': stickerIds,
      'nonce': ?nonce,
      if (nonce != null) 'enforce_nonce': enforceNonce,
      if (suppressNotifications)
        'flags': DiscordMessageFlag.suppressNotifications.bit,
      if (attachments.isNotEmpty)
        'attachments': [
          for (var index = 0; index < attachments.length; index++)
            {'id': index, 'filename': attachments[index].name},
        ],
    };
    if (attachments.isEmpty) {
      return _requestObject(
        'POST',
        '/channels/$channelId/messages',
        body: payload,
      );
    }
    return _createMultipartObject(
      '/channels/$channelId/messages',
      payload,
      attachments,
    );
  }

  Future<Map<String, Object?>> createVoiceMessage({
    required String channelId,
    required PendingVoiceMessage voiceMessage,
    String? nonce,
    bool enforceNonce = false,
  }) {
    _validateNonce(nonce, enforceNonce: enforceNonce);
    return _createMultipartObject(
      '/channels/$channelId/messages',
      {
        'flags': DiscordMessageFlag.voiceMessage.bit,
        'nonce': ?nonce,
        if (nonce != null) 'enforce_nonce': enforceNonce,
        'attachments': [
          {
            'id': 0,
            'filename': voiceMessage.name,
            'duration_secs': voiceMessage.durationSecs,
            'waveform': voiceMessage.waveform,
          },
        ],
      },
      [
        PendingAttachment(
          name: voiceMessage.name,
          path: voiceMessage.path,
          size: voiceMessage.size,
        ),
      ],
    );
  }

  Future<Map<String, Object?>> editMessage({
    required String channelId,
    required String messageId,
    required String content,
  }) => _requestObject(
    'PATCH',
    '/channels/$channelId/messages/$messageId',
    body: {'content': content},
  );

  Future<Map<String, Object?>> editMessageFlags({
    required String channelId,
    required String messageId,
    required bool suppressEmbeds,
    bool componentsV2 = false,
  }) => _requestObject(
    'PATCH',
    '/channels/$channelId/messages/$messageId',
    body: {
      'flags':
          (suppressEmbeds ? DiscordMessageFlag.suppressEmbeds.bit : 0) |
          (componentsV2 ? DiscordMessageFlag.componentsV2.bit : 0),
    },
  );

  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) => _requestEmpty('DELETE', '/channels/$channelId/messages/$messageId');

  void _validateNonce(String? nonce, {required bool enforceNonce}) {
    if (nonce != null && nonce.length > 25) {
      throw ArgumentError.value(nonce, 'nonce', 'maximum is 25 characters');
    }
    if (enforceNonce && nonce == null) {
      throw ArgumentError('enforceNonce requires a nonce');
    }
  }
}
