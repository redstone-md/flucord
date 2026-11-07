typedef DiscordNonceClock = DateTime Function();

/// One-shot nonces for the sends that have no Retry, such as polls, stickers
/// and forwards. A message with Retry keeps its nonce in the chat controller's
/// outgoing queue instead.
final class DiscordMessageNonceFactory {
  DiscordMessageNonceFactory({DiscordNonceClock? clock})
    : _clock = clock ?? DateTime.now;

  final DiscordNonceClock _clock;
  int _sequence = 0;

  String next() {
    final timestamp = _clock().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final sequence = (_sequence++ % 1296).toRadixString(36).padLeft(2, '0');
    return '$timestamp$sequence';
  }
}
