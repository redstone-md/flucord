import '../data/discord/discord_snowflake.dart';
import '../domain/chat_models.dart';
import '../domain/message_search.dart';

part 'message_search_tokens.dart';

/// What a line of search-bar text resolved to.
final class MessageSearchParse {
  MessageSearchParse({
    required this.filters,
    Iterable<String> unresolved = const [],
  }) : unresolved = List.unmodifiable(unresolved);

  final MessageSearchFilters filters;

  /// Tokens that named something this workspace cannot resolve — a user who is
  /// not known here, a channel the account cannot see, a `has:` value Discord
  /// does not offer.
  ///
  /// They are kept out of the query, because a filter Discord never receives
  /// would silently widen the search to everything the user meant to exclude.
  /// They are reported rather than dropped so the surface can say which word
  /// it could not use instead of quietly answering a different question.
  final List<String> unresolved;

  bool get isEmpty => filters.isEmpty;
}

/// Parses the filter syntax Discord's search bar accepts.
///
/// `from:`, `mentions:`, `has:`, `before:`, `after:`, `in:` and `pinned:` map
/// onto query parameters; every other word falls into the free-text bucket.
/// Names are resolved against the workspace the search will run in, so the
/// caller decides what "visible" means — pass only the channels the account may
/// actually read and an `in:` filter can never name one it may not.
final class MessageSearchGrammar {
  const MessageSearchGrammar({
    required this.channels,
    required this.members,
    required this.currentMemberId,
  });

  /// Discord's own literal for "me" in a `from:` or `mentions:` filter.
  static const selfToken = '@me';

  /// The shape of a raw id typed instead of a name.
  static final _snowflakePattern = RegExp(r'^\d{17,19}$');

  /// `pinned:` accepts only these two words; anything else is not a pin filter.
  static final _booleanPattern = RegExp(
    r'^\s*(true|false)',
    caseSensitive: false,
  );

  /// The channels an `in:` filter may name. Filtering this list is how the
  /// caller keeps the filter inside what the account is allowed to read.
  final List<ConversationChannel> channels;
  final List<Member> members;
  final String currentMemberId;

  MessageSearchParse parse(String text) {
    final words = <String>[];
    final authorIds = <String>[];
    final mentionIds = <String>[];
    final has = <MessageSearchHas>[];
    final channelIds = <String>[];
    final unresolved = <String>[];
    bool? pinned;
    String? minId;
    String? maxId;

    for (final token in _MessageSearchTokens.split(text)) {
      final filter = token.filter;
      if (filter == null) {
        if (token.value.isNotEmpty) words.add(token.value);
        continue;
      }
      // An answerless filter word is not free text: Discord strips the
      // incomplete token before searching rather than searching for "from:".
      if (token.value.isEmpty) continue;
      switch (filter) {
        case 'from':
          _resolveUsers(token, authorIds, unresolved);
        case 'mentions':
          _resolveUsers(token, mentionIds, unresolved);
        case 'has':
          final term = _parseHas(token.value);
          if (term == null) {
            unresolved.add(token.text);
          } else {
            has.add(term);
          }
        case 'in':
          _resolveChannels(token, channelIds, unresolved);
        case 'pinned':
          final match = _booleanPattern.firstMatch(token.value);
          if (match == null) {
            unresolved.add(token.text);
          } else {
            pinned = match.group(1)!.toLowerCase() == 'true';
          }
        case 'before' || 'after':
          final range = _MessageSearchDate.parse(token.value);
          if (range == null) {
            unresolved.add(token.text);
            continue;
          }
          // A date bound is assigned, never accumulated: a second `before:`
          // replaces the first, exactly as Discord's builder overwrites it.
          if (filter == 'before') {
            maxId = DiscordSnowflake.fromTimestampMillis(range.startMillis);
          } else {
            minId = DiscordSnowflake.fromTimestampMillis(range.endMillis);
          }
      }
    }

    return MessageSearchParse(
      filters: MessageSearchFilters(
        content: words.join(' '),
        authorIds: authorIds,
        mentionIds: mentionIds,
        has: has,
        channelIds: channelIds,
        pinned: pinned,
        minId: minId,
        maxId: maxId,
      ),
      unresolved: unresolved,
    );
  }

  static MessageSearchHas? _parseHas(String value) {
    final negated = value.startsWith('-');
    final kind = MessageSearchHasKind.parse(
      negated ? value.substring(1) : value,
    );
    return kind == null ? null : MessageSearchHas(kind, negated: negated);
  }

  void _resolveUsers(
    _MessageSearchToken token,
    List<String> into,
    List<String> unresolved,
  ) {
    final value = token.value;
    if (value.toLowerCase() == selfToken) {
      into.add(currentMemberId);
      return;
    }
    if (_snowflakePattern.hasMatch(value)) {
      into.add(value);
      return;
    }
    final name = (value.startsWith('@') ? value.substring(1) : value)
        .toLowerCase();
    // Every exact match is kept: two people can carry the same display name,
    // and picking one of them arbitrarily would answer about the wrong person
    // with no way for the reader to tell.
    final matches = [
      for (final member in members)
        if (member.displayName.toLowerCase() == name) member.id,
    ];
    if (matches.isEmpty) {
      unresolved.add(token.text);
      return;
    }
    into.addAll(matches);
  }

  void _resolveChannels(
    _MessageSearchToken token,
    List<String> into,
    List<String> unresolved,
  ) {
    final value = token.value.startsWith('#')
        ? token.value.substring(1)
        : token.value;
    if (_snowflakePattern.hasMatch(value)) {
      // A raw id still has to name a channel the account can see, or the
      // filter would ask the server about a channel this session may not read.
      if (channels.any((channel) => channel.id == value)) {
        into.add(value);
        return;
      }
      unresolved.add(token.text);
      return;
    }
    final name = value.toLowerCase();
    final matches = [
      for (final channel in channels)
        if (channel.name.toLowerCase() == name) channel.id,
    ];
    if (matches.isEmpty) {
      unresolved.add(token.text);
      return;
    }
    into.addAll(matches);
  }
}
