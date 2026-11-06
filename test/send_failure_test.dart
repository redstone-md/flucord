import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/send_failure.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';

void main() {
  test('a slowmode refusal says slowmode holds the next message', () {
    const refusal = DiscordRateLimitedException(
      message: 'This action cannot be performed due to slowmode rate limit.',
      retryAfter: Duration(seconds: 30),
      responsePayload: {'code': 20016},
    );

    expect(
      sendFailureReason(refusal),
      'Slowmode is on. Try again in 30 seconds.',
    );
  });

  test('a missing permission says the account may not send here', () {
    const refusal = DiscordApiException(
      statusCode: 403,
      message: 'Missing Permissions',
      responsePayload: {'code': 50013},
    );

    expect(
      sendFailureReason(refusal),
      'You do not have permission to send messages here.',
    );
  });

  test('a body too large says the files are too large', () {
    const fromDiscord = DiscordApiException(
      statusCode: 413,
      message: 'Request entity too large',
      responsePayload: {'code': 40005},
    );
    const fromProxy = DiscordApiException(
      statusCode: 413,
      message: 'Request failed',
    );

    expect(sendFailureReason(fromDiscord), 'The files are too large to send.');
    expect(sendFailureReason(fromProxy), 'The files are too large to send.');
  });

  test('another refusal keeps the words Discord gave', () {
    const refusal = DiscordApiException(
      statusCode: 400,
      message: 'Cannot send messages to this user',
      responsePayload: {'code': 50007},
    );

    expect(sendFailureReason(refusal), 'Cannot send messages to this user');
  });
}
