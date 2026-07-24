import 'package:flutter/foundation.dart';

import '../domain/discord_oauth.dart';

final class OAuthGuildDirectoryController extends ChangeNotifier {
  String? _selectedGuildId;

  String? get selectedGuildId => _selectedGuildId;

  void reconcile(DiscordOAuthAccount? account) {
    final guilds = account?.guilds ?? const <DiscordOAuthGuild>[];
    if (_selectedGuildId != null &&
        guilds.any((guild) => guild.id == _selectedGuildId)) {
      return;
    }
    _selectedGuildId = guilds.isEmpty ? null : guilds.first.id;
  }

  void selectGuild(DiscordOAuthAccount account, String guildId) {
    if (_selectedGuildId == guildId ||
        !account.guilds.any((guild) => guild.id == guildId)) {
      return;
    }
    _selectedGuildId = guildId;
    notifyListeners();
  }
}
