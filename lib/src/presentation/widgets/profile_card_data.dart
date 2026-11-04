import 'package:flutter/widgets.dart';

import '../../data/discord/discord_cdn.dart';
import '../../domain/chat_models.dart';
import '../../domain/discord_relationship.dart';
import '../../domain/user_profile.dart';
import 'discord_relationship_avatar.dart';

/// Everything the profile card shows about one person.
///
/// The host builds it from what it knows, and every part the host cannot
/// fill stays empty: the card hides a part with nothing in it rather than
/// guessing. A member, a Social SDK friend and (later) the account's own
/// profile each have their own factory.
@immutable
final class ProfileCardData {
  const ProfileCardData({
    required this.userId,
    required this.displayName,
    required this.monogram,
    this.username,
    this.avatarUrl,
    this.avatarColorValue,
    this.decorationUrl,
    this.presence,
    this.bannerUrl,
    this.accentColorValue,
    this.pronouns = '',
    this.clanTag,
    this.badges = const [],
    this.mutualFriends = const [],
    this.mutualServerCount = 0,
    this.bio = '',
    this.activity,
    this.roles,
  });

  /// [member] as the workspace knows them, with the fetched [profile] laid
  /// over it once it arrives. [roles] are the roles they hold in the server
  /// the card was opened in, or null outside a server.
  factory ProfileCardData.member(
    Member member, {
    String? spaceId,
    OtherUserProfile? profile,
    List<CommunityRole>? roles,
  }) {
    final presence = member.presenceOrCoarse;
    return ProfileCardData(
      userId: member.id,
      displayName: member.displayName,
      monogram: member.initials,
      username: member.username ?? _nonEmpty(profile?.username),
      avatarUrl: member.avatarUrlFor(spaceId),
      avatarColorValue: member.colorValue,
      decorationUrl: _decorationUrl(profile?.decoration),
      presence: presence,
      bannerUrl: DiscordCdn.userBanner(member.id, profile?.bannerHash),
      accentColorValue: switch (profile?.accentColor) {
        final rgb? => 0xff000000 | rgb,
        null => member.colorValue,
      },
      pronouns: profile?.pronouns ?? '',
      clanTag: member.clanTag,
      badges: profile?.badges ?? const [],
      mutualFriends: profile?.mutualFriends ?? const [],
      mutualServerCount: profile?.mutualServers.length ?? 0,
      bio: profile?.bio ?? '',
      activity: _shownActivity(presence),
      roles: roles,
    );
  }

  /// A Social SDK relationship. The SDK has no profile route, so the card
  /// shows the name, the status and the game.
  factory ProfileCardData.relationship(DiscordRelationship relationship) {
    final user = relationship.user;
    final activity = user.activity;
    return ProfileCardData(
      userId: user.id,
      displayName: user.displayName,
      monogram: user.displayName.characters.first.toUpperCase(),
      username: user.username,
      avatarUrl: user.avatarUrl,
      presence: UserPresence(
        status: DiscordRelationshipAvatar.presenceOf(user.status),
      ),
      activity: activity == null
          ? null
          : UserActivity(
              name: activity.name,
              details: activity.details,
              state: activity.state,
            ),
    );
  }

  final String userId;
  final String displayName;

  /// What stands in for the avatar while it loads or where there is none.
  final String monogram;
  final String? username;
  final String? avatarUrl;

  /// The fill behind [monogram]. Null takes the card's own control colour.
  final int? avatarColorValue;
  final String? decorationUrl;

  /// The status dot and the custom status. Null draws no dot.
  final UserPresence? presence;
  final String? bannerUrl;

  /// The banner's colour where there is no banner image.
  final int? accentColorValue;
  final String pronouns;
  final ClanTag? clanTag;
  final List<ProfileBadge> badges;
  final List<MutualFriend> mutualFriends;
  final int mutualServerCount;
  final String bio;

  /// What they are doing now, drawn in its own card.
  final UserActivity? activity;

  /// The roles they hold in this server, highest first. Null outside a
  /// server, which hides the section.
  final List<CommunityRole>? roles;

  /// The custom status text, or null for none.
  String? get customStatus => switch (presence?.customStatus?.summary) {
    final String text when text.isNotEmpty => text,
    _ => null,
  };

  /// The first activity that is not a custom status: Discord's card shows a
  /// plain "Playing" too, not only rich presence.
  static UserActivity? _shownActivity(UserPresence presence) {
    for (final activity in presence.activities) {
      if (activity.type == ActivityType.customStatus ||
          activity.type == ActivityType.hangStatus) {
        continue;
      }
      return activity;
    }
    return null;
  }

  static String? _decorationUrl(ProfileDecoration? decoration) {
    final asset = decoration?.asset;
    if (asset == null || asset.isEmpty) return null;
    return 'https://cdn.discordapp.com/avatar-decoration-decoration/$asset.png'
        '?size=96&passthrough=true';
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;
}
