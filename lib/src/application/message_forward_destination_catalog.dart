import '../domain/chat_models.dart';

enum MessageForwardDestinationKind {
  directMessage,
  textChannel,
  voiceChannel,
  thread,
}

final class MessageForwardDestination {
  const MessageForwardDestination({
    required this.channelId,
    required this.spaceId,
    required this.kind,
    required this.title,
    required this.path,
  });

  final String channelId;
  final String spaceId;
  final MessageForwardDestinationKind kind;
  final String title;
  final String path;
}

final class MessageForwardDestinationCatalog {
  MessageForwardDestinationCatalog._(
    List<MessageForwardDestination> destinations,
  ) : _destinations = List.unmodifiable(destinations);

  factory MessageForwardDestinationCatalog.fromWorkspace(
    ChatWorkspace workspace,
  ) => MessageForwardDestinationCatalog._([
    for (final channel in workspace.channels)
      if (channel.canAcceptMessageForward) _fromChannel(workspace, channel),
  ]);

  final List<MessageForwardDestination> _destinations;

  List<MessageForwardDestination> get destinations => _destinations;

  List<MessageForwardDestination> search(String query) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) return _destinations;
    return _destinations
        .where((destination) {
          final candidate = '${destination.title} ${destination.path}'
              .toLowerCase();
          return terms.every(candidate.contains);
        })
        .toList(growable: false);
  }

  static MessageForwardDestination _fromChannel(
    ChatWorkspace workspace,
    ConversationChannel channel,
  ) {
    final space = workspace.spaceById(channel.spaceId);
    final isDirect = channel.isDirectMessage || space.isDirectMessages;
    final kind = isDirect
        ? MessageForwardDestinationKind.directMessage
        : channel.isThread
        ? MessageForwardDestinationKind.thread
        : channel.kind == ChannelKind.voice
        ? MessageForwardDestinationKind.voiceChannel
        : MessageForwardDestinationKind.textChannel;
    final title = switch (kind) {
      MessageForwardDestinationKind.directMessage =>
        '@${_recipientName(workspace, channel)}',
      // A voice channel is not addressed with a hash in Discord, so the plain
      // name is what makes it recognisable in the picker.
      MessageForwardDestinationKind.voiceChannel => channel.name,
      MessageForwardDestinationKind.textChannel ||
      MessageForwardDestinationKind.thread => '#${channel.name}',
    };
    return MessageForwardDestination(
      channelId: channel.id,
      spaceId: channel.spaceId,
      kind: kind,
      title: title,
      path: '${space.name} / $title',
    );
  }

  static String _recipientName(
    ChatWorkspace workspace,
    ConversationChannel channel,
  ) {
    final recipientId = channel.recipientId;
    if (recipientId == null) return channel.name;
    return workspace.memberOrNull(recipientId)?.displayName ?? channel.name;
  }
}
