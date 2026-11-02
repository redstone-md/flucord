import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messageId = '900000000000000001';

void main() {
  testSession(
    'a message still waiting for its write reaches the disk when the system '
    'asks the app to exit',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await session.dispatch(
        'MESSAGE_CREATE',
        rawMessage(
          id: _messageId,
          channelId: SessionHarness.channelId,
          guildId: SessionHarness.guildId,
          authorId: SessionHarness.friendId,
          content: 'hello',
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 16));

      await session.systemAsksToExit();

      expect(await session.messageOnDisk(_messageId), isTrue);

      await session.settle();
      expect(session.exitAnswer, {'response': 'exit'});
    },
    onDisk: true,
  );
}
