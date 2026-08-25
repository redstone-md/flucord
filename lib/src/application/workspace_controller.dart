import 'package:flutter/material.dart';

import '../domain/chat_models.dart';
import '../domain/discord_permissions.dart';
import '../domain/workspace_permissions.dart';
import '../domain/channel_link.dart';
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
  bool _showSearch = false;
  ChatWorkspace? _reconciledWorkspace;
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
  bool get showSearch => _showSearch;
  Set<String> get collapsedCategoryIds =>
      Set.unmodifiable(_collapsedCategoryIds);

  VoiceChannelSurface voiceSurfaceOf(String channelId) =>
      _voiceSurfaces.of(channelId);

  /// Drops selections the workspace no longer offers, and lands somewhere when
  /// nothing is selected yet.
  ///
  /// Called from the shell's build, which runs on every frame the shell paints,
  /// while the answer only moves when the workspace does. Selection changes made
  /// from here land their own choice, so a repeat pass over the same workspace
  /// has nothing left to fix.
  void reconcile(ChatWorkspace workspace) {
    if (identical(_reconciledWorkspace, workspace)) return;
    _reconciledWorkspace = workspace;
    // Both sets hold a handful of ids, so each held id is looked up in the
    // workspace rather than every category and channel id being collected into
    // a set to compare against.
    _collapsedCategoryIds.retainWhere(
      (id) => workspace.categoryOrNull(id) != null,
    );
    _voiceSurfaces.retainWhere((id) => workspace.channelOrNull(id) != null);
    if (_selectedSpaceId == null ||
        workspace.spaceOrNull(_selectedSpaceId!) == null) {
      _selectedSpaceId = workspace.spaces.first.id;
    }
    // A selection that is still open needs the same question answered as the
    // filter below asks — but about one channel, not about every channel of the
    // space. Resolving the whole list to confirm nothing moved was the common
    // case, and it ran on every gateway event.
    final selected = _selectedChannelId == null
        ? null
        : workspace.channelOrNull(_selectedChannelId!);
    if (selected != null &&
        selected.spaceId == _selectedSpaceId &&
        WorkspacePermissions(
          workspace,
        ).can(DiscordPermissions.viewChannel, selected)) {
      return;
    }
    final availableChannels = _visibleChannels(workspace, _selectedSpaceId!);
    if (availableChannels.isEmpty) {
      _selectedChannelId = null;
      _targetMessageId = null;
      return;
    }
    _targetMessageId = null;
    _selectedChannelId = availableChannels
        .firstWhere(
          _isDefaultLandingChannel,
          orElse: () => availableChannels.first,
        )
        .id;
  }

  /// Voice channels are skipped when a landing channel has to be guessed: the
  /// room is the surface a voice channel opens on, and opening it unasked would
  /// reach for the microphone. A voice channel is still reachable by every
  /// deliberate route.
  static bool _isDefaultLandingChannel(ConversationChannel channel) =>
      channel.kind != ChannelKind.voice && !channel.isThread;

  /// Landing is only ever guessed among channels the account may actually
  /// open: Discord's own default-channel pick is the first one with
  /// `VIEW_CHANNEL`, and dropping into a hidden channel would show an empty
  /// timeline no request can fill.
  static List<ConversationChannel> _visibleChannels(
    ChatWorkspace workspace,
    String spaceId,
  ) => WorkspacePermissions(workspace).visibleChannelsFor(spaceId);

  void selectSpace(ChatWorkspace workspace, String spaceId) {
    if (_selectedSpaceId == spaceId) return;
    _selectedSpaceId = spaceId;
    // Results belong to the guild they were searched in, so leaving it closes
    // them rather than showing another server's messages under this one's name.
    _showSearch = false;
    final channels = _visibleChannels(workspace, spaceId);
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

  /// Flips the open voice channel between its room and its timeline.
  ///
  /// Answers whether anything moved: with no voice channel open there is
  /// nothing to flip, and a keybind that silently did nothing should be able
  /// to say so.
  bool toggleVoiceChannelChat() {
    final channelId = _selectedChannelId;
    if (channelId == null) return false;
    return _voiceSurfaces.select(
          channelId,
          _voiceSurfaces.of(channelId) == VoiceChannelSurface.chat
              ? VoiceChannelSurface.room
              : VoiceChannelSurface.chat,
        ) &&
        _notified();
  }

  bool _notified() {
    notifyListeners();
    return true;
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
      _showSearch = false;
    }
    notifyListeners();
  }

  void togglePins() {
    _showPins = !_showPins;
    if (_showPins) {
      _showMembers = false;
      _showThreads = false;
      _showSearch = false;
    }
    notifyListeners();
  }

  void toggleThreads() {
    _showThreads = !_showThreads;
    if (_showThreads) {
      _showMembers = false;
      _showPins = false;
      _showSearch = false;
    }
    notifyListeners();
  }

  /// Search results take the same slot as the pins and thread panels, because
  /// they answer the same kind of question about the conversation on screen and
  /// two of them side by side would leave no room for the timeline.
  void openSearch() {
    if (_showSearch) return;
    _showSearch = true;
    _showMembers = false;
    _showPins = false;
    _showThreads = false;
    notifyListeners();
  }

  void closeSearch() {
    if (!_showSearch) return;
    _showSearch = false;
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
