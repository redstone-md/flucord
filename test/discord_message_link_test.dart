import 'package:flucord/src/domain/channel_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiscordMessageLink.tryParse', () {
    test('reads a channel link and a message link', () {
      final channel = DiscordMessageLink.tryParse(
        'https://discord.com/channels/forge/forge-design',
      );
      expect(channel, isNotNull);
      expect(channel!.spaceId, 'forge');
      expect(channel.channelId, 'forge-design');
      expect(channel.messageId, isNull);

      final message = DiscordMessageLink.tryParse(
        'https://discord.com/channels/forge/forge-design/m5',
      );
      expect(message, isNotNull);
      expect(message!.spaceId, 'forge');
      expect(message.channelId, 'forge-design');
      expect(message.messageId, 'm5');
    });

    test('accepts every host Discord publishes on and @me for DMs', () {
      for (final host in [
        'discord.com',
        'ptb.discord.com',
        'canary.discord.com',
      ]) {
        expect(
          DiscordMessageLink.tryParse(
            'https://$host/channels/forge/forge-design/m5',
          ),
          isNotNull,
          reason: '$host should be a conversation-link host',
        );
      }

      final dm = DiscordMessageLink.tryParse(
        'https://discord.com/channels/@me/dm-mira/m9',
      );
      expect(dm, isNotNull);
      expect(dm!.spaceId, '@me');
      expect(dm.channelId, 'dm-mira');
      expect(dm.messageId, 'm9');
    });

    test('ignores a query or fragment rather than rejecting the link', () {
      final link = DiscordMessageLink.tryParse(
        'https://discord.com/channels/forge/forge-design/m5?jump=now#top',
      );
      expect(link, isNotNull);
      expect(link!.channelId, 'forge-design');
      expect(link.messageId, 'm5');
    });

    test('rejects links that name no conversation of this app', () {
      expect(
        DiscordMessageLink.tryParse('https://example.com/channels/a/b'),
        isNull,
      );
      expect(DiscordMessageLink.tryParse('https://discord.com/store'), isNull);
      expect(
        DiscordMessageLink.tryParse('https://discord.com/channels/forge'),
        isNull,
      );
      expect(
        DiscordMessageLink.tryParse(
          'https://discord.com/channels/forge/forge-design/m5/extra',
        ),
        isNull,
      );
      expect(DiscordMessageLink.tryParse('not a link'), isNull);
      expect(DiscordMessageLink.tryParse(''), isNull);
    });

    test('equals links that name the same destination', () {
      expect(
        const DiscordMessageLink(spaceId: 'forge', channelId: 'forge-design'),
        const DiscordMessageLink(spaceId: 'forge', channelId: 'forge-design'),
      );
      expect(
        const DiscordMessageLink(spaceId: 'forge', channelId: 'forge-design'),
        isNot(
          const DiscordMessageLink(
            spaceId: 'forge',
            channelId: 'forge-design',
            messageId: 'm5',
          ),
        ),
      );
    });
  });
}
