import 'dart:convert';

import '../../domain/chat_models.dart';

typedef DiscordNonceClock = DateTime Function();

final class DiscordMessageNonceFactory {
  DiscordMessageNonceFactory({DiscordNonceClock? clock})
    : _clock = clock ?? DateTime.now;

  final DiscordNonceClock _clock;
  int _sequence = 0;

  /// The draft that last failed in each channel, with the nonce it went out with.
  final Map<String, ({String draft, String nonce})> _failedDrafts = {};

  /// Runs [send] with this draft's nonce.
  ///
  /// A send that fails may still have posted, so the same draft sent again keeps
  /// its nonce, and Discord answers with the first message instead of a second
  /// one. Changed words are a new message, and so are the same words after a
  /// success. Only the last failure of a channel is kept, which is all a retry
  /// from the composer can reach.
  Future<T> sendDraft<T>({
    required String channelId,
    required String body,
    required List<PendingAttachment> attachments,
    required String? replyToMessageId,
    required bool suppressNotifications,
    required bool textToSpeech,
    required Future<T> Function(String nonce) send,
  }) async {
    final draft = jsonEncode([
      body,
      replyToMessageId,
      suppressNotifications,
      textToSpeech,
      for (final file in attachments) [file.path, file.name, file.size],
    ]);
    final failed = _failedDrafts[channelId];
    final nonce = failed?.draft == draft ? failed!.nonce : next();
    _failedDrafts[channelId] = (draft: draft, nonce: nonce);
    final sent = await send(nonce);
    _failedDrafts.remove(channelId);
    return sent;
  }

  String next() {
    final timestamp = _clock().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final sequence = (_sequence++ % 1296).toRadixString(36).padLeft(2, '0');
    return '$timestamp$sequence';
  }
}
