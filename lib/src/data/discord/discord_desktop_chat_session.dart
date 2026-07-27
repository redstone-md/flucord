part of 'discord_desktop_chat_repository.dart';

/// What the transport does once it knows which account it is holding.
///
/// Adopting an account fans one id out to six planes and adopting a workspace
/// tells the read-state store which channels are private; the bootstrap
/// wrapper exists so that a failure names the stage it failed at. None of it
/// is a call a caller makes, so it sits beside the transport rather than
/// inside it.
extension _DiscordDesktopChatSession on DiscordDesktopChatRepository {
  /// Voice signalling cannot tell our own `VOICE_STATE_UPDATE` from anybody
  /// else's until it knows who we are, and that answer only exists once a
  /// workspace — live or cached — has been resolved.
  void _adoptCurrentMember(String memberId) {
    _currentMemberId = memberId;
    _voiceSignaling.setCurrentUserId(memberId);
    _directCalls.setCurrentUserId(memberId);
    _messageSearch.setCurrentUserId(memberId);
    _presence.currentUserId = memberId;
    // The ACK token belongs to one logged-in account; carrying it across a
    // switch would have the new account acking with the old one's credential.
    _readState.setCurrentUserId(memberId);
    _emitSelfPresence();
  }

  /// Publishes the account's own row.
  ///
  /// The id may come from either side: `loadWorkspace` resolves it from the
  /// bootstrap, but READY names the account first, and waiting for the slower
  /// of the two would leave the panel showing a stale status for as long as the
  /// workspace takes to map.
  void _emitSelfPresence() {
    final memberId = _currentMemberId ?? _presence.currentUserId;
    if (memberId == null || _events.isClosed) return;
    _events.add(
      PresenceChangedEvent(
        memberId: memberId,
        presence: _presence.selfUserPresence,
      ),
    );
  }

  /// R09 computes `private_channels_version` over the read states of private
  /// channels only, so the store has to be told which channels those are.
  void _adoptPrivateChannels(ChatWorkspace workspace) =>
      _readState.setPrivateChannelIds(
        workspace.channels
            .where((channel) => channel.isDirectMessage)
            .map((channel) => channel.id),
      );

  Future<T> _bootstrapStage<T>(
    String stage,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      developer.log(
        'Discord desktop bootstrap failed at $stage: '
        '${_diagnosticFor(error)}',
        name: 'flucord.discord.desktop',
        level: 1000,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

String _diagnosticFor(Object error) => switch (error) {
  DiscordApiException() => 'HTTP ${error.statusCode}: ${error.message}',
  _ => '${error.runtimeType}: $error',
};
