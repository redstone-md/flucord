import 'package:flutter/widgets.dart';

import '../../application/active_friends.dart';
import '../../data/discord/discord_cdn.dart';
import '../../domain/chat_models.dart';
import '../../domain/discord_relationship.dart';
import '../../domain/discord_rgb.dart';
import '../../domain/discord_snowflake.dart';
import '../../domain/monogram.dart';
import '../../domain/profile_effect.dart';
import '../../domain/user_profile.dart';

/// A friend both people share, with their status where the workspace knows
/// it.
typedef ProfileMutualFriend = ({MutualFriend friend, UserPresence? presence});

/// A server both people are in, with what the person is called there.
typedef ProfileMutualServer = ({CommunitySpace space, String? nickname});

/// When the person joined the server the profile was opened in.
typedef ProfileServerSince = ({String serverName, DateTime since});

/// Everything the profile card and the full profile show about one person.
///
/// The host builds it from what it knows, and every part the host cannot
/// fill stays empty: the card hides a part with nothing in it rather than
/// guessing. A member, a Social SDK friend and the account's own profile
/// each have their own factory.
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
    this.themeColors,
    this.pronouns = '',
    this.clanTag,
    this.nameStyle,
    this.badges = const [],
    this.mutualFriends = const [],
    this.mutualServers = const [],
    this.bio = '',
    this.activity,
    this.voiceRoom,
    this.roles,
    this.memberSince,
    this.serverSince,
    this.friendsSince,
    this.connections = const [],
    this.effect,
  });

  /// [member] as the workspace knows them, with the fetched [profile] laid
  /// over it once it arrives. [roles] are the roles they hold in the server
  /// the card was opened in, or null outside a server.
  ///
  /// [workspace] names the mutual servers and gives the mutual friends their
  /// status; a server it does not hold is left out. [friendsSince] and
  /// [voiceRoom] come from the friend list and the voice seats.
  factory ProfileCardData.member(
    Member member, {
    String? spaceId,
    OtherUserProfile? profile,
    List<CommunityRole>? roles,
    ChatWorkspace? workspace,
    DateTime? friendsSince,
    ActiveFriendRoom? voiceRoom,
  }) {
    final presence = member.presenceOrCoarse;
    // A friend outside the workspace has no tags but the profile's.
    final tags = profile?.tags?.over(member.tags) ?? member.tags;
    final space = spaceId == null ? null : workspace?.spaceOrNull(spaceId);
    final joined = spaceId == null
        ? null
        : member.membershipIn(spaceId)?.joinedAt;
    return ProfileCardData(
      userId: member.id,
      displayName: member.displayNameFor(spaceId),
      monogram: member.initials,
      username: member.username ?? _nonEmpty(profile?.username),
      avatarUrl: member.avatarUrlFor(spaceId),
      avatarColorValue: member.colorValue,
      decorationUrl: _decorationUrl(tags.decoration),
      presence: presence,
      bannerUrl: switch (profile?.serverProfile) {
        ServerProfile(:final guildId, bannerHash: final hash?) =>
          DiscordCdn.guildMemberBanner(guildId, member.id, hash),
        _ => DiscordCdn.userBanner(member.id, profile?.bannerHash),
      },
      accentColorValue: switch (profile?.accentColor) {
        final rgb? => DiscordRgb(rgb).opaque,
        null => member.colorValue,
      },
      themeColors: profile?.effectiveThemeColors,
      pronouns: profile?.effectivePronouns ?? '',
      clanTag: tags.clanTag,
      nameStyle: tags.nameStyle,
      badges: profile?.badges ?? const [],
      mutualFriends: [
        for (final friend in profile?.mutualFriends ?? const <MutualFriend>[])
          (
            friend: friend,
            presence: workspace?.memberOrNull(friend.id)?.presenceOrCoarse,
          ),
      ],
      mutualServers: [
        for (final server in profile?.mutualServers ?? const <MutualServer>[])
          if (workspace?.spaceOrNull(server.id) case final space?)
            (space: space, nickname: server.nickname),
      ],
      bio: profile?.effectiveBio ?? '',
      // Discord's card shows a plain "Playing" too, not only rich presence.
      activity: presence.doing.firstOrNull,
      voiceRoom: voiceRoom,
      roles: roles,
      memberSince: DiscordSnowflake.createdAt(member.id),
      serverSince: space == null || joined == null
          ? null
          : (serverName: space.name, since: joined),
      friendsSince: friendsSince,
      connections: profile?.connections ?? const [],
      effect: _wornEffect(profile),
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
      monogram: monogramOf(user.displayName),
      username: user.username,
      avatarUrl: user.avatarUrl,
      presence: UserPresence(status: user.status.presence),
      activity: activity == null
          ? null
          : UserActivity(
              name: activity.name,
              details: activity.details,
              state: activity.state,
            ),
      memberSince: DiscordSnowflake.createdAt(user.id),
      friendsSince: relationship.kind == DiscordRelationshipKind.friend
          ? relationship.since
          : null,
    );
  }

  /// The account's own profile while it is being edited: [profile] says who
  /// it is, the rest are the form's current values, saved or not. The
  /// images are the staged ones where the user picked new ones. [published]
  /// gives the collectibles.
  factory ProfileCardData.ownProfile(
    UserProfile profile, {
    required String displayName,
    required String pronouns,
    required String bio,
    required int? accentColor,
    required ProfileThemeColors? themeColors,
    required String? avatarUrl,
    required String? bannerUrl,
    UserPresence? presence,
    OtherUserProfile? published,
  }) {
    final name = displayName.isEmpty ? profile.username : displayName;
    return ProfileCardData(
      userId: profile.userId,
      displayName: name,
      monogram: monogramOf(name),
      username: profile.hasLegacyDiscriminator
          ? '${profile.username}#${profile.discriminator}'
          : _nonEmpty(profile.username),
      avatarUrl: avatarUrl,
      decorationUrl: _decorationUrl(published?.tags?.decoration),
      presence: presence,
      bannerUrl: bannerUrl,
      accentColorValue: accentColor == null
          ? null
          : DiscordRgb(accentColor).opaque,
      themeColors: themeColors,
      pronouns: pronouns,
      bio: bio,
      memberSince: DiscordSnowflake.createdAt(profile.userId),
      effect: _wornEffect(published),
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

  /// The person's Nitro theme, which paints the card. Null keeps the app's
  /// own colours.
  final ProfileThemeColors? themeColors;
  final String pronouns;
  final ClanTag? clanTag;

  /// How the person styled their name. A profile is the person, not their
  /// standing in a server, so no role colour takes its place here.
  final NameStyle? nameStyle;
  final List<ProfileBadge> badges;
  final List<ProfileMutualFriend> mutualFriends;
  final List<ProfileMutualServer> mutualServers;
  final String bio;

  /// What they are doing now, drawn in its own card.
  final UserActivity? activity;

  /// The voice channel they sit in. Null when they sit in none.
  final ActiveFriendRoom? voiceRoom;

  /// The roles they hold in this server, highest first. Null outside a
  /// server, which hides the section.
  final List<CommunityRole>? roles;

  /// When the account was made. Null hides the line.
  final DateTime? memberSince;

  /// When they joined the server the profile was opened in. Null outside a
  /// server or where Discord did not say.
  final ProfileServerSince? serverSince;

  /// When the two became friends. Null for someone who is not a friend.
  final DateTime? friendsSince;

  /// Their linked accounts on other services.
  final List<ProfileConnection> connections;

  /// The profile effect drawn over the card. Null for none.
  final ProfileEffectConfig? effect;

  /// The custom status text, or null for none.
  String? get customStatus => switch (presence?.customStatus?.summary) {
    final String text when text.isNotEmpty => text,
    _ => null,
  };

  static String? _decorationUrl(AvatarDecoration? decoration) =>
      switch (decoration) {
        final decoration? => DiscordCdn.avatarDecoration(decoration.asset),
        null => null,
      };

  /// How [profile]'s effect looks, unless it has expired.
  static ProfileEffectConfig? _wornEffect(OtherUserProfile? profile) =>
      switch (profile?.effectiveProfileEffect) {
        final worn? when worn.isWornAt(DateTime.now()) =>
          profile?.profileEffectConfig,
        _ => null,
      };

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;
}
