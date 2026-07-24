import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/discord_relationship.dart';
import '../domain/discord_social_activity.dart';
import '../domain/discord_social_call.dart';
import '../domain/discord_social_sdk.dart';

final class DiscordSocialActivityController extends ChangeNotifier {
  static const int _maximumRetainedInvites = 20;

  DiscordSocialActivityController(
    this._gateway, {
    DiscordSocialActivityEvents? events,
    DiscordSocialCallGateway? callGateway,
    DiscordSocialCallEvents? callEvents,
  }) : _callGateway =
           callGateway ??
           (_gateway is DiscordSocialCallGateway
               ? _gateway as DiscordSocialCallGateway
               : null) {
    final eventSource =
        events ??
        (_gateway is DiscordSocialActivityEvents
            ? _gateway as DiscordSocialActivityEvents
            : null);
    _inviteSubscription = eventSource?.activityInviteEvents.listen(
      _onInviteEvent,
    );
    final callEventSource =
        callEvents ??
        (_gateway is DiscordSocialCallEvents
            ? _gateway as DiscordSocialCallEvents
            : null);
    _callSubscription = callEventSource?.activityCallEvents.listen(
      _onCallState,
    );
  }

  final DiscordSocialActivityGateway? _gateway;
  final DiscordSocialCallGateway? _callGateway;
  StreamSubscription<DiscordSocialActivityInviteEvent>? _inviteSubscription;
  StreamSubscription<DiscordSocialCallState>? _callSubscription;
  List<DiscordSocialActivityInvite> _invites = const [];
  final Set<String> _acceptingInviteIds = {};
  final Set<String> _invitingUserIds = {};
  final Map<String, String> _inviteErrors = {};
  DiscordSocialActivitySession? _session;
  DiscordSocialCallState? _call;
  String? _callError;
  bool _callPending = false;
  final Set<String> _participantMutePendingUserIds = {};
  final Map<String, String> _participantMuteErrors = {};
  bool _sessionReady = false;
  bool _disposed = false;
  int _generation = 0;

  List<DiscordSocialActivityInvite> get invites => _invites;
  DiscordSocialActivitySession? get session => _session;
  DiscordSocialCallState? get call => _call;
  String? get callError => _callError;
  bool get callPending => _callPending;
  bool get canUseActivities => _sessionReady && _gateway != null;
  bool isAccepting(String inviteId) => _acceptingInviteIds.contains(inviteId);
  bool isInviting(String userId) => _invitingUserIds.contains(userId);
  String? errorFor(String id) => _inviteErrors[id];
  bool isParticipantMutePending(String userId) =>
      _participantMutePendingUserIds.contains(userId);
  String? participantMuteErrorFor(String userId) =>
      _participantMuteErrors[userId];

  void reconcileSession(
    DiscordSocialSdkAvailability? availability, {
    required bool authenticated,
  }) {
    final ready = availability?.isReady == true && authenticated;
    if (_sessionReady == ready) return;
    _sessionReady = ready;
    _generation++;
    _invites = const [];
    _acceptingInviteIds.clear();
    _invitingUserIds.clear();
    _inviteErrors.clear();
    _session = null;
    _call = null;
    _callError = null;
    _callPending = false;
    _participantMutePendingUserIds.clear();
    _participantMuteErrors.clear();
    if (!_disposed) notifyListeners();
  }

  Future<bool> sendInvite(DiscordRelationship relationship) async {
    final userId = relationship.user.id;
    final gateway = _gateway;
    if (!canUseActivities ||
        gateway == null ||
        relationship.kind != DiscordRelationshipKind.friend ||
        _invitingUserIds.contains(userId)) {
      return false;
    }
    final generation = _generation;
    _invitingUserIds.add(userId);
    _inviteErrors.remove(userId);
    notifyListeners();
    try {
      final session = await gateway.sendActivityInvite(userId);
      if (!_accepts(generation)) return false;
      _session = session;
      await _startVoice(generation);
      return true;
    } on DiscordSocialSdkException catch (error) {
      if (_accepts(generation)) {
        _inviteErrors[userId] = error.code;
      }
      return false;
    } on Object {
      if (_accepts(generation)) {
        _inviteErrors[userId] = 'activity_invite_failed';
      }
      return false;
    } finally {
      if (_accepts(generation)) {
        _invitingUserIds.remove(userId);
        notifyListeners();
      }
    }
  }

  Future<bool> acceptInvite(DiscordSocialActivityInvite invite) async {
    final gateway = _gateway;
    if (!canUseActivities ||
        gateway == null ||
        !invite.isValid ||
        _acceptingInviteIds.contains(invite.key)) {
      return false;
    }
    final generation = _generation;
    _acceptingInviteIds.add(invite.key);
    _inviteErrors.remove(invite.key);
    notifyListeners();
    try {
      final session = await gateway.acceptActivityInvite(invite);
      if (!_accepts(generation)) return false;
      _session = session;
      _removeInvite(invite.key);
      await _startVoice(generation);
      return true;
    } on DiscordSocialSdkException catch (error) {
      if (_accepts(generation)) {
        _inviteErrors[invite.key] = error.code;
      }
      return false;
    } on Object {
      if (_accepts(generation)) {
        _inviteErrors[invite.key] = 'activity_join_failed';
      }
      return false;
    } finally {
      if (_accepts(generation)) {
        _acceptingInviteIds.remove(invite.key);
        notifyListeners();
      }
    }
  }

  void dismissInvite(String inviteId) {
    if (_disposed) return;
    _removeInvite(inviteId);
    _inviteErrors.remove(inviteId);
    notifyListeners();
  }

  void clearSessionNotice() {
    if (_session == null ||
        _disposed ||
        _callPending ||
        _call?.isActive == true) {
      return;
    }
    _session = null;
    _call = null;
    _callError = null;
    notifyListeners();
  }

  Future<bool> startVoice() => _startVoice(_generation);

  Future<bool> toggleMuted() {
    final current = _call;
    return _mutateCall(
      (gateway) => gateway.setActivityCallMuted(
        lobbyId: current!.lobbyId,
        muted: !current.selfMuted,
      ),
    );
  }

  Future<bool> toggleDeafened() {
    final current = _call;
    return _mutateCall(
      (gateway) => gateway.setActivityCallDeafened(
        lobbyId: current!.lobbyId,
        deafened: !current.selfDeafened,
      ),
    );
  }

  Future<bool> toggleParticipantMuted(String userId) async {
    final normalizedUserId = userId.trim();
    final gateway = _callGateway;
    final current = _call;
    if (!canUseActivities ||
        gateway == null ||
        current == null ||
        !current.isActive ||
        _callPending ||
        normalizedUserId.isEmpty ||
        normalizedUserId == current.currentUserId ||
        !current.participantUserIds.contains(normalizedUserId) ||
        _participantMutePendingUserIds.contains(normalizedUserId)) {
      return false;
    }
    final generation = _generation;
    final lobbyId = current.lobbyId;
    _participantMutePendingUserIds.add(normalizedUserId);
    _participantMuteErrors.remove(normalizedUserId);
    notifyListeners();
    try {
      final state = await gateway.setActivityParticipantMuted(
        lobbyId: lobbyId,
        userId: normalizedUserId,
        muted: !current.isLocallyMuted(normalizedUserId),
      );
      if (!_accepts(generation) || state.lobbyId != _session?.lobbyId) {
        return false;
      }
      _applyCallState(state);
      return true;
    } on DiscordSocialSdkException catch (error) {
      if (_accepts(generation)) {
        _participantMuteErrors[normalizedUserId] = error.code;
      }
      return false;
    } on Object {
      if (_accepts(generation)) {
        _participantMuteErrors[normalizedUserId] =
            'activity_participant_mute_failed';
      }
      return false;
    } finally {
      if (_accepts(generation)) {
        _participantMutePendingUserIds.remove(normalizedUserId);
        notifyListeners();
      }
    }
  }

  Future<bool> leaveVoice() {
    final current = _call;
    return _mutateCall(
      (gateway) => gateway.leaveActivityCall(current!.lobbyId),
    );
  }

  void _onInviteEvent(DiscordSocialActivityInviteEvent event) {
    if (!canUseActivities || _disposed) return;
    if (!event.invite.isValid) {
      _removeInvite(event.invite.key);
      _inviteErrors.remove(event.invite.key);
      notifyListeners();
      return;
    }
    final next = [..._invites];
    final index = next.indexWhere((item) => item.key == event.invite.key);
    if (index == -1) {
      next.insert(0, event.invite);
      if (next.length > _maximumRetainedInvites) {
        next.removeLast();
      }
    } else {
      next[index] = event.invite;
    }
    _invites = List.unmodifiable(next);
    notifyListeners();
  }

  void _onCallState(DiscordSocialCallState state) {
    if (!canUseActivities || _disposed || state.lobbyId != _session?.lobbyId) {
      return;
    }
    _applyCallState(state);
    _callError = null;
    notifyListeners();
  }

  Future<bool> _startVoice(int generation) async {
    final session = _session;
    final gateway = _callGateway;
    if (!_accepts(generation) ||
        session == null ||
        gateway == null ||
        _callPending ||
        (_call?.isActive == true && _call?.lobbyId == session.lobbyId)) {
      return false;
    }
    return _performCallMutation(
      generation,
      () => gateway.startActivityCall(session.lobbyId),
    );
  }

  Future<bool> _mutateCall(
    Future<DiscordSocialCallState> Function(DiscordSocialCallGateway gateway)
    mutation,
  ) {
    final gateway = _callGateway;
    final current = _call;
    if (!canUseActivities ||
        gateway == null ||
        current == null ||
        !current.isActive ||
        _callPending ||
        _participantMutePendingUserIds.isNotEmpty) {
      return Future.value(false);
    }
    return _performCallMutation(_generation, () => mutation(gateway));
  }

  Future<bool> _performCallMutation(
    int generation,
    Future<DiscordSocialCallState> Function() mutation,
  ) async {
    _callPending = true;
    _callError = null;
    notifyListeners();
    try {
      final state = await mutation();
      if (!_accepts(generation) || state.lobbyId != _session?.lobbyId) {
        return false;
      }
      _applyCallState(state);
      return true;
    } on DiscordSocialSdkException catch (error) {
      if (_accepts(generation)) _callError = error.code;
      return false;
    } on Object {
      if (_accepts(generation)) _callError = 'activity_call_failed';
      return false;
    } finally {
      if (_accepts(generation)) {
        _callPending = false;
        notifyListeners();
      }
    }
  }

  void _removeInvite(String inviteId) {
    _invites = List.unmodifiable(
      _invites.where((invite) => invite.key != inviteId),
    );
  }

  void _applyCallState(DiscordSocialCallState state) {
    _call = state;
    final participants = state.participantUserIds.toSet();
    _participantMutePendingUserIds.retainAll(participants);
    _participantMuteErrors.removeWhere(
      (userId, _) => !participants.contains(userId),
    );
  }

  bool _accepts(int generation) =>
      !_disposed && _sessionReady && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_inviteSubscription?.cancel());
    unawaited(_callSubscription?.cancel());
    super.dispose();
  }
}
