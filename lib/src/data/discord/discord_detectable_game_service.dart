import '../../domain/game_detection.dart';
import 'discord_desktop_api_client.dart';

/// The detectable-game list through the desktop REST client.
final class DiscordDetectableGameService implements DetectableGameRepository {
  DiscordDetectableGameService(this._api);

  final DiscordDesktopApiClient _api;

  @override
  Future<List<DetectableGame>?> detectableGames() async {
    final payloads = await _api.getDetectableApplications();
    return [
      for (final payload in payloads) ?DetectableGame.fromPayload(payload),
    ];
  }
}
