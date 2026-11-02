import '../data/discord/discord_rest_client.dart';

/// Why a send failed, in words for the person who pressed Send.
///
/// Discord's own message is the clear answer when it gave one. A rate limit
/// says how long to wait, and a server error is not the sender's fault. Anything
/// else is a technical error that would only confuse.
String sendFailureReason(Object? error) => switch (error) {
  DiscordRateLimitedException(:final retryAfter) =>
    'You are sending too fast. Try again in ${_waitInWords(retryAfter)}.',
  DiscordApiException(statusCode: >= 500) =>
    'Discord is having trouble. Try again.',
  DiscordApiException(:final message) => message,
  _ => 'Try again.',
};

/// A wait in its largest whole unit, rounded up so the person never comes back
/// too early.
String _waitInWords(Duration wait) {
  final seconds = (wait.inMilliseconds / Duration.millisecondsPerSecond).ceil();
  if (seconds < Duration.secondsPerMinute) {
    return _count(seconds, 'second');
  }
  if (seconds <= Duration.secondsPerHour) {
    return _count((seconds / Duration.secondsPerMinute).ceil(), 'minute');
  }
  return _count((seconds / Duration.secondsPerHour).ceil(), 'hour');
}

String _count(int value, String unit) =>
    value == 1 ? '1 $unit' : '$value ${unit}s';
