part of 'chat_controller.dart';

/// Rules screening and onboarding: what a server asks of a new member.
///
/// Each answer folds this account's member row back into the workspace, so
/// a cleared pending state and the roles the answers granted show at once,
/// without waiting for the gateway's member update.
extension ChatControllerJoinGate on ChatController {
  GuildJoinGateRepository? get _joinGate =>
      switch (_repository.guildManagement) {
        final GuildJoinGateRepository gate => gate,
        _ => null,
      };

  /// Whether this session can read and answer a server's rules and
  /// onboarding.
  bool get canAnswerJoinGate => _joinGate != null;

  Future<RulesScreening?> loadRulesScreening(String spaceId) async =>
      _joinGate?.loadRulesScreening(spaceId);

  /// Agrees to [screening] in [spaceId]. A refusal arrives as
  /// [GuildJoinGateRefusal].
  Future<void> acceptRules(String spaceId, RulesScreening screening) async {
    final gate = _joinGate;
    if (gate == null) return;
    _foldOwnMember(
      await gate.acceptRules(guildId: spaceId, screening: screening),
    );
  }

  Future<GuildOnboarding?> loadOnboarding(String spaceId) async =>
      _joinGate?.loadOnboarding(spaceId);

  /// Sends the options picked in [onboarding]. A refusal arrives as
  /// [GuildJoinGateRefusal].
  Future<void> answerOnboarding(
    GuildOnboarding onboarding,
    Set<String> chosenOptionIds,
  ) async {
    final gate = _joinGate;
    if (gate == null) return;
    _foldOwnMember(
      await gate.answerOnboarding(
        guildId: onboarding.guildId,
        onboarding: onboarding,
        chosenOptionIds: chosenOptionIds,
        seenAt: DateTime.now(),
      ),
    );
  }

  void _foldOwnMember(Member? member) {
    if (member == null) return;
    _workspace = _workspace?.upsertMember(member);
    _notify();
  }
}
