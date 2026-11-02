import 'dart:async';

import 'package:flucord/src/data/discord/discord_gateway_client.dart';

/// The bot transport's gateway with no socket behind it. A test sends what
/// Discord would through [emit] or [dispatch].
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

  @override
  void updateVoiceState({
    required String guildId,
    required String? channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) {}

  @override
  void pingVoiceServer() {}

  @override
  Future<void> close() => _events.close();
}
