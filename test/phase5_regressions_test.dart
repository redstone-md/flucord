import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('permission parsing', () {
    test('an unsigned field is never read as every bit set', () {
      // Two's complement makes -1 hold every bit, so hasAll would have
      // answered true for ADMINISTRATOR: one malformed field would have
      // failed open into full rights.
      expect(DiscordPermissions.tryParse('-1'), isNull);
      expect(DiscordPermissions.tryParse(-1), isNull);
      expect(DiscordPermissions.parse('-1'), DiscordPermissions.none);
      expect(
        DiscordPermissions.hasAll(
          DiscordPermissions.parse('-1'),
          DiscordPermissions.administrator,
        ),
        isFalse,
      );
    });

    test('a legitimate high-bit value survives', () {
      // USE_EXTERNAL_APPS and friends live above bit 32, so a 32-bit read
      // would silently drop them.
      final high = BigInt.one << 50;
      expect(DiscordPermissions.tryParse(high.toString()), high);
      expect(DiscordPermissions.hasAll(high, high), isTrue);
    });
  });
}
