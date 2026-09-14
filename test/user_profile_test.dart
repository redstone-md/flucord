import 'package:flucord/src/application/user_profile_controller.dart';
import 'package:flucord/src/data/discord/discord_user_profile_repository.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('profile mapping', () {
    test('reads a user object and collapses absent text to empty', () {
      final profile = DiscordUserProfileRepository.readProfile(const {
        'id': '123456789012345678',
        'username': 'rxflex',
        'global_name': null,
        'discriminator': '0',
        'avatar': 'hash',
        'banner': '',
        'accent_color': 0x5865F2,
      })!;

      expect(profile.displayName, '');
      expect(profile.effectiveName, 'rxflex');
      expect(profile.hasLegacyDiscriminator, isFalse);
      expect(profile.avatarHash, 'hash');
      // An empty banner is no banner, not a banner named "".
      expect(profile.bannerHash, isNull);
      expect(profile.accentColor, 0x5865F2);
    });

    test('rejects a payload with no id', () {
      expect(DiscordUserProfileRepository.readProfile(const {}), isNull);
      expect(
        DiscordUserProfileRepository.readProfile(const {'id': 42}),
        isNull,
      );
    });

    test('keeps a legacy discriminator visible', () {
      final profile = DiscordUserProfileRepository.readProfile(const {
        'id': '123456789012345678',
        'username': 'rxflex',
        'discriminator': '1234',
      })!;

      expect(profile.hasLegacyDiscriminator, isTrue);
    });
  });

  group('other-user profile mapping', () {
    test('reads a full profile payload', () {
      final profile = DiscordUserProfileRepository.readOtherProfile(const {
        'user': {
          'id': '222222222222222222',
          'username': 'mira',
          'global_name': 'Mira Chen',
          'discriminator': '0',
          'avatar': 'mhash',
          'banner': 'a_bhash',
          'accent_color': 0x5865f2,
          'avatar_decoration_data': {
            'asset': 'a_deco',
            'sku_id': '444444444444444444',
          },
        },
        'user_profile': {
          'pronouns': 'she/her',
          'bio': 'ships the parser',
          'banner': 'a_bhash',
          'accent_color': 0x5865f2,
        },
        'badges': [
          {
            'id': 'legacy_username',
            'description': 'Originally known as mira#1234',
            'icon': '6de27dcd513adaa7c2eb5a206fb0d47c',
          },
        ],
        'connected_accounts': [
          {'type': 'twitter', 'id': '123', 'name': 'discord', 'verified': true},
          {'type': 'github', 'id': '456', 'name': 'mira'},
        ],
        'mutual_guilds': [
          {'id': '666666666666666666', 'nick': 'Liena'},
          {'id': '999'},
        ],
        'mutual_friends': [
          {
            'id': '333333333333333333',
            'username': 'roman',
            'global_name': 'Roman Vale',
          },
        ],
      })!;

      expect(profile.userId, '222222222222222222');
      expect(profile.effectiveName, 'Mira Chen');
      expect(profile.bio, 'ships the parser');
      expect(profile.pronouns, 'she/her');
      expect(profile.avatarHash, 'mhash');
      expect(profile.bannerHash, 'a_bhash');
      expect(profile.accentColor, 0x5865f2);
      expect(profile.decoration?.asset, 'a_deco');
      expect(profile.decoration?.skuId, '444444444444444444');
      expect(profile.badges.single.description, contains('mira#1234'));
      expect(profile.connections, hasLength(2));
      expect(profile.connections.first.type, 'twitter');
      expect(profile.connections.first.verified, isTrue);
      expect(profile.connections[1].verified, isFalse);
      expect(profile.mutualServers, hasLength(2));
      expect(profile.mutualServers.first.nickname, 'Liena');
      expect(profile.mutualServers[1].id, '999');
      expect(profile.mutualFriends.single.displayName, 'Roman Vale');
      expect(profile.mutualFriends.single.username, 'roman');
    });

    test('a redacted or bare profile falls back per field', () {
      final profile = DiscordUserProfileRepository.readOtherProfile(const {
        'user': {'id': '222222222222222222', 'username': 'mira'},
        'user_profile': {},
      })!;

      expect(profile.effectiveName, 'mira');
      expect(profile.bio, '');
      expect(profile.pronouns, '');
      expect(profile.avatarHash, isNull);
      expect(profile.bannerHash, isNull);
      expect(profile.accentColor, isNull);
      expect(profile.decoration, isNull);
      expect(profile.badges, isEmpty);
      expect(profile.connections, isEmpty);
      expect(profile.mutualServers, isEmpty);
      expect(profile.mutualFriends, isEmpty);
    });

    test('a payload with no user is refused', () {
      expect(DiscordUserProfileRepository.readOtherProfile(const {}), isNull);
      expect(
        DiscordUserProfileRepository.readOtherProfile(const {
          'user': {'id': 42},
        }),
        isNull,
      );
    });

    test('a mutual friend with no display name falls back to the handle', () {
      final profile = DiscordUserProfileRepository.readOtherProfile(const {
        'user': {'id': '222222222222222222'},
        'mutual_friends': [
          {'id': '333', 'username': 'roman'},
        ],
      })!;

      expect(profile.mutualFriends.single.displayName, 'roman');
    });

    test('the repository fetches the other user over the transport', () async {
      final transport = _FakeTransport();
      final repository = DiscordUserProfileRepository(transport);
      addTearDown(repository.close);

      final profile = await repository.loadProfileOf('222222222222222222');

      expect(transport.requestedProfileIds, ['222222222222222222']);
      expect(profile, isNotNull);
      expect(profile!.userId, '222222222222222222');
    });

    test('a refused or empty fetch answers null without throwing', () async {
      final refused = _FakeTransport()..refuseProfile = true;
      final repository = DiscordUserProfileRepository(refused);
      addTearDown(repository.close);
      expect(await repository.loadProfileOf('222222222222222222'), isNull);

      expect(await repository.loadProfileOf('  '), isNull);
    });
  });

  group('patch', () {
    test('sends only what was touched', () {
      expect(const UserProfilePatch().isEmpty, isTrue);
      expect(const UserProfilePatch().toJson(), isEmpty);
      expect(const UserProfilePatch(displayName: 'Rx').toJson(), {
        'global_name': 'Rx',
      });
    });

    test('distinguishes leaving an image alone from removing it', () {
      // Absence and null mean different things here: omitting the key keeps the
      // current image, sending null deletes it. Collapsing the two would let an
      // unrelated save strip an avatar nobody touched.
      expect(const UserProfilePatch().toJson().containsKey('avatar'), isFalse);
      expect(
        const UserProfilePatch(avatar: ProfileImage.removed()).toJson(),
        containsPair('avatar', null),
      );
      expect(
        const UserProfilePatch(
          avatar: ProfileImage.replaced('data:image/png;base64,AAA'),
        ).toJson(),
        containsPair('avatar', 'data:image/png;base64,AAA'),
      );
    });

    test('an accent colour can be cleared as well as set', () {
      expect(
        const UserProfilePatch(accentColor: ProfileValue.cleared()).toJson(),
        containsPair('accent_color', null),
      );
      expect(
        const UserProfilePatch(accentColor: ProfileValue.set(255)).toJson(),
        containsPair('accent_color', 255),
      );
    });
  });

  group('value semantics', () {
    const profile = UserProfile(
      userId: '123456789012345678',
      username: 'rxflex',
      displayName: 'Rx',
      bio: 'about',
      pronouns: 'they/them',
      avatarHash: 'a',
      bannerHash: 'b',
      accentColor: 1,
    );

    test('copyWith replaces only what it is given', () {
      final copy = profile.copyWith(
        username: 'other',
        displayName: 'Other',
        discriminator: '1',
        bio: 'b',
        pronouns: 'she/her',
        avatarHash: 'x',
        bannerHash: 'y',
        accentColor: 2,
      );

      expect(copy.userId, profile.userId);
      expect(copy.username, 'other');
      expect(copy.accentColor, 2);
      expect(profile.copyWith(), profile);
      expect(profile.copyWith().hashCode, profile.hashCode);
      expect(profile == copy, isFalse);
      expect(profile == Object(), isFalse);
    });
  });

  group('controller', () {
    test('a transport with no profile plane offers nothing', () async {
      final controller = UserProfileController(() => null);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.isSupported, isFalse);
      expect(await controller.save(), isFalse);
    });

    test('typing a value back is not a change', () async {
      final transport = _FakeTransport();
      final controller = UserProfileController(
        () => DiscordUserProfileRepository(transport),
      );
      addTearDown(controller.dispose);
      await controller.load();

      controller.editDisplayName('changed');
      expect(controller.hasChanges, isTrue);

      controller.editDisplayName('Rx');
      expect(controller.hasChanges, isFalse);
    });

    test('a save writes the patch and adopts the server echo', () async {
      final transport = _FakeTransport();
      final controller = UserProfileController(
        () => DiscordUserProfileRepository(transport),
      );
      addTearDown(controller.dispose);
      await controller.load();

      controller
        ..editDisplayName('  Rx Two  ')
        ..editBio('hello');
      expect(await controller.save(), isTrue);

      expect(transport.patches.single, {
        'global_name': '  Rx Two  ',
        'bio': 'hello',
      });
      // The server trims; the client must show what the account actually has.
      expect(controller.profile?.displayName, 'Rx Two');
      expect(controller.hasChanges, isFalse);
    });

    test('a failed save keeps the draft and reports the error', () async {
      final transport = _FakeTransport()..failWrites = true;
      final controller = UserProfileController(
        () => DiscordUserProfileRepository(transport),
      );
      addTearDown(controller.dispose);
      await controller.load();

      controller.editBio('kept');
      expect(await controller.save(), isFalse);

      expect(controller.error, isNotNull);
      expect(controller.bio, 'kept');
      expect(controller.hasChanges, isTrue);
    });

    test('discarding restores the saved values', () async {
      final transport = _FakeTransport();
      final controller = UserProfileController(
        () => DiscordUserProfileRepository(transport),
      );
      addTearDown(controller.dispose);
      await controller.load();

      controller
        ..editDisplayName('temp')
        ..editAvatar(null)
        ..discard();

      expect(controller.displayName, 'Rx');
      expect(controller.pendingAvatar.isUntouched, isTrue);
      expect(controller.hasChanges, isFalse);
    });

    test('pronouns and accent colour reach the patch', () async {
      final transport = _FakeTransport();
      final controller = UserProfileController(
        () => DiscordUserProfileRepository(transport),
      );
      addTearDown(controller.dispose);
      await controller.load();

      controller
        ..editPronouns('they/them')
        ..editAccentColor(0x5865F2);
      expect(controller.pronouns, 'they/them');
      expect(await controller.save(), isTrue);

      expect(transport.patches.single, {
        'pronouns': 'they/them',
        'accent_color': 0x5865F2,
      });

      controller.editAccentColor(null);
      expect(await controller.save(), isTrue);
      expect(transport.patches.last, containsPair('accent_color', null));
    });

    test('a staged avatar reaches the patch', () async {
      final transport = _FakeTransport();
      final controller = UserProfileController(
        () => DiscordUserProfileRepository(transport),
      );
      addTearDown(controller.dispose);
      await controller.load();

      controller.editAvatar('data:image/png;base64,AAA');
      expect(controller.pendingAvatar.dataUri, 'data:image/png;base64,AAA');
      expect(await controller.save(), isTrue);

      expect(
        transport.patches.single,
        containsPair('avatar', 'data:image/png;base64,AAA'),
      );
    });

    test(
      'a failed load is reported and does not wedge the controller',
      () async {
        final transport = _FakeTransport()..failReads = true;
        final controller = UserProfileController(
          () => DiscordUserProfileRepository(transport),
        );
        addTearDown(controller.dispose);

        await controller.load();

        expect(controller.error, isNotNull);
        expect(controller.isLoading, isFalse);
        expect(controller.profile, isNull);

        transport.failReads = false;
        await controller.load();
        expect(controller.profile?.username, 'rxflex');
      },
    );

    test('an empty save is refused before it reaches the transport', () async {
      final transport = _FakeTransport();
      final repository = DiscordUserProfileRepository(transport);
      final controller = UserProfileController(() => repository);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.save(), isFalse);
      expect(transport.patches, isEmpty);
      expect(await repository.apply(const UserProfilePatch()), isNotNull);
      expect(transport.patches, isEmpty);

      await repository.close();
      await repository.close();
    });

    test('an unusable payload leaves the last good profile in place', () async {
      final transport = _FakeTransport();
      final repository = DiscordUserProfileRepository(transport);
      final controller = UserProfileController(() => repository);
      addTearDown(controller.dispose);
      await controller.load();

      // A USER_UPDATE with no id is not a reason to forget who we are.
      expect(repository.accept('USER_UPDATE', const {})?.username, 'rxflex');
      expect(controller.isSaving, isFalse);
    });

    test('a USER_UPDATE from another device is adopted', () async {
      final transport = _FakeTransport();
      final repository = DiscordUserProfileRepository(transport);
      final controller = UserProfileController(() => repository);
      addTearDown(controller.dispose);
      await controller.load();

      repository.accept('USER_UPDATE', const {
        'id': '123456789012345678',
        'username': 'rxflex',
        'global_name': 'Elsewhere',
      });

      expect(controller.profile?.displayName, 'Elsewhere');
      expect(
        repository.accept('MESSAGE_CREATE', const {})?.displayName,
        'Elsewhere',
      );
    });
  });
}

final class _FakeTransport implements DiscordUserProfileTransport {
  final List<Map<String, Object?>> patches = [];
  final List<String> requestedProfileIds = [];
  bool failWrites = false;
  bool failReads = false;
  bool refuseProfile = false;
  String _displayName = 'Rx';

  @override
  Future<Map<String, Object?>> readCurrentUser() async {
    if (failReads) throw StateError('offline');
    return _user();
  }

  @override
  Future<Map<String, Object?>?> readUserProfile(String userId) async {
    requestedProfileIds.add(userId);
    if (refuseProfile) return null;
    return {
      'user': {'id': userId, 'username': 'mira', 'global_name': 'Mira'},
      'user_profile': {'bio': 'ships the parser'},
    };
  }

  @override
  Future<Map<String, Object?>?> patchCurrentUser(
    Map<String, Object?> body,
  ) async {
    patches.add(body);
    if (failWrites) throw StateError('rejected');
    final name = body['global_name'];
    if (name is String) _displayName = name.trim();
    return _user();
  }

  Map<String, Object?> _user() => {
    'id': '123456789012345678',
    'username': 'rxflex',
    'global_name': _displayName,
    'discriminator': '0',
  };
}
