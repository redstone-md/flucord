import 'package:flutter/foundation.dart';

import '../domain/discord_oauth.dart';

final class OAuthGuildDirectoryController extends ChangeNotifier {
  String? _selectedGuildId;
  String? _accountId;
  bool _accountHomeSelected = false;

  String? get selectedGuildId => _selectedGuildId;
  bool get accountHomeSelected => _accountHomeSelected;

  void reconcile(DiscordOAuthAccount? account) {
    final guilds = account?.guilds ?? const <DiscordOAuthGuild>[];
    if (_accountId != account?.id) {
      _accountId = account?.id;
      _accountHomeSelected = account != null && guilds.isEmpty;
      _selectedGuildId = _accountHomeSelected || guilds.isEmpty
          ? null
          : guilds.first.id;
      return;
    }
    if (_accountHomeSelected) return;
    if (_selectedGuildId != null &&
        guilds.any((guild) => guild.id == _selectedGuildId)) {
      return;
    }
    _selectedGuildId = guilds.isEmpty ? null : guilds.first.id;
    _accountHomeSelected = account != null && guilds.isEmpty;
  }

  void selectAccountHome() {
    if (_accountId == null || _accountHomeSelected) return;
    _accountHomeSelected = true;
    _selectedGuildId = null;
    notifyListeners();
  }

  void selectGuild(DiscordOAuthAccount account, String guildId) {
    if (!account.guilds.any((guild) => guild.id == guildId) ||
        (!_accountHomeSelected && _selectedGuildId == guildId)) {
      return;
    }
    _accountHomeSelected = false;
    _selectedGuildId = guildId;
    notifyListeners();
  }
}
