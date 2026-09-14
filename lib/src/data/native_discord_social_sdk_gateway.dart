import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

export 'discord_social_sdk_platform_channel.dart';

import '../domain/discord_relationship.dart';
import '../domain/discord_social_activity.dart';
import '../domain/discord_social_call.dart';
import '../domain/discord_social_dm.dart';
import '../domain/discord_social_presence.dart';
import '../domain/discord_social_sdk.dart';
import 'discord_social_activity_mapper.dart';
import 'discord_social_call_mapper.dart';
import 'discord_social_dm_mapper.dart';
import 'discord_social_lobby_secret.dart';
import 'discord_social_relationship_mapper.dart';
import 'discord_social_sdk_event_router.dart';
import 'discord_social_sdk_platform_channel.dart';
import 'discord_social_sdk_response_codec.dart';
import 'secure_discord_social_sdk_vault.dart';

final class NativeDiscordSocialSdkGateway
    implements
        DiscordSocialSdkGateway,
        DiscordSocialSdkAuthenticationEvents,
        DiscordSocialCurrentUserGateway,
        DiscordSocialFriendRequestGateway,
        DiscordSocialRelationshipEvents,
        DiscordSocialPresenceGateway,
        DiscordSocialActivityGateway,
        DiscordSocialActivityEvents,
        DiscordSocialCallGateway,
        DiscordSocialCallEvents,
        DiscordSocialDmGateway,
        DiscordSocialDmEvents {
  NativeDiscordSocialSdkGateway({
    DiscordSocialSdkPlatformChannel? channel,
    this._targetPlatform,
    DiscordSocialSdkConfiguration? configuration,
    this._vault = const SecureDiscordSocialSdkGrantVault(),
    this._clock = DateTime.now,
    this._activitySecretFactory = DiscordSocialLobbySecret.generate,
  }) : _channel = channel ?? FlutterDiscordSocialSdkPlatformChannel(),
       _configuration =
           configuration ?? DiscordSocialSdkConfiguration.fromEnvironment() {
    _eventRouter = DiscordSocialSdkEventRouter(
      persistGrant: _persistGrant,
      clearGrant: _vault.clear,
      currentAuthentication: _currentAuthentication,
      authentications: _authChanges,
      dmEvents: _dmEvents,
      relationshipUpdates: _relationshipUpdates,
      activityInvites: _activityInvites,
      activityCalls: _activityCalls,
    );
    _channel.setNativeHandler(_eventRouter.handle);
  }

  final DiscordSocialSdkPlatformChannel _channel;
  final TargetPlatform? _targetPlatform;
  final DiscordSocialSdkConfiguration? _configuration;
  final DiscordSocialSdkGrantVault _vault;
  final DiscordSocialSdkClock _clock;
  final DiscordSocialActivitySecretFactory _activitySecretFactory;
  late final DiscordSocialSdkEventRouter _eventRouter;
  final StreamController<DiscordSocialSdkAuthentication> _authChanges =
      StreamController.broadcast(sync: true);
  final StreamController<DiscordSocialDmEvent> _dmEvents =
      StreamController.broadcast(sync: true);
  final StreamController<DiscordSocialRelationshipUpdate> _relationshipUpdates =
      StreamController.broadcast(sync: true);
  final StreamController<DiscordSocialActivityInviteEvent> _activityInvites =
      StreamController.broadcast(sync: true);
  final StreamController<DiscordSocialCallState> _activityCalls =
      StreamController.broadcast(sync: true);

  @override
  Stream<DiscordSocialSdkAuthentication> get authenticationChanges =>
      _authChanges.stream;

  @override
  Stream<DiscordSocialDmEvent> get socialDmEvents => _dmEvents.stream;

  @override
  Stream<DiscordSocialRelationshipUpdate> get relationshipUpdates =>
      _relationshipUpdates.stream;

  @override
  Stream<DiscordSocialActivityInviteEvent> get activityInviteEvents =>
      _activityInvites.stream;

  @override
  Stream<DiscordSocialCallState> get activityCallEvents =>
      _activityCalls.stream;

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async {
    if (!_isSupportedPlatform) {
      return DiscordSocialSdkAvailability.unsupportedPlatform;
    }
    try {
      final response = await _channel.invoke('getAvailability');
      return DiscordSocialSdkResponseCodec.availability(response);
    } on MissingPluginException {
      return DiscordSocialSdkAvailability.unsupportedPlatform;
    } on PlatformException catch (error) {
      return DiscordSocialSdkAvailability.failure(
        'platform_${DiscordSocialSdkResponseCodec.safeCode(error.code)}',
      );
    } on Object {
      return DiscordSocialSdkAvailability.failure('channel_failure');
    }
  }

  @override
  Future<DiscordSocialSdkAuthentication> restoreAuthentication() async {
    final configuration = _configuration;
    if (configuration == null) {
      return DiscordSocialSdkAuthentication.unconfigured;
    }
    _requireSupportedPlatform();
    final grant = await _vault.read();
    if (grant == null) return DiscordSocialSdkAuthentication.signedOut;
    try {
      final response = await _invoke(
        'restoreSession',
        arguments: {
          'client_id': configuration.clientId,
          'refresh_token': grant.refreshToken,
        },
      );
      await _persistGrant(response);
      return await _currentAuthentication();
    } on DiscordSocialSdkException catch (error) {
      if (_invalidIdentityCodes.contains(error.code)) {
        await _discardInvalidIdentity();
        return DiscordSocialSdkAuthentication.signedOut;
      }
      if (!_invalidGrantCodes.contains(error.code)) rethrow;
      await _vault.clear();
      return DiscordSocialSdkAuthentication.signedOut;
    }
  }

  @override
  Future<DiscordSocialSdkAuthentication> authorize() async {
    final configuration = _configuration;
    if (configuration == null) {
      return DiscordSocialSdkAuthentication.unconfigured;
    }
    _requireSupportedPlatform();
    try {
      final response = await _invoke(
        'authorize',
        arguments: {'client_id': configuration.clientId},
      );
      await _persistGrant(response);
      return await _currentAuthentication();
    } on DiscordSocialSdkException catch (error) {
      if (_invalidIdentityCodes.contains(error.code)) {
        await _discardInvalidIdentity();
      }
      rethrow;
    }
  }

  @override
  Future<String> fetchCurrentUserId() async {
    _requireSupportedPlatform();
    final response = await _invoke('getCurrentUser');
    if (response case {'user_id': final Object? rawId}) {
      final userId = switch (rawId) {
        final String value => value.trim(),
        final int value => value.toString(),
        _ => '',
      };
      if (RegExp(r'^[1-9][0-9]*$').hasMatch(userId)) return userId;
    }
    throw const DiscordSocialSdkException('invalid_identity_response');
  }

  @override
  Future<void> disconnect() async {
    try {
      if (_isSupportedPlatform) await _invoke('disconnect');
    } finally {
      await _vault.clear();
    }
  }

  @override
  Future<List<DiscordSocialDmConversation>> fetchConversations() async {
    _requireSupportedPlatform();
    try {
      return DiscordSocialDmMapper.conversations(
        await _invoke('getDmConversations'),
      );
    } on FormatException {
      throw const DiscordSocialSdkException('invalid_dm_response');
    }
  }

  @override
  Future<List<DiscordSocialDmMessage>> fetchMessages({
    required String userId,
    int limit = 100,
  }) async {
    _requireSupportedPlatform();
    try {
      return DiscordSocialDmMapper.messages(
        await _invoke(
          'getDmMessages',
          arguments: {'user_id': userId, 'limit': limit.clamp(1, 100)},
        ),
      );
    } on FormatException {
      throw const DiscordSocialSdkException('invalid_dm_response');
    }
  }

  @override
  Future<String> sendMessage({
    required String userId,
    required String content,
  }) async {
    _requireSupportedPlatform();
    _validateMessageContent(content);
    final response = await _invoke(
      'sendDmMessage',
      arguments: {'user_id': userId, 'content': content},
    );
    if (response case {'message_id': final Object? rawId}) {
      final messageId = switch (rawId) {
        final String value => value.trim(),
        final int value => value.toString(),
        _ => '',
      };
      if (messageId.isNotEmpty) return messageId;
    }
    throw const DiscordSocialSdkException('invalid_dm_response');
  }

  @override
  Future<void> editMessage({
    required String userId,
    required String messageId,
    required String content,
  }) async {
    _requireSupportedPlatform();
    _validateMessageContent(content);
    await _invoke(
      'editDmMessage',
      arguments: {
        'user_id': userId,
        'message_id': messageId,
        'content': content,
      },
    );
  }

  @override
  Future<void> deleteMessage({
    required String userId,
    required String messageId,
  }) async {
    _requireSupportedPlatform();
    await _invoke(
      'deleteDmMessage',
      arguments: {'user_id': userId, 'message_id': messageId},
    );
  }

  @override
  Future<void> setShowingChat(bool showing) async {
    _requireSupportedPlatform();
    await _invoke('setShowingChat', arguments: {'showing': showing});
  }

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async {
    _requireSupportedPlatform();
    try {
      final response = await _channel.invoke('getRelationships');
      return DiscordSocialRelationshipMapper.decode(response);
    } on MissingPluginException {
      throw const DiscordSocialSdkException('unsupported_platform');
    } on PlatformException catch (error) {
      throw DiscordSocialSdkException(
        DiscordSocialSdkResponseCodec.safeCode(error.code),
      );
    } on FormatException {
      throw const DiscordSocialSdkException('invalid_response');
    } on DiscordSocialSdkException {
      rethrow;
    } on Object {
      throw const DiscordSocialSdkException('channel_failure');
    }
  }

  @override
  Future<void> updateRelationship({
    required String userId,
    required DiscordRelationshipAction action,
  }) async {
    _requireSupportedPlatform();
    await _invoke(
      'updateRelationship',
      arguments: {'user_id': userId, 'action': _actionName(action)},
    );
  }

  @override
  Future<void> sendFriendRequest(String userId) async {
    _requireSupportedPlatform();
    await _invoke('sendFriendRequest', arguments: {'user_id': userId.trim()});
  }

  @override
  Future<void> setOnlineStatus(DiscordOnlineStatus status) async {
    _requireSupportedPlatform();
    await _invoke(
      'setOnlineStatus',
      arguments: {'status': _onlineStatusName(status)},
    );
  }

  @override
  Future<DiscordSocialActivitySession> sendActivityInvite(String userId) async {
    _requireSupportedPlatform();
    try {
      return DiscordSocialActivityMapper.session(
        await _invoke(
          'sendActivityInvite',
          arguments: {
            'user_id': userId.trim(),
            'lobby_secret': _activitySecretFactory(),
          },
        ),
      );
    } on FormatException {
      throw const DiscordSocialSdkException('invalid_activity_response');
    }
  }

  @override
  Future<DiscordSocialActivitySession> acceptActivityInvite(
    DiscordSocialActivityInvite invite,
  ) async {
    _requireSupportedPlatform();
    try {
      return DiscordSocialActivityMapper.session(
        await _invoke(
          'acceptActivityInvite',
          arguments: DiscordSocialActivityMapper.encode(invite),
        ),
      );
    } on FormatException {
      throw const DiscordSocialSdkException('invalid_activity_response');
    }
  }

  @override
  Future<DiscordSocialCallState> startActivityCall(String lobbyId) =>
      _callMutation('startActivityCall', lobbyId);

  @override
  Future<DiscordSocialCallState> setActivityCallMuted({
    required String lobbyId,
    required bool muted,
  }) => _callMutation('setActivityCallMuted', lobbyId, value: muted);

  @override
  Future<DiscordSocialCallState> setActivityCallDeafened({
    required String lobbyId,
    required bool deafened,
  }) => _callMutation('setActivityCallDeafened', lobbyId, value: deafened);

  @override
  Future<DiscordSocialCallState> setActivityParticipantMuted({
    required String lobbyId,
    required String userId,
    required bool muted,
  }) => _callMutation(
    'setActivityParticipantMuted',
    lobbyId,
    userId: userId,
    value: muted,
  );

  @override
  Future<DiscordSocialCallState> leaveActivityCall(String lobbyId) =>
      _callMutation('leaveActivityCall', lobbyId);

  Future<void> _persistGrant(Object? response) async {
    final grant = DiscordSocialSdkResponseCodec.grant(response, _clock);
    await _vault.write(grant);
  }

  Future<DiscordSocialCallState> _callMutation(
    String method,
    String lobbyId, {
    String? userId,
    bool? value,
  }) async {
    _requireSupportedPlatform();
    final normalizedUserId = userId?.trim();
    try {
      return DiscordSocialCallMapper.state(
        await _invoke(
          method,
          arguments: {
            'lobby_id': lobbyId.trim(),
            'user_id': ?normalizedUserId,
            'value': ?value,
          },
        ),
      );
    } on FormatException {
      throw const DiscordSocialSdkException('invalid_activity_call_response');
    }
  }

  Future<DiscordSocialSdkAuthentication> _currentAuthentication() async =>
      DiscordSocialSdkAuthentication.readyFor(await fetchCurrentUserId());

  Future<void> _discardInvalidIdentity() async {
    try {
      await _invoke('disconnect');
    } on DiscordSocialSdkException {
      // The local grant must still be discarded if native teardown fails.
    }
    await _vault.clear();
  }

  Future<Object?> _invoke(String method, {Object? arguments}) async {
    try {
      return await _channel.invoke(method, arguments);
    } on MissingPluginException {
      throw const DiscordSocialSdkException('unsupported_platform');
    } on PlatformException catch (error) {
      throw DiscordSocialSdkException(
        DiscordSocialSdkResponseCodec.safeCode(error.code),
      );
    } on DiscordSocialSdkException {
      rethrow;
    } on Object {
      throw const DiscordSocialSdkException('channel_failure');
    }
  }

  void _requireSupportedPlatform() {
    if (!_isSupportedPlatform) {
      throw const DiscordSocialSdkException('unsupported_platform');
    }
  }

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (_targetPlatform ?? defaultTargetPlatform) == TargetPlatform.windows;

  static void _validateMessageContent(String content) {
    if (content.trim().isEmpty || content.length > 2000) {
      throw const DiscordSocialSdkException('invalid_message_content');
    }
  }

  static String _actionName(DiscordRelationshipAction action) =>
      switch (action) {
        DiscordRelationshipAction.acceptRequest => 'accept_request',
        DiscordRelationshipAction.rejectRequest => 'reject_request',
        DiscordRelationshipAction.cancelRequest => 'cancel_request',
        DiscordRelationshipAction.removeFriend => 'remove_friend',
        DiscordRelationshipAction.blockUser => 'block_user',
      };

  static String _onlineStatusName(DiscordOnlineStatus status) =>
      switch (status) {
        DiscordOnlineStatus.online => 'online',
        DiscordOnlineStatus.idle => 'idle',
        DiscordOnlineStatus.doNotDisturb => 'dnd',
        DiscordOnlineStatus.invisible => 'invisible',
      };

  static const _invalidGrantCodes = {
    'not_authenticated',
    'refresh_failed',
    'authorization_expired',
  };
  static const _invalidIdentityCodes = {
    'current_user_unavailable',
    'invalid_identity_response',
  };
}
