/// Server-side message search, in the shape Discord's own search bar speaks.
///
/// Discord's classic search carries every filter in the query string and
/// answers with *hit groups* rather than a flat message list, so the models
/// here keep both halves of that shape: a typed query that is serialised in
/// exactly one place, and a result that never throws away the messages
/// surrounding a hit.
library;

import 'chat_models.dart';

part 'message_search_results.dart';

/// How the server should order the result set.
///
/// The wire carries `sort_by` and `sort_order` as two independent fields, but
/// only these three combinations are reachable from the client, so the pair
/// travels as one value. Keeping them apart would invent modes — `relevance`
/// ascending — that no surface can restore from an echoed query.
enum MessageSearchSort {
  newest(sortBy: 'timestamp', sortOrder: 'desc'),
  oldest(sortBy: 'timestamp', sortOrder: 'asc'),
  mostRelevant(sortBy: 'relevance', sortOrder: 'desc');

  const MessageSearchSort({required this.sortBy, required this.sortOrder});

  final String sortBy;
  final String sortOrder;

  /// Reads the sort control back out of a query the server echoed.
  ///
  /// Relevance wins outright, then the order, and anything missing falls back
  /// to [newest] — the same precedence Discord restores its own control with,
  /// which is what stops an unknown pair from silently reordering results.
  static MessageSearchSort fromWire({String? sortBy, String? sortOrder}) {
    if (sortBy == 'relevance') return mostRelevant;
    if (sortOrder == 'asc') return oldest;
    return newest;
  }
}

/// The value domain of the `has:` filter.
enum MessageSearchHasKind {
  link,
  embed,
  poll,
  snapshot,
  file,
  video,
  image,
  sound,
  sticker;

  /// The token as it rides in the query string. Identical to the Dart name
  /// today, named separately so a future rename cannot change the wire.
  String get wireValue => name;

  static MessageSearchHasKind? parse(String value) {
    final normalized = value.trim().toLowerCase();
    for (final kind in values) {
      if (kind.wireValue == normalized) return kind;
    }
    return null;
  }
}

/// One `has:` term.
///
/// A leading `-` in the search bar negates the term, and the negation rides in
/// the value itself (`has=-image`) rather than as a separate parameter, so it
/// belongs to the term and not to the filter list.
final class MessageSearchHas {
  const MessageSearchHas(this.kind, {this.negated = false});

  final MessageSearchHasKind kind;
  final bool negated;

  String get wireValue => negated ? '-${kind.wireValue}' : kind.wireValue;

  @override
  bool operator ==(Object other) =>
      other is MessageSearchHas &&
      other.kind == kind &&
      other.negated == negated;

  @override
  int get hashCode => Object.hash(kind, negated);

  @override
  String toString() => 'MessageSearchHas($wireValue)';
}

/// Everything the search bar's tokens resolved to, before paging and sorting.
///
/// Every list is de-duplicated in first-seen order because Discord accumulates
/// each filter into a `Set` keyed by its query parameter: typing `has:image
/// has:image` has to produce one `has=image`, not two.
final class MessageSearchFilters {
  MessageSearchFilters({
    String content = '',
    Iterable<String> authorIds = const [],
    Iterable<String> mentionIds = const [],
    Iterable<MessageSearchHas> has = const [],
    Iterable<String> channelIds = const [],
    this.pinned,
    this.minId,
    this.maxId,
  }) : content = content.trim(),
       authorIds = _distinct(authorIds),
       mentionIds = _distinct(mentionIds),
       has = _distinct(has),
       channelIds = _distinct(channelIds);

  /// All non-filter words, joined by single spaces and trimmed.
  final String content;
  final List<String> authorIds;
  final List<String> mentionIds;
  final List<MessageSearchHas> has;
  final List<String> channelIds;

  /// Null when the user never typed `pinned:`; Discord omits the key entirely
  /// rather than sending `pinned=false` for "do not care".
  final bool? pinned;

  /// Lower and upper snowflake bounds, derived from `after:` and `before:`.
  final String? minId;
  final String? maxId;

  /// Whether the query would carry no parameters at all.
  ///
  /// Discord refuses to search on an empty query object rather than asking the
  /// server for every message in the guild, and so does Flucord.
  bool get isEmpty =>
      content.isEmpty &&
      authorIds.isEmpty &&
      mentionIds.isEmpty &&
      has.isEmpty &&
      channelIds.isEmpty &&
      pinned == null &&
      minId == null &&
      maxId == null;

  static List<T> _distinct<T>(Iterable<T> values) =>
      List.unmodifiable(<T>{...values});
}

/// A filter set together with the page and order it should be answered in.
final class MessageSearchQuery {
  const MessageSearchQuery({
    required this.filters,
    this.sort = MessageSearchSort.newest,
    this.offset = 0,
  });

  /// Discord pages search in fixed blocks of 25. The classic endpoint is never
  /// sent a `limit` — the client relies on the server default and does all of
  /// its page arithmetic with this constant, so Flucord does the same rather
  /// than inventing a limit the desktop client never sends.
  static const pageSize = 25;

  /// The last offset the client will ask for, and the page index it implies.
  /// Both are client-side caps; the server's own limit is not established.
  static const maxOffset = 9975;
  static const maxPageIndex = maxOffset ~/ pageSize;

  /// The largest result count pagination can actually walk through.
  static const reachableResults = maxOffset + pageSize;

  final MessageSearchFilters filters;
  final MessageSearchSort sort;
  final int offset;

  int get pageIndex => offset ~/ pageSize;

  /// Moves to [index], clamped to the reachable range so a pager that lost
  /// track cannot ask for an offset the client would never send.
  MessageSearchQuery atPage(int index) => MessageSearchQuery(
    filters: filters,
    sort: sort,
    offset: index.clamp(0, maxPageIndex) * pageSize,
  );

  /// Changing the order restarts the result set: an offset into the old
  /// ordering points at unrelated messages once the ordering changes.
  MessageSearchQuery sortedBy(MessageSearchSort value) =>
      MessageSearchQuery(filters: filters, sort: value);
}

/// Which corpus a search runs against.
///
/// Only the two routes whose behaviour R05 establishes are modelled. A guild
/// search always uses the guild-wide route — narrowing it to one channel is
/// what the `in:` filter is for, because how the client's `GUILD_CHANNEL`
/// context reaches the wire is recorded as unestablished. Thread-scoped and
/// cross-DM search need the tabs endpoint and are deliberately absent.
sealed class MessageSearchScope {
  const MessageSearchScope();

  /// The identity one in-flight search is tracked by. A new search for the
  /// same key replaces the previous one, exactly as the desktop client cancels
  /// the fetcher registered under that id.
  String get key;
}

final class GuildMessageSearchScope extends MessageSearchScope {
  const GuildMessageSearchScope(this.guildId);

  final String guildId;

  @override
  String get key => 'guild:$guildId';

  @override
  bool operator ==(Object other) =>
      other is GuildMessageSearchScope && other.guildId == guildId;

  @override
  int get hashCode => Object.hash('guild', guildId);
}

/// One channel — a guild channel picked deliberately, or a private
/// conversation, which has no guild to search.
final class ChannelMessageSearchScope extends MessageSearchScope {
  const ChannelMessageSearchScope(this.channelId);

  final String channelId;

  @override
  String get key => 'channel:$channelId';

  @override
  bool operator ==(Object other) =>
      other is ChannelMessageSearchScope && other.channelId == channelId;

  @override
  int get hashCode => Object.hash('channel', channelId);
}

final class MessageSearchRequest {
  const MessageSearchRequest({required this.scope, required this.query});

  final MessageSearchScope scope;
  final MessageSearchQuery query;
}
