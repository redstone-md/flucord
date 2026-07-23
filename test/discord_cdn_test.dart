import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_cdn.dart';

void main() {
  test('builds documented Discord CDN identity URLs', () {
    expect(
      DiscordCdn.guildIcon('guild-1', 'icon-hash'),
      'https://cdn.discordapp.com/icons/guild-1/icon-hash.webp?size=128',
    );
    expect(
      DiscordCdn.userAvatar('user-1', 'a_avatar-hash', size: 256),
      'https://cdn.discordapp.com/avatars/user-1/a_avatar-hash.gif?size=256',
    );
    expect(
      DiscordCdn.guildMemberAvatar('guild-1', 'user-1', 'member-hash'),
      'https://cdn.discordapp.com/guilds/guild-1/users/user-1/avatars/member-hash.webp?size=128',
    );
    expect(
      DiscordCdn.customEmoji('emoji-1', animated: true),
      'https://cdn.discordapp.com/emojis/emoji-1.gif?size=32&quality=lossless',
    );
  });

  test('uses the documented default avatar index', () {
    expect(
      DiscordCdn.userAvatar('4194304', null),
      'https://cdn.discordapp.com/embed/avatars/1.png',
    );
    expect(DiscordCdn.userAvatar('not-a-snowflake', null), isNull);
  });

  test('rejects unsupported CDN dimensions', () {
    expect(
      () => DiscordCdn.guildIcon('guild-1', 'hash', size: 96),
      throwsArgumentError,
    );
    expect(
      () => DiscordCdn.customEmoji('emoji-1', size: 96),
      throwsArgumentError,
    );
  });
}
