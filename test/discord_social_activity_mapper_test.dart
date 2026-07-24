import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord_social_activity_mapper.dart';
import 'package:flucord/src/domain/discord_social_activity.dart';

void main() {
  test('maps and re-encodes the exact native activity invite', () {
    final event = DiscordSocialActivityMapper.event({
      'type': 'created',
      'invite': _invitePayload(),
    });

    expect(event.updated, isFalse);
    expect(event.invite.applicationId, '100');
    expect(event.invite.parentApplicationId, '0');
    expect(event.invite.senderId, '500');
    expect(event.invite.type, DiscordSocialActivityInviteType.join);
    expect(event.invite.isValid, isTrue);
    expect(DiscordSocialActivityMapper.encode(event.invite), _invitePayload());
  });

  test('maps joined lobby sessions and rejects malformed payloads', () {
    final session = DiscordSocialActivityMapper.session({'lobby_id': 700});

    expect(session.lobbyId, '700');
    expect(
      () => DiscordSocialActivityMapper.event({'type': 'created'}),
      throwsA(anyOf(isA<FormatException>(), isA<ArgumentError>())),
    );
    expect(
      () => DiscordSocialActivityMapper.session({'lobby_id': '0'}),
      throwsArgumentError,
    );
  });
}

Map<String, Object> _invitePayload() => {
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
