import 'guild_member_list.dart';

/// Server-authoritative access to a guild's lazily loaded member lists.
///
/// The roster is not something the client can enumerate: Discord only sends the
/// row ranges a client has asked for, keyed by a *visibility class* rather than
/// by channel. So the panel above this contract can never own the data — it can
/// only declare which rows it is looking at and read back whatever the server
/// has vouched for since. Keeping that asymmetry in the contract stops the UI
/// from assuming a complete list exists somewhere.
abstract interface class GuildMemberListRepository {
  /// Asks the guild for members whose name starts with [query].
  ///
  /// Answers arrive as ordinary member updates rather than as a return value:
  /// Discord replies on the gateway, and the same reply also reaches anybody
  /// else watching the roster. A blank query asks nothing.
  void searchGuildMembers({
    required String guildId,
    required String query,
    int limit = 25,
  });

  /// Lists that changed, one event per applied `GUILD_MEMBER_LIST_UPDATE`.
  Stream<GuildMemberList> get memberListUpdates;

  /// The list identifier a channel's roster arrives on.
  ///
  /// Several channels share one identifier when they share their
  /// `VIEW_CHANNEL` overwrites, which is why subscribing is per channel but
  /// reading back is per list.
  String memberListIdFor({required String guildId, required String channelId});

  /// The list as it is currently known, or `null` when nothing has arrived.
  GuildMemberList? memberListFor({
    required String guildId,
    required String listId,
  });

  /// Declares the row ranges a channel's panel is looking at.
  ///
  /// Ranges replace, never merge: this call is the complete set for the
  /// channel. Passing an unchanged set is cheap and expected — the transport
  /// suppresses the resend.
  void subscribeMemberRanges({
    required String guildId,
    required String channelId,
    required List<List<int>> ranges,
  });

  /// Stops watching a channel's roster.
  void unsubscribeMemberRanges({
    required String guildId,
    required String channelId,
  });
}
