part of 'flucord_shell.dart';

/// Starting, running and leaving group DMs, and closing DMs.
extension _FlucordShellDirectMessages on FlucordShell {
  /// The account's friends, the only people a group DM can hold.
  List<DirectMessageCandidate> _friendCandidates({
    Set<String> except = const {},
  }) {
    final workspace = chatController.workspace!;
    return [
      for (final person in DirectMessageCandidate.from(
        members: workspace.members,
        currentMemberId: workspace.currentMemberId,
        relationships: chatController.relationships?.relationships ?? const [],
      ))
        if (person.isFriend && !except.contains(person.id)) person,
    ];
  }

  void _tellFailure(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _newGroupDirectMessage(BuildContext context) async {
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (_) => FriendPickerDialog(
        title: 'Create group DM',
        confirmLabel: 'Create group DM',
        friends: _friendCandidates(),
        maxPicked: groupDirectMessageCapacity - 1,
        minPicked: 2,
      ),
    );
    if (picked == null || !context.mounted) return;
    final channelId = await chatController.createGroupDirectMessage(picked);
    if (!context.mounted) return;
    if (channelId == null) {
      return _tellFailure(context, 'The group DM could not be started');
    }
    _openDestination(
      spaceId: CommunitySpace.directMessagesId,
      channelId: channelId,
    );
  }

  Future<void> _addToGroup(
    BuildContext context,
    ConversationChannel channel,
  ) async {
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (_) => FriendPickerDialog(
        title: 'Add friends to ${channel.name}',
        confirmLabel: 'Add',
        friends: _friendCandidates(except: channel.recipientIds.toSet()),
        maxPicked: groupDirectMessageCapacity - 1 - channel.recipientIds.length,
      ),
    );
    if (picked == null) return;
    for (final userId in picked) {
      if (!await chatController.addGroupRecipient(channel.id, userId)) {
        if (!context.mounted) return;
        return _tellFailure(context, 'Not everybody could be added');
      }
    }
  }

  /// Leaves a group after asking, or closes a DM with one person at once,
  /// the way Discord does.
  Future<void> _closeDirectMessage(
    BuildContext context,
    ConversationChannel channel,
  ) async {
    if (channel.isGroupDirectMessage &&
        !await confirmDestructiveAction(
          context,
          title: "Leave '${channel.name}'",
          message:
              'You will stop getting its messages. You can only come back if '
              'somebody adds you again.',
          confirmLabel: 'Leave group',
        )) {
      return;
    }
    if (!await chatController.closeDirectMessage(channel.id) &&
        context.mounted) {
      _tellFailure(
        context,
        channel.isGroupDirectMessage
            ? 'The group could not be left'
            : 'The DM could not be closed',
      );
    }
  }

  Future<void> _editGroup(BuildContext context, String channelId) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => ListenableBuilder(
          listenable: chatController,
          builder: (_, _) {
            final workspace = chatController.workspace;
            final channel = workspace?.channelOrNull(channelId);
            if (workspace == null || channel == null) {
              // The account is no longer in the group.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              });
              return const SizedBox.shrink();
            }
            return GroupDirectMessageSettingsDialog(
              channel: channel,
              recipients: [
                for (final id in channel.recipientIds)
                  ?workspace.memberOrNull(id),
              ],
              isOwner: channel.ownerId == workspace.currentMemberId,
              onRename: (name) =>
                  chatController.renameGroupDirectMessage(channelId, name),
              onSetIcon: (dataUri) =>
                  chatController.setGroupDirectMessageIcon(channelId, dataUri),
              onRemove: (userId) =>
                  chatController.removeGroupRecipient(channelId, userId),
            );
          },
        ),
      );
}
