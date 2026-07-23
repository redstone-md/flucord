import 'package:flutter/material.dart';

import '../domain/chat_models.dart';

final class WorkspaceController extends ChangeNotifier {
  String? _selectedSpaceId;
  String? _selectedChannelId;
  String _query = '';
  ThemeMode _themeMode = ThemeMode.dark;
  bool _showMembers = true;

  String? get selectedSpaceId => _selectedSpaceId;
  String? get selectedChannelId => _selectedChannelId;
  String get query => _query;
  ThemeMode get themeMode => _themeMode;
  bool get showMembers => _showMembers;

  void reconcile(ChatWorkspace workspace) {
    if (_selectedSpaceId == null ||
        !workspace.spaces.any((space) => space.id == _selectedSpaceId)) {
      _selectedSpaceId = workspace.spaces.first.id;
    }
    final availableChannels = workspace.channelsFor(_selectedSpaceId!);
    if (_selectedChannelId == null ||
        !availableChannels.any((channel) => channel.id == _selectedChannelId)) {
      _selectedChannelId = availableChannels
          .firstWhere(
            (channel) => channel.kind == ChannelKind.text,
            orElse: () => availableChannels.first,
          )
          .id;
    }
  }

  void selectSpace(ChatWorkspace workspace, String spaceId) {
    if (_selectedSpaceId == spaceId) return;
    _selectedSpaceId = spaceId;
    final channels = workspace.channelsFor(spaceId);
    _selectedChannelId = channels
        .firstWhere(
          (channel) => channel.kind == ChannelKind.text,
          orElse: () => channels.first,
        )
        .id;
    _query = '';
    notifyListeners();
  }

  void selectChannel(String channelId) {
    if (_selectedChannelId == channelId) return;
    _selectedChannelId = channelId;
    _query = '';
    notifyListeners();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  void toggleMembers() {
    _showMembers = !_showMembers;
    notifyListeners();
  }

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    notifyListeners();
  }
}
