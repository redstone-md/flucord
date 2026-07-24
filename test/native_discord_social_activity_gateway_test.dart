import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/native_discord_social_sdk_gateway.dart';
import 'package:flucord/src/domain/discord_social_activity.dart';
import 'package:flucord/src/domain/discord_social_call.dart';

void main() {
  test('maps activity send and accept to the native wire contract', () async {
    final channel = _Channel({'lobby_id': '700'});
    final gateway = NativeDiscordSocialSdkGateway(
      channel: channel,
      targetPlatform: TargetPlatform.windows,
      activitySecretFactory: () => 'ephemeral-secret',
    );
    final invite = _invite();

    final hosted = await gateway.sendActivityInvite(' 500 ');
    final joined = await gateway.acceptActivityInvite(invite);

    expect(hosted.lobbyId, '700');
    expect(joined.lobbyId, '700');
    expect(channel.calls, ['sendActivityInvite', 'acceptActivityInvite']);
    expect(channel.arguments.first, {
      'user_id': '500',
      'lobby_secret': 'ephemeral-secret',
    });
    expect(channel.arguments.last, {
      'application_id': '100',
      'parent_application_id': '0',
      'channel_id': '300',
      'message_id': '400',
      'sender_id': '500',
      'party_id': 'party',
      'session_id': 'session',
      'invite_type': 'join',
      'is_valid': true,
    });
  });

  test('decodes native activity invite callbacks', () async {
    final channel = _Channel(null);
    final gateway = NativeDiscordSocialSdkGateway(
      channel: channel,
      targetPlatform: TargetPlatform.windows,
    );
    final expectation = expectLater(
      gateway.activityInviteEvents,
      emits(
        isA<DiscordSocialActivityInviteEvent>()
            .having((event) => event.updated, 'updated', isTrue)
            .having((event) => event.invite.senderId, 'sender', '500'),
      ),
    );

    await channel.emit('socialActivityInviteChanged', {
      'type': 'updated',
      'invite': _payload(),
    });

    await expectation;
  });

  test('maps activity voice controls and live state callbacks', () async {
    final channel = _Channel(_callPayload());
    final gateway = NativeDiscordSocialSdkGateway(
      channel: channel,
      targetPlatform: TargetPlatform.windows,
    );

    final started = await gateway.startActivityCall('700');
    await gateway.setActivityCallMuted(lobbyId: '700', muted: true);
    await gateway.setActivityCallDeafened(lobbyId: '700', deafened: true);
    await gateway.leaveActivityCall('700');

    expect(started.status, DiscordSocialCallStatus.connected);
    expect(channel.calls, [
      'startActivityCall',
      'setActivityCallMuted',
      'setActivityCallDeafened',
      'leaveActivityCall',
    ]);
    expect(channel.arguments, [
      {'lobby_id': '700'},
      {'lobby_id': '700', 'value': true},
      {'lobby_id': '700', 'value': true},
      {'lobby_id': '700'},
    ]);

    final expectation = expectLater(
      gateway.activityCallEvents,
      emits(
        isA<DiscordSocialCallState>().having(
          (state) => state.participantUserIds,
          'participants',
          ['500'],
        ),
      ),
    );
    await channel.emit('socialActivityCallChanged', _callPayload());
    await expectation;
  });
}

DiscordSocialActivityInvite _invite() => DiscordSocialActivityInvite(
  applicationId: '100',
  parentApplicationId: '0',
  channelId: '300',
  messageId: '400',
  senderId: '500',
  partyId: 'party',
  sessionId: 'session',
  type: DiscordSocialActivityInviteType.join,
  isValid: true,
);

Map<String, Object> _payload() => {
  'application_id': '100',
  'parent_application_id': '0',
  'channel_id': '300',
  'message_id': '400',
  'sender_id': '500',
  'party_id': 'party',
  'session_id': 'session',
  'invite_type': 'join',
  'is_valid': true,
};

Map<String, Object> _callPayload() => {
  'lobby_id': '700',
  'status': 'connected',
  'participant_user_ids': ['500'],
  'self_muted': false,
  'self_deafened': false,
};

final class _Channel implements DiscordSocialSdkPlatformChannel {
  _Channel(this.response);

  final Object? response;
  final List<String> calls = [];
  final List<Object?> arguments = [];
  DiscordSocialSdkNativeHandler? handler;

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    calls.add(method);
    this.arguments.add(arguments);
    return response;
  }

  @override
  void setNativeHandler(DiscordSocialSdkNativeHandler? handler) {
    this.handler = handler;
  }

  Future<Object?> emit(String method, Object? arguments) {
    final current = handler;
    if (current == null) throw StateError('Missing native handler.');
    return current(method, arguments);
  }
}
