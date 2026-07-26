import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_snowflake.dart';

void main() {
  test('orders snowflakes by value, not lexicographically', () {
    expect(
      DiscordSnowflake.compare('987654321098765432', '234567890123456789'),
      isPositive,
    );
    // Lexicographically '99' would win; numerically it is the smaller id.
    expect(DiscordSnowflake.compare('99', '111111111111111111'), isNegative);
    expect(
      DiscordSnowflake.compare('123456789012345678', '123456789012345678'),
      isZero,
    );
    expect(
      DiscordSnowflake.compare('000123456789012345678', '123456789012345678'),
      isZero,
    );
  });

  test('treats ids that carry no snowflake as the oldest possible one', () {
    expect(DiscordSnowflake.compare('placeholder-channel', '0'), isZero);
    expect(DiscordSnowflake.compare('', '00'), isZero);
    expect(
      DiscordSnowflake.compare('111111111111111111', 'placeholder-channel'),
      isPositive,
    );
    expect(
      DiscordSnowflake.timestampMillis('placeholder-channel'),
      DiscordSnowflake.epochMillis,
    );
  });

  test('reads the timestamp a snowflake encodes', () {
    final older = DiscordSnowflake.timestampMillis('111111111111111111');
    final newer = DiscordSnowflake.timestampMillis('987654321098765432');
    expect(older, greaterThan(DiscordSnowflake.epochMillis));
    expect(newer, greaterThan(older));
  });

  test('promotes a timestamp into snowflake space and back', () {
    final millis = DateTime.utc(2026, 7, 20, 12).millisecondsSinceEpoch;
    final promoted = DiscordSnowflake.fromTimestampMillis(millis);

    expect(DiscordSnowflake.timestampMillis(promoted), millis);
    expect(
      DiscordSnowflake.compare(promoted, '987654321098765432'),
      isPositive,
    );
    // Anything at or before Discord's epoch has no snowflake to promote into.
    expect(
      DiscordSnowflake.fromTimestampMillis(DiscordSnowflake.epochMillis),
      '0',
    );
    expect(DiscordSnowflake.fromTimestampMillis(0), '0');
  });
}
