import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/discord_relationship.dart';
import '../domain/discord_social_activity.dart';
import '../domain/discord_social_sdk.dart';

final class DiscordSocialActivityController extends ChangeNotifier {
  static const int _maximumRetainedInvites = 20;

  DiscordSocialActivityController(
    this._gateway, {
    DiscordSocialActivityEvents? events,
  }) {
    final eventSource =
        events ??
        (_gateway is DiscordSocialActivityEvents
            ? _gateway as DiscordSocialActivityEvents
            : null);
    _inviteSubscription = eventSource?.activityInviteEvents.listen(
      _onInviteEvent,
    );
  }

  final DiscordSocialActivityGateway? _gateway;
  StreamSubscription<DiscordSocialActivityInviteEvent>? _inviteSubscription;
  List<DiscordSocialActivityInvite> _invites = const [];
  final Set<String> _acceptingInviteIds = {};
  final Set<String> _invitingUserIds = {};
  final Map<String, String> _inviteErrors = {};
  DiscordSocialActivitySession? _session;
  bool _sessionReady = false;
  bool _disposed = false;
  int _generation = 0;

  List<DiscordSocialActivityInvite> get invites => _invites;
  DiscordSocialActivitySession? get session => _session;
  bool get canUseActivities => _sessionReady && _gateway != null;
  bool isAccepting(String inviteId) => _acceptingInviteIds.contains(inviteId);
  bool isInviting(String userId) => _invitingUserIds.contains(userId);
  String? errorFor(String id) => _inviteErrors[id];

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
    if (_session == null || _disposed) return;
    _session = null;
    notifyListeners();
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

  void _removeInvite(String inviteId) {
    _invites = List.unmodifiable(
      _invites.where((invite) => invite.key != inviteId),
    );
  }

  bool _accepts(int generation) =>
      !_disposed && _sessionReady && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_inviteSubscription?.cancel());
    super.dispose();
  }
}
