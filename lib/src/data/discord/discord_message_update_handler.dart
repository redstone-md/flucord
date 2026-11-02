import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import 'discord_mapper.dart';

/// [held] with what [payload] names applied. Each transport supplies this,
/// because the desktop one also knows the account's roles.
typedef DiscordUpdatedMessage =
    ChatMessage Function(Map<String, Object?> payload, ChatMessage held);

/// Turns `MESSAGE_UPDATE` into a change for the workspace and the cache.
///
/// An update only changes a copy that exists. It adds no row to the cache, and
/// the event it announces adds no message to the timeline. Discord can send an
/// update for any old message, and a stray one in the timeline would make the
/// next older page start from the wrong place.
final class DiscordMessageUpdateHandler {
  DiscordMessageUpdateHandler(
    this._cache,
    this._mapper,
    this._updatedMessage,
    this._publish,
  );

  final ChatCache _cache;
  final DiscordMapper _mapper;
  final DiscordUpdatedMessage _updatedMessage;
  final void Function(ChatRepositoryEvent event) _publish;

  /// Announces [payload], then changes the cached copy, if there is one. The
  /// cache may not hold a message the screen shows, so the event goes out either
  /// way.
  Future<void> apply(Map<String, Object?> payload) async {
    final messageId = payload['id'];
    if (messageId is! String) return;
    ChatMessage applyTo(ChatMessage held) => _updatedMessage(payload, held);
    final member = _mapper.messageAuthor(payload);
    _publish(
      MessageUpdatedEvent(
        messageId: messageId,
        applyTo: applyTo,
        member: member,
      ),
    );
    await _cache.updateMessage(messageId, applyTo, member: member);
  }
}
