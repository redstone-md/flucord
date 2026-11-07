part of 'chat_controller.dart';

/// The most of a send's upload the timeline shows while the send is out.
const _uploadShownAtMost = 0.99;

/// The messages this client is sending, per channel, in the order written.
final class _OutgoingMessages {
  final Map<String, List<OutgoingMessage>> _byChannel = {};

  /// The last send queued in each channel. Each send waits for the one before
  /// it, so a channel's messages arrive in the order they were written.
  final Map<String, Future<bool>> _tails = {};

  /// What to run, by nonce, once a message leaves the queue: sent, echoed,
  /// deleted, or dropped when its session ends. Its files are let go here.
  final Map<String, void Function()> _onLeave = {};
  int _lastNonceMillis = 0;

  List<OutgoingMessage> inChannel(String channelId) =>
      List.unmodifiable(_byChannel[channelId] ?? const <OutgoingMessage>[]);

  /// A snowflake of now, later than every nonce before it.
  String nextNonce() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastNonceMillis = now > _lastNonceMillis ? now : _lastNonceMillis + 1;
    return DiscordSnowflake.fromTimestampMillis(_lastNonceMillis);
  }

  bool holds(OutgoingMessage message) => _indexOf(message) >= 0;

  void add(OutgoingMessage message, {void Function()? onLeave}) {
    (_byChannel[message.channelId] ??= []).add(message);
    if (onLeave != null) _onLeave[message.nonce] = onLeave;
  }

  /// Swaps in [message] for the held one with its nonce. Returns false when
  /// none is held: Discord's echo or a delete got there first.
  bool replace(OutgoingMessage message) {
    final index = _indexOf(message);
    if (index < 0) return false;
    _byChannel[message.channelId]![index] = message;
    return true;
  }

  bool remove(String channelId, String nonce) {
    final held = _byChannel[channelId];
    final before = held?.length ?? 0;
    held?.removeWhere((message) => message.nonce == nonce);
    if (held != null && held.isEmpty) _byChannel.remove(channelId);
    final removed = (held?.length ?? 0) != before;
    if (removed) _onLeave.remove(nonce)?.call();
    return removed;
  }

  /// Drops every held message, sending or failed, for a session that ends.
  /// A send already on the wire may still land; it is no longer shown here.
  void releaseAll() {
    _byChannel.clear();
    final onLeave = [..._onLeave.values];
    _onLeave.clear();
    for (final release in onLeave) {
      release();
    }
  }

  int _indexOf(OutgoingMessage message) =>
      _byChannel[message.channelId]?.indexWhere(
        (held) => held.nonce == message.nonce,
      ) ??
      -1;

  /// Runs [send] once the sends queued before it in [channelId] are done.
  /// [send] reports its own failure, so it never throws.
  Future<bool> afterEarlierSends(
    String channelId,
    Future<bool> Function() send,
  ) => _tails[channelId] = (_tails[channelId] ?? Future.value(true)).then(
    (_) => send(),
  );
}

extension ChatControllerOutgoing on ChatController {
  /// The messages on their way to [channelId], oldest first: sending, or failed
  /// and waiting for Retry or Delete.
  List<OutgoingMessage> outgoingIn(String channelId) =>
      _outgoing.inChannel(channelId);

  /// Sends a failed message again, under the nonce it first went out with, so
  /// Discord gives back the first message if that one did arrive.
  Future<bool> retrySend(OutgoingMessage message) {
    final sending = message.withDelivery(const OutgoingSending());
    if (!message.hasFailed || !_outgoing.replace(sending)) {
      return Future.value(false);
    }
    _notify();
    return _deliver(sending);
  }

  /// Drops a failed message from the timeline without sending it.
  void discardSend(OutgoingMessage message) {
    if (!message.hasFailed) return;
    if (_outgoing.remove(message.channelId, message.nonce)) _notify();
  }

  /// Shows [message] at once and queues its send. [onLeave] runs once the
  /// message leaves the queue, as [_OutgoingMessages] lists.
  Future<bool> _queueSend(OutgoingMessage message, {void Function()? onLeave}) {
    final channelId = message.channelId;
    if (hasNewerMessages(channelId)) unawaited(jumpToPresent(channelId));
    _outgoing.add(message, onLeave: onLeave);
    _lastSentMessage = message.message;
    _notify();
    return _deliver(message);
  }

  /// Sends [message] once the channel's earlier sends are done. Returns whether
  /// Discord has it. A failure stays in the timeline, and [error] says why.
  Future<bool> _deliver(OutgoingMessage message) =>
      _outgoing.afterEarlierSends(message.channelId, () async {
        if (!_outgoing.holds(message)) return false;
        var lastPercent = -1;
        void onUploadProgress(double fraction) {
          // The files going out is not the whole send: Discord still has to
          // take the message. Complete is never shown, because the row leaves
          // the timeline when the send returns.
          final shown = fraction.clamp(0.0, _uploadShownAtMost);
          // Whole percents, so a large file does not redraw the app for each
          // chunk.
          final percent = (shown * 100).floor();
          if (percent == lastPercent || _disposed) return;
          lastPercent = percent;
          final progress = OutgoingSending(uploadProgress: shown);
          if (_outgoing.replace(message.withDelivery(progress))) _notify();
        }

        try {
          final sent = await _send(
            message,
            onUploadProgress: message.attachments.isEmpty
                ? null
                : onUploadProgress,
          );
          _outgoing.remove(message.channelId, message.nonce);
          _applySentMessage(sent);
          _error = null;
          return true;
        } catch (error) {
          // Held no more means Discord's echo arrived: the message is there.
          final failed = message.withDelivery(OutgoingFailed(error));
          if (!_outgoing.replace(failed)) return true;
          AppLog.warning('chat.send', 'Sending a message failed', error: error);
          _error = error;
          return false;
        } finally {
          if (!_disposed) _notify();
        }
      });

  /// Hands [message] to the repository, as text or as a voice message.
  Future<ChatMessage> _send(
    OutgoingMessage message, {
    required UploadProgressListener? onUploadProgress,
  }) {
    final draft = message.message;
    final repository = _repository;
    return switch ((message.kind, repository)) {
      (final OutgoingText text, _) => repository.sendMessage(
        channelId: draft.channelId,
        authorId: draft.authorId,
        body: draft.body,
        nonce: message.nonce,
        attachments: text.attachments,
        replyToMessageId: text.replyToMessageId,
        suppressNotifications: draft.suppressesNotifications,
        textToSpeech: draft.isTextToSpeech,
        onUploadProgress: onUploadProgress,
      ),
      (
        OutgoingVoice(:final recording),
        final VoiceMessageRepository repository,
      ) =>
        repository.sendVoiceMessage(
          channelId: draft.channelId,
          authorId: draft.authorId,
          voiceMessage: recording,
          nonce: message.nonce,
          onUploadProgress: onUploadProgress,
        ),
      // The session changed to one without voice messages since the send.
      _ => Future.error(
        UnsupportedError('This session cannot send voice messages'),
      ),
    };
  }

  /// Takes this client's own message out of the outgoing list when Discord
  /// echoes it with the nonce it was sent under.
  void _settleEcho(MessageUpsertedEvent event) {
    final nonce = event.nonce;
    if (nonce == null ||
        event.message.authorId != _workspace?.currentMemberId) {
      return;
    }
    _outgoing.remove(event.message.channelId, nonce);
  }
}
