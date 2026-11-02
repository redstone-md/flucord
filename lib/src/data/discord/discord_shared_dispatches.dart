import 'dart:async';

import '../../app_log.dart';
import '../../domain/chat_cache.dart';
import '../../domain/chat_repository.dart';
import 'discord_gateway_client.dart';
import 'discord_mapper.dart';
import 'discord_message_update_handler.dart';
import 'discord_reaction_handler.dart';

/// The gateway dispatches that the bot and desktop transports answer the same
/// way.
///
/// Both transports send every dispatch here, so a dispatch added to [route]
/// works on both and the two cannot drift apart. A transport's own routing keeps
/// only what really differs between them.
final class DiscordSharedDispatches {
  DiscordSharedDispatches(
    this._cache,
    DiscordMapper mapper,
    String? Function() currentMemberId,
    this._events,
  ) : _reactions = DiscordReactionHandler(_cache, currentMemberId),
      _updates = DiscordMessageUpdateHandler(_cache, mapper, currentMemberId);

  final ChatCache _cache;
  final DiscordReactionHandler _reactions;
  final DiscordMessageUpdateHandler _updates;
  final StreamController<ChatRepositoryEvent> _events;

  /// The step added last. See [inOrder].
  Future<void> _lastStep = Future.value();

  /// Finishes when every step added so far has run. A repository closes its
  /// cache only after this, so no step is cut off halfway.
  Future<void> get drained => _lastStep;

  void route(DiscordGatewayDispatch event) {
    switch (event.name) {
      case 'MESSAGE_REACTION_ADD' ||
          'MESSAGE_REACTION_REMOVE' ||
          'MESSAGE_REACTION_REMOVE_EMOJI' ||
          'MESSAGE_REACTION_REMOVE_ALL':
        inOrder(() => _announce(_reactions.apply(event)));
      case 'MESSAGE_UPDATE':
        inOrder(() => _announce(_updates.apply(event.data)));
      case 'MESSAGE_DELETE':
        inOrder(() => _announce(_deleteMessage(event.data)));
    }
  }

  /// Runs [step] after every step added before it.
  ///
  /// Each dispatch about a message goes through here, because each one waits on
  /// the cache. Run side by side, a slow create or edit would finish after the
  /// delete that followed it and bring the message back. A step that fails is
  /// logged, and the next one still runs.
  void inOrder(Future<void> Function() step) {
    _lastStep = _lastStep.then((_) async {
      try {
        await step();
      } catch (error, stackTrace) {
        AppLog.warning(
          'discord.dispatch',
          'Could not apply a message dispatch: $error ($stackTrace)',
          error: error,
        );
      }
    });
  }

  Future<void> _announce(Future<ChatRepositoryEvent?> answer) async {
    final update = await answer;
    if (update != null) _events.add(update);
  }

  Future<MessageDeletedEvent?> _deleteMessage(Map<String, Object?> data) async {
    final messageId = data['id'];
    final channelId = data['channel_id'];
    if (messageId is! String || channelId is! String) return null;
    await _cache.deleteMessage(messageId);
    return MessageDeletedEvent(messageId: messageId, channelId: channelId);
  }
}
