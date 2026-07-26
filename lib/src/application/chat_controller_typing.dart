part of 'chat_controller.dart';

/// The typing indicator, both halves of it.
///
/// Kept together because the two are one protocol: what the account announces
/// is rate limited against the same clock the inbound rows expire on, and
/// splitting them let the two drift out of step.
extension ChatControllerTyping on ChatController {
  /// Who is typing in [channelId], never including the account itself.
  List<Member> typingMembersFor(String channelId) {
    final workspace = _workspace;
    if (workspace == null) return const [];
    return (_typingMembers[channelId] ?? const <String>{})
        .where((id) => id != workspace.currentMemberId)
        .map(workspace.memberOrNull)
        .whereType<Member>()
        .toList(growable: false);
  }

  /// Announces that the account is typing, at most once every eight seconds.
  ///
  /// Discord's own indicator lasts ten, so a keystroke-per-request client would
  /// spend its rate limit saying what the server already believes.
  Future<void> startTyping(String channelId) async {
    final now = DateTime.now();
    final previous = _typingRequests[channelId];
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 8)) {
      return;
    }
    _typingRequests[channelId] = now;
    try {
      await _repository.startTyping(channelId);
    } catch (error) {
      _error = error;
    }
  }

  void _handleTyping(TypingStartedEvent event) {
    if (event.memberId == _workspace?.currentMemberId) return;
    final members = _typingMembers.putIfAbsent(event.channelId, () => {});
    members.add(event.memberId);
    final key = '${event.channelId}:${event.memberId}';
    _typingTimers[key]?.cancel();
    _typingTimers[key] = Timer(const Duration(seconds: 9), () {
      _typingMembers[event.channelId]?.remove(event.memberId);
      _typingTimers.remove(key);
      if (!_disposed) _notify();
    });
  }

  void _clearTyping() {
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _typingMembers.clear();
    _typingRequests.clear();
  }
}
