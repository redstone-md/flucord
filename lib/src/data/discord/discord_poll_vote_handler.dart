import '../../domain/chat_cache.dart';
import '../../domain/chat_repository.dart';
import 'discord_gateway_client.dart';

final class DiscordPollVoteHandler {
  const DiscordPollVoteHandler(this._cache, this._currentMemberId);

  final ChatCache _cache;
  final String? Function() _currentMemberId;

  Future<MessageUpsertedEvent?> apply(DiscordGatewayDispatch event) async {
    final messageId = event.data['message_id'] as String?;
    final answerId = event.data['answer_id'] as int?;
    if (messageId == null || answerId == null) return null;
    final message = await _cache.readMessage(messageId);
    final poll = message?.poll;
    if (message == null || poll == null) return null;
    final answers = [...poll.answers];
    final index = answers.indexWhere((answer) => answer.id == answerId);
    if (index < 0) return null;
    final add = event.name == 'MESSAGE_POLL_VOTE_ADD';
    final byCurrentUser = event.data['user_id'] == _currentMemberId();
    final current = answers[index];
    answers[index] = current.copyWith(
      count: (current.count + (add ? 1 : -1)).clamp(0, 0x7fffffff),
      votedByCurrentUser: byCurrentUser ? add : current.votedByCurrentUser,
    );
    final updated = message.copyWith(poll: poll.copyWith(answers: answers));
    await _cache.writeMessage(updated);
    return MessageUpsertedEvent(message: updated);
  }
}
