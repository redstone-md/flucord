import 'dart:convert';
import 'dart:math';

abstract final class DiscordSocialLobbySecret {
  static String generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
