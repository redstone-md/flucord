import 'dart:io';

import '../data/discord/discord_rest_client.dart';
import '../domain/duration_in_words.dart';

/// Discord's error codes for the refusals a sender can act on.
const _slowmodeCode = 20016;
const _missingPermissionsCode = 50013;
const _tooLargeCode = 40005;

/// Why a send failed, in words for the person who pressed Send.
///
/// A refusal Discord names by code is said plainly: slowmode, a missing
/// permission, files too large. Otherwise Discord's own message is the clear
/// answer when it gave one. A rate limit says how long to wait, and a server
/// error is not the sender's fault. Anything else is a technical error that
/// would only confuse.
String sendFailureReason(Object? error) => switch (error) {
  DiscordRateLimitedException(:final retryAfter, :final responsePayload)
      when responsePayload?['code'] == _slowmodeCode =>
    'Slowmode is on. Try again in '
        '${durationInWords(retryAfter, roundUp: true)}.',
  DiscordRateLimitedException(:final retryAfter) => sendingTooFast(
    durationInWords(retryAfter, roundUp: true),
  ),
  DiscordApiException(:final responsePayload)
      when responsePayload?['code'] == _missingPermissionsCode =>
    'You do not have permission to send messages here.',
  DiscordApiException(statusCode: HttpStatus.requestEntityTooLarge) ||
  DiscordApiException(
    responsePayload: {'code': _tooLargeCode},
  ) => 'The files are too large to send.',
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
String callFailureReason(Object? error) =>
    refusalOr(error, 'The call could not start. Try again.');

/// Discord's own refusal of [error] when it gave one, else [fallback].
String refusalOr(Object? error, String fallback) => switch (error) {
  DiscordApiException(statusCode: < 500, :final message)
      when message.isNotEmpty =>
    message,
  _ => fallback,
};
