import 'package:flutter/material.dart';

import '../domain/chat_models.dart';
import 'channel_link.dart';
import 'voice_channel_surface.dart';

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
  final VoiceChannelSurfaces _voiceSurfaces = VoiceChannelSurfaces();

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

  VoiceChannelSurface voiceSurfaceOf(String channelId) =>
      _voiceSurfaces.of(channelId);

  void reconcile(ChatWorkspace workspace) {
    final categoryIds = workspace.categories.map((category) => category.id);
    _collapsedCategoryIds.retainAll(categoryIds);
    _voiceSurfaces.retainAll(workspace.channels.map((channel) => channel.id));
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
            _isDefaultLandingChannel,
            orElse: () => availableChannels.first,
          )
          .id;
    }
  }

  /// Voice channels are skipped when a landing channel has to be guessed: the
  /// room is the surface a voice channel opens on, and opening it unasked would
  /// reach for the microphone. A voice channel is still reachable by every
  /// deliberate route.
  static bool _isDefaultLandingChannel(ConversationChannel channel) =>
      channel.kind != ChannelKind.voice && !channel.isThread;

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
        .firstWhere(_isDefaultLandingChannel, orElse: () => channels.first)
        .id;
    _targetMessageId = null;
    _query = '';
    notifyListeners();
  }

  /// [surface] is how a caller says which side of a voice channel it meant.
  /// Leaving it null keeps whatever the channel last showed, which is what the
  /// channel sidebar and its compact stand-in want; message-shaped navigation
  /// passes [VoiceChannelSurface.chat] so a link never drops the user into a
  /// live room.
  void selectChannel(String channelId, {VoiceChannelSurface? surface}) {
    final surfaceChanged =
        surface != null && _voiceSurfaces.select(channelId, surface);
    if (_selectedChannelId == channelId && _targetMessageId == null) {
      if (surfaceChanged) notifyListeners();
      return;
    }
    _selectedChannelId = channelId;
    _targetMessageId = null;
    _query = '';
    notifyListeners();
  }

  void selectVoiceSurface(String channelId, VoiceChannelSurface surface) {
    if (_voiceSurfaces.select(channelId, surface)) notifyListeners();
  }

  /// Jumping to a message is the most message-shaped route there is, so a voice
  /// channel opens on its timeline rather than on the room the anchor is not in.
  void selectMessage(String channelId, String messageId) {
    final changed =
        _selectedChannelId != channelId ||
        _targetMessageId != messageId ||
        _query.isNotEmpty;
    final surfaceChanged = _voiceSurfaces.select(
      channelId,
      VoiceChannelSurface.chat,
    );
    _selectedChannelId = channelId;
    _targetMessageId = messageId;
    _query = '';
    if (changed || surfaceChanged) notifyListeners();
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
    // A channel link points at a conversation, so a voice channel opened this
    // way shows its chat instead of pulling the user into the live room.
    final surfaceChanged = _voiceSurfaces.select(
      link.channelId,
      VoiceChannelSurface.chat,
    );
    _selectedSpaceId = link.spaceId;
    _selectedChannelId = link.channelId;
    _targetMessageId = null;
    _query = '';
    if (changed || surfaceChanged) notifyListeners();
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
