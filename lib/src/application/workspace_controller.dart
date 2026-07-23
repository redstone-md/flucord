import 'package:flutter/material.dart';

import '../domain/chat_models.dart';
import 'channel_link.dart';

final class WorkspaceController extends ChangeNotifier {
  String? _selectedSpaceId;
  String? _selectedChannelId;
  String? _targetMessageId;
  String _query = '';
  ThemeMode _themeMode = ThemeMode.dark;
  bool _showMembers = true;
  bool _showPins = false;
  bool _showThreads = false;
  final Set<String> _collapsedCategoryIds = {};

  String? get selectedSpaceId => _selectedSpaceId;
  String? get selectedChannelId => _selectedChannelId;
  String? get targetMessageId => _targetMessageId;
  String get query => _query;
  ThemeMode get themeMode => _themeMode;
  bool get showMembers => _showMembers;
  bool get showPins => _showPins;
  bool get showThreads => _showThreads;
  Set<String> get collapsedCategoryIds =>
      Set.unmodifiable(_collapsedCategoryIds);

  void reconcile(ChatWorkspace workspace) {
    final categoryIds = workspace.categories.map((category) => category.id);
    _collapsedCategoryIds.retainAll(categoryIds);
    if (_selectedSpaceId == null ||
        !workspace.spaces.any((space) => space.id == _selectedSpaceId)) {
      _selectedSpaceId = workspace.spaces.first.id;
    }
    final availableChannels = workspace.channelsFor(_selectedSpaceId!);
    if (availableChannels.isEmpty) {
      _selectedChannelId = null;
      _targetMessageId = null;
      return;
    }
    if (_selectedChannelId == null ||
        !availableChannels.any((channel) => channel.id == _selectedChannelId)) {
      _targetMessageId = null;
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
    if (channels.isEmpty) {
      _selectedChannelId = null;
      _query = '';
      notifyListeners();
      return;
    }
    _selectedChannelId = channels
        .firstWhere(
          (channel) => channel.kind == ChannelKind.text,
          orElse: () => channels.first,
        )
        .id;
    _targetMessageId = null;
    _query = '';
    notifyListeners();
  }

  void selectChannel(String channelId) {
    if (_selectedChannelId == channelId && _targetMessageId == null) return;
    _selectedChannelId = channelId;
    _targetMessageId = null;
    _query = '';
    notifyListeners();
  }

  void selectMessage(String channelId, String messageId) {
    final changed =
        _selectedChannelId != channelId ||
        _targetMessageId != messageId ||
        _query.isNotEmpty;
    _selectedChannelId = channelId;
    _targetMessageId = messageId;
    _query = '';
    if (changed) notifyListeners();
  }

  bool openChannelLink(ChatWorkspace workspace, ChannelLink link) {
    ConversationChannel? target;
    for (final channel in workspace.channels) {
      if (channel.id == link.channelId && channel.spaceId == link.spaceId) {
        target = channel;
        break;
      }
    }
    if (target == null) return false;

    final changed =
        _selectedSpaceId != link.spaceId ||
        _selectedChannelId != link.channelId ||
        _query.isNotEmpty;
    _selectedSpaceId = link.spaceId;
    _selectedChannelId = link.channelId;
    _targetMessageId = null;
    _query = '';
    if (changed) notifyListeners();
    return true;
  }

  void setQuery(String value) {
    if (_query == value && (value.isEmpty || _targetMessageId == null)) return;
    _query = value;
    if (value.isNotEmpty) _targetMessageId = null;
    notifyListeners();
  }

  void toggleMembers() {
    _showMembers = !_showMembers;
    if (_showMembers) {
      _showPins = false;
      _showThreads = false;
    }
    notifyListeners();
  }

  void togglePins() {
    _showPins = !_showPins;
    if (_showPins) {
      _showMembers = false;
      _showThreads = false;
    }
    notifyListeners();
  }

  void toggleThreads() {
    _showThreads = !_showThreads;
    if (_showThreads) {
      _showMembers = false;
      _showPins = false;
    }
    notifyListeners();
  }

  void toggleCategory(String categoryId) {
    if (!_collapsedCategoryIds.add(categoryId)) {
      _collapsedCategoryIds.remove(categoryId);
    }
    notifyListeners();
  }

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    notifyListeners();
  }
}
