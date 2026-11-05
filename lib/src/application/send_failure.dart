import '../data/discord/discord_rest_client.dart';
import '../domain/duration_in_words.dart';

/// Why a send failed, in words for the person who pressed Send.
///
/// Discord's own message is the clear answer when it gave one. A rate limit
/// says how long to wait, and a server error is not the sender's fault. Anything
/// else is a technical error that would only confuse.
String sendFailureReason(Object? error) => switch (error) {
  DiscordRateLimitedException(:final retryAfter) => sendingTooFast(
    durationInWords(retryAfter, roundUp: true),
  ),
  DiscordApiException(statusCode: >= 500) =>
    'Discord is having trouble. Try again.',
  DiscordApiException(:final message) => message,
  _ => 'Try again.',
};

/// What the person is told when Discord or slowmode holds their next send for
/// [wait], whether that is a rate limit's answer or the composer's countdown.
String sendingTooFast(String wait) =>
    'You are sending too fast. Try again in $wait.';

/// Why a call could not start, in words for the person who pressed Call.
///
/// Discord's own refusal is the clear answer when it gave one, such as a DM
/// with someone who does not take calls from this account.
String callFailureReason(Object? error) => switch (error) {
  DiscordApiException(statusCode: < 500, :final message)
      when message.isNotEmpty =>
    message,
  _ => 'The call could not start. Try again.',
};
