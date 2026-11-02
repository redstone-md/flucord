import 'dart:async';

import '../../domain/chat_cache.dart';
import '../../domain/chat_repository.dart';
import 'discord_gateway_client.dart';
import 'discord_reaction_handler.dart';

/// The gateway dispatches that the bot and desktop transports answer the same
/// way.
///
/// Both transports send every dispatch here, so a dispatch added to [route]
/// works on both and the two cannot drift apart. A transport's own routing keeps
/// only what really differs between them.
final class DiscordSharedDispatches {
  DiscordSharedDispatches(
    ChatCache cache,
    String? Function() currentMemberId,
    this._events,
  ) : _reactions = DiscordReactionHandler(cache, currentMemberId);

  final DiscordReactionHandler _reactions;
  final StreamController<ChatRepositoryEvent> _events;

  void route(DiscordGatewayDispatch event) {
    switch (event.name) {
      case 'MESSAGE_REACTION_ADD' ||
          'MESSAGE_REACTION_REMOVE' ||
          'MESSAGE_REACTION_REMOVE_EMOJI' ||
          'MESSAGE_REACTION_REMOVE_ALL':
        unawaited(_announce(_reactions.apply(event)));
    }
  }

  /// Announces what a handler answered. The repository may have closed while
  /// the handler was waiting on the cache.
  Future<void> _announce(Future<ChatRepositoryEvent?> answer) async {
    final update = await answer;
    if (update != null && !_events.isClosed) _events.add(update);
  }
}
