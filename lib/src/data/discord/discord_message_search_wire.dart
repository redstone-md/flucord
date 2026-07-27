import '../../domain/message_search.dart';

/// Turns a search into the route and query string Discord's classic search
/// endpoints expect.
///
/// Everything about the request lives here so there is exactly one place where
/// a parameter name can be wrong. The serialisation reproduces Node's
/// `querystring` semantics, which is what the desktop client encodes with:
/// a list becomes a repeated key, a boolean becomes the literal `true`/`false`,
/// and an empty list emits nothing at all rather than an empty value.
abstract final class DiscordMessageSearchWire {
  /// The route for [scope].
  ///
  /// A guild search always uses the guild-wide route. The desktop client's
  /// channel-inside-a-guild context resolves to this same route, and R05
  /// records how the channel restriction reaches the wire from there as
  /// unestablished — so Flucord narrows a guild search with the `channel_id`
  /// filter, which is established, instead of guessing at a second route.
  static String pathFor(MessageSearchScope scope) => switch (scope) {
    GuildMessageSearchScope(:final guildId) =>
      '/guilds/$guildId/messages/search',
    ChannelMessageSearchScope(:final channelId) =>
      '/channels/$channelId/messages/search',
  };

  /// The query string for [query].
  ///
  /// [attempts] is the 202 retry counter. Discord mutates it onto the query
  /// object, so it is absent on the first request and rides as a parameter on
  /// each retry; it is reproduced for parity and is harmless if ignored.
  ///
  /// `include_nsfw` is deliberately never sent. The desktop client only adds it
  /// once the account has agreed to age-restricted content *for that guild*,
  /// and Flucord holds no such agreement — sending it unconditionally would
  /// claim a consent the user never gave.
  static Map<String, Object?> parametersFor(
    MessageSearchQuery query, {
    int attempts = 0,
  }) {
    final filters = query.filters;
    return {
      if (filters.content.isNotEmpty) 'content': filters.content,
      if (filters.authorIds.isNotEmpty) 'author_id': filters.authorIds,
      if (filters.mentionIds.isNotEmpty) 'mentions': filters.mentionIds,
      if (filters.has.isNotEmpty)
        'has': [for (final term in filters.has) term.wireValue],
      if (filters.channelIds.isNotEmpty) 'channel_id': filters.channelIds,
      if (filters.pinned case final pinned?) 'pinned': '$pinned',
      'min_id': ?filters.minId,
      'max_id': ?filters.maxId,
      'sort_by': query.sort.sortBy,
      'sort_order': query.sort.sortOrder,
      'offset': '${query.offset}',
      if (attempts > 0) 'attempts': '$attempts',
    };
  }
}
