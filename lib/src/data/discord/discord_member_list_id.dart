import '../../domain/discord_permissions.dart';
import '../../domain/permission_overwrite.dart';
import 'discord_murmur3.dart';

// The overwrite record the derivation reads is the same one permission
// computation reads, so it is defined once, in the domain, and handed on from
// here rather than kept as a second copy that could drift from it.
export '../../domain/permission_overwrite.dart' show DiscordPermissionOverwrite;

/// Derives the member-list identifier Discord uses to key a channel's roster.
///
/// The Gateway answers a channel range subscription with a
/// `GUILD_MEMBER_LIST_UPDATE` whose `id` identifies a *visibility class*, not a
/// channel: every channel with the same `VIEW_CHANNEL` overwrites shares one
/// list. A client that cannot reproduce the identifier cannot tell which
/// subscription an update belongs to, so the derivation is part of the wire
/// contract rather than an optimisation.
abstract final class DiscordMemberListId {
  /// Identifier shared by every channel `@everyone` can read.
  static const everyone = 'everyone';

  /// `VIEW_CHANNEL`, the only permission bit the derivation looks at.
  static final viewChannel = DiscordPermissions.viewChannel;

  /// Resolves the identifier for [channel].
  ///
  /// [everyoneRolePermissions] is the guild's `@everyone` role permission
  /// bitfield. For a thread, pass its parent channel and set
  /// [isPrivateThread] when the thread is private: Discord's own check
  /// resolves threads to their parent and never treats a private thread as
  /// readable by `@everyone`.
  static String resolve({
    required Map<String, Object?>? channel,
    required BigInt everyoneRolePermissions,
    bool isPrivateThread = false,
  }) {
    if (channel == null) return everyone;

    final serverProvided = channel['member_list_id'];
    if (serverProvided is String && serverProvided.isNotEmpty) {
      return serverProvided;
    }

    final overwrites = overwritesOf(channel);
    if (!isPrivateThread &&
        _visibleToEveryone(overwrites, everyoneRolePermissions)) {
      return everyone;
    }
    return hashOverwrites(overwrites);
  }

  /// Reads the `permission_overwrites` array, skipping malformed entries.
  static List<DiscordPermissionOverwrite> overwritesOf(
    Map<String, Object?> channel,
  ) {
    final raw = channel['permission_overwrites'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (entry) => DiscordPermissionOverwrite.fromJson(
            entry.cast<String, Object?>(),
          ),
        )
        .nonNulls
        .toList(growable: false);
  }

  /// Hashes the sorted `allow:`/`deny:` token list for the overwrites.
  ///
  /// An overwrite that both grants and denies `VIEW_CHANNEL` contributes only
  /// the `allow:` token, because the renderer tests `allow` first and never
  /// falls through.
  static String hashOverwrites(List<DiscordPermissionOverwrite> overwrites) {
    final tokens = <String>[];
    for (final overwrite in overwrites) {
      if (overwrite.grants(viewChannel)) {
        tokens.add('allow:${overwrite.id}');
      } else if (overwrite.denies(viewChannel)) {
        tokens.add('deny:${overwrite.id}');
      }
    }
    tokens.sort();
    return '${DiscordMurmur3.hashText(tokens.join(','))}';
  }

  static bool _visibleToEveryone(
    List<DiscordPermissionOverwrite> overwrites,
    BigInt everyoneRolePermissions,
  ) {
    if ((everyoneRolePermissions & viewChannel) != viewChannel) return false;
    return !overwrites.any((overwrite) => overwrite.denies(viewChannel));
  }
}
