import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_member_list_ranges.dart';
import '../domain/guild_member_list.dart';
import '../domain/guild_member_list_repository.dart';

/// Owns one member panel's subscription to a channel's roster.
///
/// The roster is pull-shaped: nothing arrives until the client says which rows
/// it is looking at, and the answer is keyed by a list id the client has to
/// derive. This controller is where those two halves meet — it holds the
/// derived id so inbound updates can be matched, and it turns scroll positions
/// into range subscriptions.
///
/// It deliberately does *not* dedup ranges or cap how many channels stay
/// subscribed. Both belong to the transport, which already implements them, and
/// a second layer of either would only hide when the first one is wrong.
final class GuildMemberListController extends ChangeNotifier {
  GuildMemberListController(
    this._repositoryProvider, {
    this.scrollDebounce = const Duration(milliseconds: 50),
  });

  final GuildMemberListRepository? Function() _repositoryProvider;

  /// Trailing debounce applied to scroll-driven range changes.
  ///
  /// Discord's renderer uses 50 ms. Recomputing per scroll tick is cheap, but
  /// the socket write is not, and most ticks resolve to the same pages anyway.
  final Duration scrollDebounce;

  GuildMemberListRepository? _repository;
  StreamSubscription<GuildMemberList>? _updates;
  Timer? _debounce;
  String? _guildId;
  String? _channelId;
  String? _listId;
  GuildMemberList? _list;
  bool _bound = false;
  bool _disposed = false;

  /// The roster as far as the server has described it, or `null` when no
  /// channel is being watched or nothing has arrived yet.
  GuildMemberList? get list => _list;

  /// Whether the server has described the watched list at all.
  bool get isLoaded => _list?.isLoaded ?? false;

  /// The derived member list id the watched channel reads from.
  String? get listId => _listId;

  String? get channelId => _channelId;

  /// Watches [channelId] in [guildId], subscribing the head page immediately.
  ///
  /// Discord subscribes `[[0, 99]]` the moment the members section opens,
  /// before the panel has measured itself, because the head page carries the
  /// group headers every other row index is counted against.
  void viewChannel({required String? guildId, required String? channelId}) {
    if (_disposed) return;
    final rebound = _bind();
    if (!rebound && guildId == _guildId && channelId == _channelId) return;

    _cancelDebounce();
    _unsubscribeCurrent();
    _guildId = guildId;
    _channelId = channelId;
    final repository = _repository;
    if (guildId == null || channelId == null || repository == null) {
      _listId = null;
      _list = null;
      notifyListeners();
      return;
    }
    _listId = repository.memberListIdFor(
      guildId: guildId,
      channelId: channelId,
    );
    _list = repository.memberListFor(guildId: guildId, listId: _listId!);
    repository.subscribeMemberRanges(
      guildId: guildId,
      channelId: channelId,
      ranges: DiscordMemberListRanges.initial,
    );
    notifyListeners();
  }

  /// Reports the panel's scroll position so the needed pages get subscribed.
  ///
  /// [rowHeight] is the panel's fixed per-row extent: the range arithmetic maps
  /// pixels straight onto the flat row space, which only holds while headers
  /// and members are the same height.
  void updateViewport({
    required double scrollOffset,
    required double viewportHeight,
    required double rowHeight,
  }) {
    // The channel is captured now rather than when the timer fires: these
    // ranges describe this channel's panel and mean nothing for another one.
    final guildId = _guildId;
    final channelId = _channelId;
    final repository = _repository;
    if (_disposed ||
        guildId == null ||
        channelId == null ||
        repository == null) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(scrollDebounce, () {
      _debounce = null;
      repository.subscribeMemberRanges(
        guildId: guildId,
        channelId: channelId,
        ranges: DiscordMemberListRanges.forViewport(
          scrollOffset: scrollOffset,
          viewportHeight: viewportHeight,
          rowHeight: rowHeight,
        ),
      );
    });
  }

  /// Stops watching, releasing the channel's subscription.
  void clear() => viewChannel(guildId: null, channelId: null);

  /// Attaches to the active transport. Returns `true` when it changed.
  bool _bind() {
    final repository = _repositoryProvider();
    if (_bound && identical(repository, _repository)) return false;
    _bound = true;
    unawaited(_updates?.cancel());
    _updates = null;
    _repository = repository;
    _list = null;
    _listId = null;
    _updates = repository?.memberListUpdates.listen(_acceptUpdate);
    return true;
  }

  void _acceptUpdate(GuildMemberList update) {
    if (_disposed || update.guildId != _guildId || update.listId != _listId) {
      return;
    }
    _list = update;
    notifyListeners();
  }

  void _unsubscribeCurrent() {
    final guildId = _guildId;
    final channelId = _channelId;
    if (guildId == null || channelId == null) return;
    _repository?.unsubscribeMemberRanges(
      guildId: guildId,
      channelId: channelId,
    );
  }

  void _cancelDebounce() {
    _debounce?.cancel();
    _debounce = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelDebounce();
    unawaited(_updates?.cancel());
    _updates = null;
    _list = null;
    super.dispose();
  }
}
