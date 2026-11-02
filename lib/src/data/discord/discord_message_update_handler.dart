import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import 'discord_mapper.dart';

/// Turns `MESSAGE_UPDATE` into a change for the cache and the workspace.
///
/// An update only changes a copy that exists. It adds no row to the cache, and
/// the event it answers with adds no message to the timeline. Discord can send
/// an update for any old message, and a stray one in the timeline would make
/// the next older page start from the wrong place.
final class DiscordMessageUpdateHandler {
  DiscordMessageUpdateHandler(this._cache, this._mapper, this._currentMemberId);

  final ChatCache _cache;
  final DiscordMapper _mapper;
  final String? Function() _currentMemberId;

  /// Applies [payload] to the cached message, if there is one, and returns the
  /// event to announce. The cache may not hold a message the screen shows, so
  /// the event goes out either way.
  Future<MessageUpdatedEvent?> apply(Map<String, Object?> payload) async {
    final messageId = payload['id'];
    if (messageId is! String) return null;
    ChatMessage applyTo(ChatMessage held) => _mapper.message(
      payload,
      fallback: held,
      currentMemberId: _currentMemberId(),
    );
    final member = _mapper.messageAuthor(payload);
    final cached = await _cache.readMessage(messageId);
    if (cached != null) {
      await _cache.writeMessage(applyTo(cached), member: member);
    }
    return MessageUpdatedEvent(
      messageId: messageId,
      applyTo: applyTo,
      member: member,
    );
  }
}
