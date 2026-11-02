import '../../domain/chat_models.dart';
import '../../domain/message_embed.dart';

/// The ids a message body names with Discord's mention markers.
final class BodyMentions {
  const BodyMentions._({
    this.members = const {},
    this.roles = const {},
    this.channels = const {},
  });

  factory BodyMentions.of(String body) {
    if (!body.contains('<')) return const BodyMentions._();
    return BodyMentions._(
      members: _ids(_memberMention, body),
      roles: _ids(_roleMention, body),
      channels: _ids(_channelMention, body),
    );
  }

  static final _memberMention = RegExp(r'<@!?(\d+)>');
  static final _roleMention = RegExp(r'<@&(\d+)>');
  static final _channelMention = RegExp(r'<#(\d+)>');

  final Set<String> members;
  final Set<String> roles;
  final Set<String> channels;

  static Set<String> _ids(RegExp mention, String body) => {
    for (final match in mention.allMatches(body)) match[1]!,
  };
}

/// Every id that the rows of a list of messages draw.
final class _NamedIds {
  _NamedIds.of(List<ChatMessage> messages) {
    for (final message in messages) {
      members.add(message.authorId);
      channels.add(message.channelId);
      final sourceChannel = message.reference?.channelId;
      if (sourceChannel != null) channels.add(sourceChannel);
      final reply = message.reply;
      if (reply != null) {
        members.add(reply.authorId);
        _addBody(reply.body);
      }
      _addBody(message.body);
      _addEmbeds(message.embeds);
      for (final snapshot in message.snapshots) {
        _addBody(snapshot.body);
        _addEmbeds(snapshot.embeds);
      }
    }
  }

  /// A channel's list stays the same object until the channel changes, so its
  /// bodies are read once per change, not once per notification.
  static final _byMessages = Expando<_NamedIds>();

  final members = <String>{};
  final roles = <String>{};
  final channels = <String>{};

  void _addEmbeds(List<MessageEmbed> embeds) {
    for (final embed in embeds) {
      _addBody(embed.description ?? '');
      for (final field in embed.fields) {
        _addBody(field.value);
      }
    }
  }

  void _addBody(String body) {
    final mentions = BodyMentions.of(body);
    members.addAll(mentions.members);
    roles.addAll(mentions.roles);
    channels.addAll(mentions.channels);
  }
}

/// What the rows of [channel] draw from [workspace]: the channel's messages, the
/// people and channels those messages name, and the roles and emoji that colour
/// them.
///
/// Traffic from another server changes the workspace, and changes nothing here.
/// That is what lets the timeline skip it.
///
/// Rows draw from this and nothing else. An action that needs more, such as the
/// channels Forward offers, reads the workspace when the user asks for it, with
/// `ChatScope.workspaceNow`.
List<Object?> timelineDependencies(
  ChatWorkspace workspace,
  ConversationChannel channel,
) {
  final messages = workspace.messagesFor(channel.id);
  final named = _NamedIds._byMessages[messages] ??= _NamedIds.of(messages);
  final members = [for (final id in named.members) workspace.memberOrNull(id)];
  return [
    messages,
    members,
    [
      for (final id in named.roles) workspace.roleOrNull(id),
      for (final member in members)
        for (final id in member?.membershipIn(channel.spaceId)?.roleIds ?? [])
          workspace.roleOrNull(id),
    ],
    [for (final id in named.channels) workspace.channelOrNull(id)],
    workspace.emojisFor(channel.spaceId),
    workspace.currentMemberId,
  ];
}
