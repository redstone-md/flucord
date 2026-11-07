import '../../domain/poll_repository.dart';
import 'discord_mapper.dart';
import 'discord_rest_client.dart';

/// The poll routes, as Userdoccers lists them. A poll itself is created with
/// the message that carries it.
///
/// Ending a poll and listing voters work for a bot and a user alike. Only a
/// user may vote.
final class DiscordPollRoutes {
  const DiscordPollRoutes(this._rest);

  final DiscordRestClient _rest;

  /// Ends the poll now. Only its author may.
  Future<Map<String, Object?>> endPoll({
    required String channelId,
    required String messageId,
  }) => _rest.requestObject(
    'POST',
    '/channels/$channelId/polls/$messageId/expire',
  );

  /// Makes [answerIds] the account's whole vote. An empty list takes it back.
  /// Discord answers 204 and sends the vote dispatches.
  Future<void> vote({
    required String channelId,
    required String messageId,
    required List<int> answerIds,
  }) => _rest.requestEmpty(
    'PUT',
    '/channels/$channelId/polls/$messageId/answers/@me',
    body: {'answer_ids': answerIds},
  );

  /// The users who voted for [answerId], up to [limit] after [afterUserId].
  Future<MemberPage> answerVoters({
    required String channelId,
    required String messageId,
    required int answerId,
    required DiscordMapper mapper,
    String? afterUserId,
    int limit = 100,
  }) async {
    final pageLimit = limit.clamp(1, 100);
    final payload = await _rest.requestObject(
      'GET',
      '/channels/$channelId/polls/$messageId/answers/$answerId',
      query: {'after': ?afterUserId, 'limit': '$pageLimit'},
    );
    final users = [
      for (final user in payload['users'] as List? ?? const [])
        if (user is Map) user.cast<String, Object?>(),
    ];
    return MemberPage(
      users: [for (final user in users) mapper.member(user, role: 'Voted')],
      hasMore: users.length == pageLimit,
    );
  }
}
