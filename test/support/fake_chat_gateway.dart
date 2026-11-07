import 'dart:async';

import 'package:flucord/src/data/discord/discord_gateway_client.dart';

/// One opcode 4 voice state, as the gateway was asked to send it.
typedef FakeVoiceStateFrame = ({
  String guildId,
  String? channelId,
  bool selfMute,
  bool selfDeaf,
  bool selfVideo,
});

/// The bot transport's gateway with no socket behind it. A test sends what
/// Discord would through [emit] or [dispatch], and reads what went out in
/// [voiceStates] and [voicePings].
final class FakeChatGateway implements DiscordChatGateway {
  final StreamController<DiscordGatewayEvent> _events =
      StreamController.broadcast();

  void emit(DiscordGatewayEvent event) => _events.add(event);

  /// Sends one dispatch, as its `t` name and raw `d`.
  void dispatch(String name, Map<String, Object?> data) =>
      emit(DiscordGatewayDispatch(name: name, data: data));

  @override
  Stream<DiscordGatewayEvent> get events => _events.stream;

  @override
  String? get sessionId => 'session-1';

  @override
  Future<void> connect(String gatewayUrl) async {}

  /// Every opcode 4 voice state sent, oldest first.
  final List<FakeVoiceStateFrame> voiceStates = [];

  /// How many opcode 5 voice server pings were sent.
  int voicePings = 0;

  @override
  void updateVoiceState({
    required String guildId,
    required String? channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) => voiceStates.add((
    guildId: guildId,
    channelId: channelId,
    selfMute: selfMute,
    selfDeaf: selfDeaf,
    selfVideo: selfVideo,
  ));

  @override
  void pingVoiceServer() => voicePings++;

  @override
  Future<void> close() => _events.close();
}
