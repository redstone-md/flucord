import 'dart:async';

import '../../domain/chat_models.dart';
import '../../domain/guild_member_list.dart';
import 'discord_mapper.dart';
import 'discord_member_list_directory.dart';
import 'discord_member_list_store.dart';
import 'discord_member_list_update.dart';

/// Turns the Gateway's member-list traffic into domain state.
///
/// Three dispatches have to be read together for a roster to make sense: READY
/// and `GUILD_CREATE` describe the channels a list id can be derived from, and
/// `GUILD_MEMBER_LIST_UPDATE` carries the rows. Keeping them in one handler is
/// what lets a roster row be matched to the channel that asked for it, and
/// keeps the repository above from having to know the derivation at all.
final class DiscordMemberListHandler {
  DiscordMemberListHandler(this._mapper);

  final DiscordMapper _mapper;
  final DiscordMemberListDirectory _directory = DiscordMemberListDirectory();
  final DiscordMemberListStore _store = DiscordMemberListStore();
  final StreamController<GuildMemberList> _updates =
      StreamController.broadcast();

  Stream<GuildMemberList> get updates => _updates.stream;

  GuildMemberList? listFor({required String guildId, required String listId}) =>
      _store.listFor(guildId, listId);

  String memberListIdFor({
    required String guildId,
    required String channelId,
  }) => _directory.memberListIdFor(guildId: guildId, channelId: channelId);

  /// Applies one dispatch and returns the members it carried.
  ///
  /// A member-list item is the first and often only place this transport
  /// reports a guild member, so the caller is expected to fold the result into
  /// the member cache before rendering rows that reference it by id.
  List<Member> accept(String name, Map<String, Object?> data) {
    // A closed handler belongs to a repository that is shutting down; applying
    // more rows would only leave state nobody can read back.
    if (_updates.isClosed) return const [];
    switch (name) {
      case 'READY':
        _directory.acceptReady(data);
        // A new session invalidates every cached row: the server tracks
        // subscriptions per connection and will resend from scratch.
        _store.clear();
      case 'GUILD_CREATE':
        _directory.acceptGuild(data);
      case 'GUILD_DELETE':
        final guildId = data['id'];
        if (guildId is String) {
          _directory.removeGuild(guildId);
          _store.clearGuild(guildId);
        }
      case 'GUILD_MEMBER_LIST_UPDATE':
        return _acceptListUpdate(data);
    }
    return const [];
  }

  List<Member> _acceptListUpdate(Map<String, Object?> data) {
    final update = DiscordMemberListUpdate.fromDispatch(data);
    if (update == null) return const [];
    final roles = _directory.rolesOf(update.guildId);
    final members = [
      for (final item in update.memberItems)
        _memberOf(item, update.guildId, roles),
    ];
    _updates.add(_store.apply(update));
    return members;
  }

  /// Merges the item's member payload with the presence riding alongside it.
  ///
  /// `guildMember` cannot know a presence — it maps a member payload that has
  /// none — but on this transport the enclosing item is where presence first
  /// appears, so it has to be applied here or the roster renders everyone as
  /// offline.
  Member _memberOf(
    DiscordMemberListItem item,
    String guildId,
    List<Map<String, Object?>> roles,
  ) {
    final member = _mapper.guildMember(item.member!, guildId, roles);
    final status = item.presence?['status'];
    return status is String
        ? member.copyWith(presence: _mapper.presence(status))
        : member;
  }

  Future<void> close() async {
    _store.clear();
    _directory.clear();
    await _updates.close();
  }
}
