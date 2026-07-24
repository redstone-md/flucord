import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/disconnected_chat_repository.dart';

void main() {
  const repository = DisconnectedChatRepository();

  test('exposes an empty workspace without synthetic Discord data', () async {
    final workspace = await repository.loadWorkspace();

    expect(workspace.spaces, isEmpty);
    expect(workspace.channels, isEmpty);
    expect(workspace.members, isEmpty);
    expect(workspace.messages, isEmpty);
    expect(await repository.events.toList(), isEmpty);
  });

  test('rejects remote operations while disconnected', () async {
    await expectLater(
      repository.loadChannelHistory('missing-channel'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'No Discord chat transport is connected.',
        ),
      ),
    );
  });
}
