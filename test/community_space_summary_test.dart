import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a guild payload gives the member count and the join date', () {
    final space = DiscordMapper().spaceFromGuildPayload({
      'id': 'guild-1',
      'name': 'The Forge',
      'member_count': 1234,
      'joined_at': '2024-03-03T10:00:00.000000+00:00',
    });

    expect(space.memberCount, 1234);
    expect(space.joinedAt, DateTime.utc(2024, 3, 3, 10));
  });

  test('a guild update without them keeps the ones already known', () {
    final workspace =
        ChatWorkspace(
              spaces: const [],
              channels: const [],
              members: const [],
              messages: const [],
              currentMemberId: 'me',
            )
            .upsertSpace(
              DiscordMapper().spaceFromGuildPayload({
                'id': 'guild-1',
                'name': 'The Forge',
                'member_count': 1234,
                'joined_at': '2024-03-03T10:00:00+00:00',
              }),
            )
            .upsertSpace(
              DiscordMapper().spaceFromGuildPayload({
                'id': 'guild-1',
                'name': 'The New Forge',
              }),
            );

    final space = workspace.spaceOrNull('guild-1')!;
    expect(space.name, 'The New Forge');
    expect(space.memberCount, 1234);
    expect(space.joinedAt, DateTime.utc(2024, 3, 3, 10));
  });
}
