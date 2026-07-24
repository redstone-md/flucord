import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord_social_relationship_mapper.dart';
import 'package:flucord/src/domain/discord_relationship.dart';

void main() {
  test('maps native friend identity, presence, and request metadata', () {
    final relationships = DiscordSocialRelationshipMapper.decode([
      {
        'id': 123456789,
        'display_name': 'Ada',
        'username': 'ada.dev',
        'avatar_url': 'https://cdn.discordapp.com/avatar.png',
        'status': 'do_not_disturb',
        'relationship_type': 'pending_incoming',
        'is_provisional': true,
        'is_spam_request': true,
      },
    ]);

    final relationship = relationships.single;
    expect(relationship.user.id, '123456789');
    expect(relationship.user.displayName, 'Ada');
    expect(relationship.user.username, 'ada.dev');
    expect(relationship.user.status, DiscordPresenceStatus.doNotDisturb);
    expect(relationship.user.isProvisional, isTrue);
    expect(relationship.kind, DiscordRelationshipKind.incomingRequest);
    expect(relationship.isSpamRequest, isTrue);
  });

  test('falls back to stable identity and rejects invalid remote URLs', () {
    final relationships = DiscordSocialRelationshipMapper.decode([
      {
        'id': 'user-2',
        'display_name': '',
        'username': 'nightshift',
        'avatar_url': 'file:///private/avatar.png',
        'status': 'offline',
        'relationship_type': 'friend',
      },
    ]);

    expect(relationships.single.user.displayName, 'nightshift');
    expect(relationships.single.user.avatarUrl, isNull);
    expect(relationships.single.kind, DiscordRelationshipKind.friend);
  });

  test('rejects malformed channel payloads', () {
    expect(
      () => DiscordSocialRelationshipMapper.decode({'id': 'not-a-list'}),
      throwsFormatException,
    );
    expect(
      () => DiscordSocialRelationshipMapper.decode([
        {'display_name': 'Missing id'},
      ]),
      throwsFormatException,
    );
  });
}
