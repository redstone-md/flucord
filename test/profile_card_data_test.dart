import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/discord/discord_user_profile_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flucord/src/presentation/widgets/profile_card_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a friend gets the same two-letter monogram a member does', () {
    final data = ProfileCardData.relationship(
      DiscordRelationship(
        user: DiscordRelationshipUser(id: 'u1', displayName: 'Mira Chen'),
        kind: DiscordRelationshipKind.friend,
      ),
    );

    expect(data.monogram, 'MC');
  });

  test('an own profile with no name at all is a question mark', () {
    final data = ProfileCardData.ownProfile(
      const UserProfile(userId: '1', username: ''),
      displayName: '',
      pronouns: '',
      bio: '',
      accentColor: null,
      themeColors: null,
      avatarUrl: null,
      bannerUrl: null,
    );

    expect(data.monogram, '?');
  });

  test('the activity shown skips a custom status and a hang status', () {
    final data = ProfileCardData.member(
      const Member(
        id: 'u1',
        displayName: 'Mira',
        initials: 'M',
        role: '',
        presence: Presence.online,
        colorValue: 0xff000000,
        presenceDetail: UserPresence(
          status: Presence.online,
          activities: [
            UserActivity(
              name: 'Custom Status',
              type: ActivityType.customStatus,
            ),
            UserActivity(name: 'Hang', type: ActivityType.hangStatus),
            UserActivity(name: 'Dota 2'),
          ],
        ),
      ),
    );

    expect(data.activity?.name, 'Dota 2');
  });

  test(
    "a friend outside the workspace shows the name style from their profile",
    () {
      final profile = DiscordUserProfileRepository.readOtherProfile(const {
        'user': {
          'id': 'u1',
          'username': 'mira',
          'display_name_styles': {
            'colors': [0x5865f2],
            'font_id': 3,
            'effect_id': 2,
          },
        },
      });

      final data = ProfileCardData.member(
        const Member(
          id: 'u1',
          displayName: 'Mira',
          initials: 'M',
          role: 'Discord user',
          presence: Presence.unknown,
          colorValue: 0xff000000,
        ),
        profile: profile,
      );

      expect(
        data.nameStyle,
        const NameStyle(colors: [0xff5865f2], fontId: 3, effectId: 2),
      );
    },
  );

  test('a server bio and banner the member payload carries win over a '
      'profile fetched before they changed', () {
    final member = _discordMapper.guildMember({
      'user': {'id': '100000000000000501', 'username': 'mira'},
      'roles': <Object?>[],
      'bio': 'Smith by trade.',
      'banner': 'c3d4',
    }, '100000000000000601');
    const stale = OtherUserProfile(
      userId: '100000000000000501',
      bio: 'Own bio',
      serverProfile: ServerProfile(
        guildId: '100000000000000601',
        bio: 'Old server bio',
        bannerHash: 'a1b2',
      ),
    );

    final data = ProfileCardData.member(
      member,
      spaceId: '100000000000000601',
      profile: stale,
    );

    expect(data.bio, 'Smith by trade.');
    expect(data.bannerUrl, contains('c3d4'));
  });

  test('a member payload without a server bio leaves the fetched one', () {
    final member = _discordMapper.guildMember({
      'user': {'id': '100000000000000501', 'username': 'mira'},
      'roles': <Object?>[],
    }, '100000000000000601');
    const fetched = OtherUserProfile(
      userId: '100000000000000501',
      serverProfile: ServerProfile(
        guildId: '100000000000000601',
        bio: 'Server bio',
        bannerHash: 'a1b2',
      ),
    );

    final data = ProfileCardData.member(
      member,
      spaceId: '100000000000000601',
      profile: fetched,
    );

    expect(data.bio, 'Server bio');
    expect(data.bannerUrl, contains('a1b2'));
  });
}

final _discordMapper = DiscordMapper();
