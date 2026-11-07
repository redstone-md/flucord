import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/conversation_summary.dart';
import 'package:flucord/src/domain/reaction_repository.dart';
import 'package:flucord/src/domain/read_state_repository.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';

/// A Super Reaction Discord refuses, as it does once the account has none
/// left, is kept for the pane to say rather than thrown at nobody.
void main() {
  const refusal = DiscordApiException(
    statusCode: 400,
    message: 'You have no Super Reactions left.',
  );
  final message = ChatMessage(
    id: '100000000000000301',
    channelId: '100000000000000201',
    authorId: '100000000000000101',
    body: 'Release day',
    sentAt: DateTime.utc(2026, 11, 7),
  );
  const reaction = MessageReaction(emojiName: 'fire', count: 1);

  test('adding one that Discord refuses keeps the refusal', () async {
    final controller = ChatController(_RefusingRepository(refusal));
    addTearDown(controller.dispose);

    expect(await controller.addSuperReaction(message, 'fire'), isFalse);
    expect(controller.error, refusal);
  });

  test('toggling one that Discord refuses keeps the refusal', () async {
    final controller = ChatController(_RefusingRepository(refusal));
    addTearDown(controller.dispose);

    expect(await controller.toggleSuperReaction(message, reaction), isFalse);
    expect(controller.error, refusal);
  });
}

final class _RefusingRepository
    implements ChatRepository, SuperReactionRepository {
  _RefusingRepository(this.refusal);

  final Object refusal;

  @override
  Stream<ChatRepositoryEvent> get events => const Stream.empty();

  @override
  ConversationSummaryRepository? get conversationSummaries => null;

  @override
  ReadStateRepository? get readState => null;

  @override
  UserSettingsRepository? get userSettings => null;

  @override
  Future<void> close() async {}

  @override
  Future<void> addSuperReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => Future.error(refusal);

  @override
  Future<void> removeSuperReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => Future.error(refusal);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
