import '../data/discord/discord_rest_client.dart';

/// Why a send failed, in words for the person who pressed Send.
///
/// Discord's own message is the clear answer when it gave one. Anything else
/// is a technical error that would only confuse.
String sendFailureReason(Object? error) => switch (error) {
  DiscordApiException(:final message) => message,
  _ => 'Try again.',
};
