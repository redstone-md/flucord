part of 'chat_controller.dart';

/// The stretch of a channel's history the client holds.
///
/// A channel normally holds its newest messages and grows upward. A jump to a
/// message outside what is held replaces them with a window around that
/// message, because keeping both would leave a hole between them that nothing
/// on screen marks. While such a window stops short of the present, new
/// messages stay out of the list for the same reason, and leaving it loads the
/// newest page again.
extension ChatControllerHistoryWindow on ChatController {
  /// Whether messages newer than the held window exist.
  bool hasNewerMessages(String channelId) =>
      _windowsBehind.containsKey(channelId);

  /// Why the last jump in this channel did not land. The channel keeps showing
  /// the messages it had.
  Object? historyWindowError(String channelId) => _windowErrors[channelId];

  /// Leaves an old window for the newest page of the channel.
  Future<void> jumpToPresent(String channelId) async {
    if (_arrivalsDuringPresentLoad.containsKey(channelId)) return;
    await _moveWindow(channelId);
  }

  /// Replaces what a loaded channel holds, leaving it on screen until the new
  /// page is in.
  Future<void> _moveWindow(String channelId, {String? aroundMessageId}) async {
    final isCurrent = _beginWindowLoad(channelId);
    final loadsPresent = aroundMessageId == null;
    // The page may have been built before these messages reached Discord.
    if (loadsPresent) _arrivalsDuringPresentLoad[channelId] = [];
    _windowErrors.remove(channelId);
    try {
      final page = await _repository.loadChannelHistory(
        channelId,
        aroundMessageId: aroundMessageId,
      );
      if (!isCurrent()) return;
      if (aroundMessageId != null && !page.holds(aroundMessageId)) {
        _windowErrors[channelId] = StateError(
          'Message $aroundMessageId is not in the page around it.',
        );
        return;
      }
      _applyWindow(channelId, page, aroundMessageId: aroundMessageId);
      _foldArrivals(channelId);
    } catch (error) {
      if (isCurrent()) _windowErrors[channelId] = error;
    } finally {
      if (loadsPresent) _arrivalsDuringPresentLoad.remove(channelId);
      if (!_disposed) _notify();
    }
  }

  /// Marks a load as the newest for its channel. The check it returns turns
  /// false once a later load takes over, and that load's page is then dropped.
  bool Function() _beginWindowLoad(String channelId) {
    final load = _windowLoads[channelId] = Object();
    return () => identical(_windowLoads[channelId], load);
  }

  /// Folds in a first page or a window, and works out whether it reaches the
  /// present.
  void _applyWindow(
    String channelId,
    ChannelHistoryPage page, {
    String? aroundMessageId,
  }) {
    final latestKnown = _latestKnownMessageId(channelId);
    final replaces =
        hasNewerMessages(channelId) ||
        (aroundMessageId != null && page.holds(aroundMessageId));
    _workspace = replaces
        ? _workspace?.mergeHistory(page.history)
        : _workspace?.mergeInitialHistory(
            page.history,
            retainExisting: aroundMessageId != null,
          );
    // A short page around an anchor says nothing about where history starts:
    // Discord fills it from both sides. Only an older page can say so.
    _setHistoryExhausted(channelId, aroundMessageId == null && !page.hasMore);
    final newestHeld = _workspace?.messagesFor(channelId).lastOrNull?.id;
    if (aroundMessageId != null &&
        latestKnown != null &&
        newestHeld != null &&
        _isOlderThan(newestHeld, latestKnown)) {
      _windowsBehind[channelId] = latestKnown;
    } else {
      _windowsBehind.remove(channelId);
    }
  }

  /// With more than a page unread, the first unread message is further back
  /// than the newest page. A window around the read cursor holds it, and the
  /// reader leaves that window with Jump to present.
  Future<void> _reachFirstUnread(
    String channelId,
    ChannelHistoryPage newestPage,
    bool Function() isCurrent,
  ) async {
    final opening = _unreadOpenings[channelId];
    final cursor = opening?.lastAckedId;
    if (opening == null || cursor == null || !newestPage.hasMore) return;
    if (!newestPage.history.messages.every((m) => opening.isBehind(m.id))) {
      return;
    }
    try {
      final window = await _repository.loadChannelHistory(
        channelId,
        aroundMessageId: cursor,
      );
      if (isCurrent() && window.holds(cursor)) {
        _applyWindow(channelId, window, aroundMessageId: cursor);
      }
    } on Object {
      // The newest page is on screen already, and it is still worth reading.
    }
  }

  /// Keeps a new message out of a list that stops short of the present, and
  /// notes that the channel has moved on. False when the channel is not in an
  /// old window, and the message belongs in the list.
  bool _keepOutOfOldWindow(ChatMessage message, {Member? member}) {
    if (!hasNewerMessages(message.channelId)) return false;
    final workspace = member == null
        ? _workspace
        : _workspace?.upsertMember(member);
    _workspace = workspace?.recordLatestMessage(message.channelId, message.id);
    _arrivalsDuringPresentLoad[message.channelId]?.add(message);
    return true;
  }

  void _foldArrivals(String channelId) {
    final arrivals = _arrivalsDuringPresentLoad[channelId];
    if (arrivals == null || arrivals.isEmpty) return;
    _workspace = _workspace?.mergeHistory(
      ChannelHistory(channelId: channelId, messages: arrivals, members: []),
      replaceChannel: false,
    );
  }

  /// The newest message this client knows of in a channel, from its record,
  /// from an earlier window, or from what the list holds now.
  String? _latestKnownMessageId(String channelId) {
    final known = [
      _workspace?.channelOrNull(channelId)?.lastMessageId,
      _windowsBehind[channelId],
      _workspace?.messagesFor(channelId).lastOrNull?.id,
    ].nonNulls;
    return known.isEmpty
        ? null
        : known.reduce((left, right) => _isOlderThan(left, right) ? right : left);
  }

  /// Ids that carry no order, as in demo mode, count as older unless equal, so
  /// a window there still offers the way back.
  bool _isOlderThan(String id, String other) =>
      id != other && DiscordSnowflake.compare(id, other) <= 0;
}
