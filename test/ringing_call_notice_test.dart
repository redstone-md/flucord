import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/ringing_call_notice.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/voice_call.dart';

void main() {
  late ChatWorkspace workspace;

  setUp(() async {
    workspace = await MockChatRepository(
      latency: Duration.zero,
    ).loadWorkspace();
  });

  const call = IncomingCall(channelId: 'dm-mira', callerId: 'mira');

  test('names the caller and lands on the call', () {
    final notice = ringingCallNotice(
      call,
      workspace,
      hidesNames: false,
      showsToast: true,
    );

    expect(notice.identifier, 'flucord-call-dm-mira');
    expect(notice.title, 'Incoming call');
    expect(notice.body, 'Mira Chen is calling');
    // A DM the client has not opened yet still has a home to land in.
    expect(
      notice.link,
      const ChannelLink(spaceId: '@me', channelId: 'dm-mira'),
    );
    expect(notice.showsToast, isTrue);
  });

  test('streamer mode keeps the caller off the stream', () {
    final notice = ringingCallNotice(
      call,
      workspace,
      hidesNames: true,
      showsToast: true,
    );

    expect(notice.body, 'Someone is calling');
    expect(notice.body, isNot(contains('Mira')));
  });

  test('a caller the workspace does not know is still announced', () {
    final notice = ringingCallNotice(
      const IncomingCall(channelId: 'dm-x', callerId: 'stranger'),
      workspace,
      hidesNames: false,
      showsToast: false,
    );

    expect(notice.body, 'Someone is calling');
    expect(notice.showsToast, isFalse);
  });
}
