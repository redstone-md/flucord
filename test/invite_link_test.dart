import 'package:flucord/src/domain/channel_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InviteLink.tryParseCode', () {
    test('reads the three link forms Discord hands out', () {
      expect(InviteLink.tryParseCode('https://discord.gg/aurora'), 'aurora');
      expect(
        InviteLink.tryParseCode('https://discord.com/invite/aurora'),
        'aurora',
      );
      expect(
        InviteLink.tryParseCode('https://discord.gg/invite/aurora'),
        'aurora',
      );
    });

    test('reads a bare code pasted as text', () {
      expect(InviteLink.tryParseCode('aurora'), 'aurora');
      expect(InviteLink.tryParseCode('  aurora  '), 'aurora');
    });

    test("keeps a query Discord's own links carry", () {
      expect(
        InviteLink.tryParseCode('https://discord.gg/aurora?event=123'),
        'aurora',
      );
      expect(
        InviteLink.tryParseCode('https://discord.com/invite/aurora#page'),
        'aurora',
      );
    });

    test('rejects links that are not invites', () {
      expect(
        InviteLink.tryParseCode('https://discord.com/channels/1/2'),
        isNull,
      );
      expect(
        InviteLink.tryParseCode('https://example.com/invite/aurora'),
        isNull,
      );
      expect(InviteLink.tryParseCode('https://discord.gg'), isNull);
      expect(InviteLink.tryParseCode('https://discord.gg/a/b'), isNull);
    });

    test('rejects text that cannot be a code', () {
      expect(InviteLink.tryParseCode(''), isNull);
      expect(InviteLink.tryParseCode('   '), isNull);
      expect(InviteLink.tryParseCode('come join us'), isNull);
      expect(
        InviteLink.tryParseCode('https://discord.com/invites/aurora'),
        isNull,
      );
    });
  });
}
