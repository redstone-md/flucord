import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/oauth_guild_directory_controller.dart';
import 'package:flucord/src/domain/discord_oauth.dart';

void main() {
  test('reconciles and changes OAuth guild selection independently', () {
    final controller = OAuthGuildDirectoryController();
    final account = _account(['guild-1', 'guild-2']);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.reconcile(account);
    expect(controller.selectedGuildId, 'guild-1');
    expect(notifications, 0);

    controller.selectGuild(account, 'guild-2');
    expect(controller.selectedGuildId, 'guild-2');
    expect(notifications, 1);

    controller.selectGuild(account, 'missing');
    expect(controller.selectedGuildId, 'guild-2');
    expect(notifications, 1);

    controller.reconcile(_account(['guild-2', 'guild-3']));
    expect(controller.selectedGuildId, 'guild-2');
    controller.reconcile(_account(['guild-3']));
    expect(controller.selectedGuildId, 'guild-3');
    controller.reconcile(null);
    expect(controller.selectedGuildId, isNull);
  });
}

DiscordOAuthAccount _account(List<String> guildIds) => DiscordOAuthAccount(
  id: 'user-1',
  username: 'jack',
  displayName: 'Jack',
  guilds: [
    for (final guildId in guildIds)
      DiscordOAuthGuild(id: guildId, name: guildId),
  ],
);
