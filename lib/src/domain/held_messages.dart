part of 'chat_models.dart';

/// The messages a workspace holds, stored per channel.
///
/// A change builds a new list for the one channel it touches and shares every
/// other list with the previous version. So a message costs the length of its
/// channel, and not the number of messages the client holds. It also lets a
/// reader tell an unchanged channel by the identity of its list.
final class _HeldMessages {
  _HeldMessages._(this._byChannel, [this._flat]);

  factory _HeldMessages.of(List<ChatMessage> messages) {
    final flat = ChatWorkspace._sealed(messages);
    return _HeldMessages._(
      ChatWorkspace._groupBy(flat, (message) => message.channelId),
      flat,
    );
  }

  final Map<String, List<ChatMessage>> _byChannel;
  List<ChatMessage>? _flat;

  List<ChatMessage> of(String channelId) =>
      ChatWorkspace._group(_byChannel, channelId);

  /// Every message, oldest first. It is built on first read, because the chat
  /// path reads one channel at a time and never needs it.
  List<ChatMessage> get flat => _flat ??= UnmodifiableListView(
    _oldestFirst(_byChannel.values.expand((messages) => messages)),
  );

  /// Puts [message] in its channel's timeline and replaces any earlier copy. It
  /// goes ahead of the first message that was sent later, or last if none was.
  _HeldMessages upsert(ChatMessage message) {
    final next = <ChatMessage>[];
    var insertAt = -1;
    for (final existing in of(message.channelId)) {
      if (existing.id == message.id) continue;
      if (insertAt < 0 && existing.sentAt.isAfter(message.sentAt)) {
        insertAt = next.length;
      }
      next.add(existing);
    }
    next.insert(insertAt < 0 ? next.length : insertAt, message);
    return _withChannel(message.channelId, next);
  }

  /// Folds a page of history into [channelId]. With [replace], the page takes
  /// the place of everything the channel held.
  _HeldMessages merge(
    String channelId,
    List<ChatMessage> page, {
    required bool replace,
  }) => _withChannel(
    channelId,
    _oldestFirst(
      <String, ChatMessage>{
        if (!replace)
          for (final message in of(channelId)) message.id: message,
        for (final message in page) message.id: message,
      }.values,
    ),
  );

  /// Replaces the message [messageId] with [update]'s answer, in the same place.
  /// Answers this same object when no channel holds that message.
  _HeldMessages update(
    String messageId,
    ChatMessage Function(ChatMessage message) update,
  ) {
    for (final MapEntry(key: channelId, value: messages)
        in _byChannel.entries) {
      final index = messages.indexWhere((message) => message.id == messageId);
      if (index < 0) continue;
      return _withChannel(
        channelId,
        [...messages]..[index] = update(messages[index]),
      );
    }
    return this;
  }

  _HeldMessages without(Set<String> messageIds) {
    final next = {..._byChannel};
    for (final MapEntry(key: channelId, value: messages)
        in _byChannel.entries) {
      if (!messages.any((message) => messageIds.contains(message.id))) continue;
      final kept = List<ChatMessage>.unmodifiable(
        messages.where((message) => !messageIds.contains(message.id)),
      );
      if (kept.isEmpty) {
        next.remove(channelId);
      } else {
        next[channelId] = kept;
      }
    }
    return _HeldMessages._(next);
  }

  _HeldMessages withoutChannels(Set<String> channelIds) => _HeldMessages._({
    for (final entry in _byChannel.entries)
      if (!channelIds.contains(entry.key)) entry.key: entry.value,
  });

  /// [channelIds] as [other] holds them, and every other channel as it is here.
  _HeldMessages withChannelsOf(_HeldMessages other, Set<String> channelIds) =>
      _HeldMessages._({
        ...withoutChannels(channelIds)._byChannel,
        for (final channelId in channelIds)
          if (other.of(channelId).isNotEmpty) channelId: other.of(channelId),
      });

  /// Keeps only the newest [cap] messages of [channelId]. Answers this same
  /// object when the channel holds no more than that.
  _HeldMessages capped(String channelId, int cap) {
    final messages = of(channelId);
    if (messages.length <= cap) return this;
    return _withChannel(channelId, messages.sublist(messages.length - cap));
  }

  _HeldMessages _withChannel(String channelId, List<ChatMessage> messages) {
    final next = {..._byChannel};
    if (messages.isEmpty) {
      next.remove(channelId);
    } else {
      next[channelId] = List.unmodifiable(messages);
    }
    return _HeldMessages._(next);
  }

  /// A stable sort by time. `List.sort` is not stable, and messages sent in the
  /// same instant must keep the order they came in.
  static List<ChatMessage> _oldestFirst(Iterable<ChatMessage> messages) {
    final numbered = messages.indexed.toList()
      ..sort((left, right) {
        final byTime = left.$2.sentAt.compareTo(right.$2.sentAt);
        return byTime != 0 ? byTime : left.$1.compareTo(right.$1);
      });
    return [for (final (_, message) in numbered) message];
  }
}
