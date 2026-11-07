import 'package:flutter/material.dart';

import '../domain/chat_models.dart';
import '../domain/discord_permissions.dart';
import '../domain/workspace_permissions.dart';
import '../domain/channel_link.dart';
import '../domain/navigation_memory.dart';
import 'navigation_memory_store.dart';
import 'voice_channel_surface.dart';

final class WorkspaceController extends ChangeNotifier {
  WorkspaceController({NavigationMemoryStore? memory})
    : _memory = memory ?? NavigationMemoryStore();

  final NavigationMemoryStore _memory;

  /// The memory generation the selection below was made under.
  late int _selectionGeneration = _memory.generation;
  String? _selectedSpaceId;
  String? _selectedChannelId;
  String? _targetMessageId;
  int _targetRequest = 0;
  String _query = '';
  ThemeMode _themeMode = ThemeMode.dark;
  bool _showMembers = true;
  bool _showPins = false;
  bool _showThreads = false;
  bool _showSearch = false;
  ChatWorkspace? _reconciledWorkspace;
  final VoiceChannelSurfaces _voiceSurfaces = VoiceChannelSurfaces();

  String? get selectedSpaceId => _selectedSpaceId;
  String? get selectedChannelId => _selectedChannelId;
  String? get targetMessageId => _targetMessageId;

  /// Changes with each [selectMessage], so the timeline can land again on the
  /// message it already points at.
  int get targetRequest => _targetRequest;
  String get query => _query;
  ThemeMode get themeMode => _themeMode;
  bool get showMembers => _showMembers;
  bool get showPins => _showPins;
  bool get showThreads => _showThreads;
  bool get showSearch => _showSearch;
  Set<String> get collapsedCategoryIds =>
      Set.unmodifiable(_memory.collapsedCategoryIds);

  /// The server folders open on the rail. The same set until one is toggled,
  /// so the rail can tell a rebuild that changed nothing.
  Set<int> get openFolderIds => _memory.openFolderIds;

  /// Where the reader stopped in each channel.
  ReadingPositions get readingPositions => _memory;

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
    if (_selectionGeneration != _memory.generation) {
      _selectionGeneration = _memory.generation;
      _selectedSpaceId = null;
      _selectedChannelId = null;
    }
    // This set holds a handful of ids, so each held id is looked up in the
    // workspace rather than every channel id being collected into a set to
    // compare against. Collapsed categories are not swept like this: a guild
    // that is unavailable at launch comes back later with its categories, and
    // an id left behind by a deleted category does no harm.
    _voiceSurfaces.retainWhere((id) => workspace.channelOrNull(id) != null);
    if (_selectedSpaceId == null ||
        workspace.spaceOrNull(_selectedSpaceId!) == null) {
      final remembered = _memory.lastSpaceId;
      _selectedSpaceId =
          remembered != null && workspace.spaceOrNull(remembered) != null
          ? remembered
          : workspace.spaces.first.id;
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
    _targetMessageId = null;
    _selectedChannelId = _landingChannelIn(workspace, _selectedSpaceId!);
  }

  /// The channel to open on when the app starts, or null when there is none.
  /// Only the app's first landing needs this: a later one happens in [reconcile].
  String? landingChannelIn(ChatWorkspace workspace) {
    if (workspace.spaces.isEmpty) return null;
    reconcile(workspace);
    return _selectedChannelId;
  }

  /// Where [spaceId] opens: the channel last open there, if it still exists and
  /// the account may still see it, and otherwise the default one.
  String? _landingChannelIn(ChatWorkspace workspace, String spaceId) {
    final remembered = _memory.lastChannelOf(spaceId);
    final channel = remembered == null
        ? null
        : workspace.channelOrNull(remembered);
    final permissions = WorkspacePermissions(workspace);
    if (channel != null &&
        channel.spaceId == spaceId &&
        permissions.can(DiscordPermissions.viewChannel, channel)) {
      return channel.id;
    }
    final channels = permissions.visibleChannelsFor(spaceId);
    if (channels.isEmpty) return null;
    return channels
        .firstWhere(_isDefaultLandingChannel, orElse: () => channels.first)
        .id;
  }

  /// Notes where the reader chose to go. A landing that [reconcile] picks is not
  /// a choice, so a guild missing for one launch keeps its place in the memory.
  ///
  /// A voice channel is not noted as a space's channel, for the reason on
  /// [_isDefaultLandingChannel]. Neither is a channel of some other space, which
  /// [reconcile] will not leave open.
  void _rememberSelection() {
    final spaceId = _selectedSpaceId;
    if (spaceId == null) return;
    final channelId = _selectedChannelId;
    final channel = channelId == null
        ? null
        : _reconciledWorkspace?.channelOrNull(channelId);
    final worthLanding =
        channel == null ||
        (channel.spaceId == spaceId && channel.kind != ChannelKind.voice);
    _memory.rememberLocation(spaceId, worthLanding ? channelId : null);
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
    // Results belong to the guild they were searched in, so leaving it closes
    // them rather than showing another server's messages under this one's name.
    _showSearch = false;
    _selectedChannelId = _landingChannelIn(workspace, spaceId);
    if (_selectedChannelId != null) _targetMessageId = null;
    _query = '';
    _rememberSelection();
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
    _rememberSelection();
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
    _voiceSurfaces.select(channelId, VoiceChannelSurface.chat);
    _selectedChannelId = channelId;
    _targetMessageId = messageId;
    _targetRequest++;
    _query = '';
    _rememberSelection();
    notifyListeners();
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
    _rememberSelection();
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
    _memory.toggleCategory(categoryId);
    notifyListeners();
  }

  void toggleFolder(int folderId) {
    _memory.toggleFolder(folderId);
    notifyListeners();
  }

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    notifyListeners();
  }
}
