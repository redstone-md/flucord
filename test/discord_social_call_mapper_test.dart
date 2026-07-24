import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord_social_call_mapper.dart';
import 'package:flucord/src/domain/discord_social_call.dart';

void main() {
  test('maps exact activity voice state from the native bridge', () {
    final state = DiscordSocialCallMapper.state({
      'lobby_id': '700',
      'status': 'connected',
      'participant_user_ids': ['500', 501, '500'],
      'self_muted': true,
      'self_deafened': false,
    });

    expect(state.lobbyId, '700');
    expect(state.status, DiscordSocialCallStatus.connected);
    expect(state.participantUserIds, ['500', '501']);
    expect(state.selfMuted, isTrue);
    expect(state.selfDeafened, isFalse);
    expect(state.isActive, isTrue);
  });

  test('rejects incomplete and invalid activity voice payloads', () {
    expect(
      () => DiscordSocialCallMapper.state({'lobby_id': '700'}),
      throwsFormatException,
    );
    expect(
      () => DiscordSocialCallMapper.state({
        'lobby_id': '0',
        'status': 'disconnected',
        'participant_user_ids': const [],
        'self_muted': false,
        'self_deafened': false,
      }),
      throwsFormatException,
    );
  });
}
