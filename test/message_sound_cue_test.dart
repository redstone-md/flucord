import 'dart:async';

import 'package:flucord/src/application/message_sound_cue.dart';
import 'package:flucord/src/application/window_visible.dart';
import 'package:flucord/src/domain/channel_link.dart';
import 'package:flucord/src/domain/client_sounds.dart';
import 'package:flucord/src/platform/desktop_integration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<DesktopMessageNotification> notifications;
  late WindowVisible window;
  late List<ClientSound> played;
  String? activeChannelId;

  setUp(() {
    notifications = StreamController.broadcast();
    window = WindowVisible();
    played = [];
    activeChannelId = 'text-1';
    final cue = MessageSoundCue(
      notifications: notifications.stream,
      activeChannelId: () => activeChannelId,
      window: window,
      sounds: _RecordingSounds(played),
    );
    addTearDown(cue.dispose);
  });

  Future<void> arrive(String channelId) async {
    notifications.add(
      DesktopMessageNotification(
        identifier: 'flucord-1',
        title: 'Friend',
        body: 'hi',
        link: ChannelLink(spaceId: 'space-1', channelId: channelId),
      ),
    );
    await pumpEventQueue();
  }

  test('a message elsewhere plays the message sound', () async {
    await arrive('text-2');
    expect(played, [ClientSound.message]);
  });

  test('a message in the focused channel makes no sound', () async {
    await arrive('text-1');
    expect(played, isEmpty);
  });

  test('the open channel sounds once the window is not focused', () async {
    window.setFocused(false);
    await arrive('text-1');
    expect(played, [ClientSound.message]);
  });
}

final class _RecordingSounds implements ClientSoundPlayer {
  _RecordingSounds(this.played);

  final List<ClientSound> played;

  @override
  void play(ClientSound sound) => played.add(sound);

  @override
  void loop(ClientSound sound) {}

  @override
  void stopLoop() {}
}
