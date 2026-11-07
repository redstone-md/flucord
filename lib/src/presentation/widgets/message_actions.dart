import 'package:flutter/foundation.dart';

import '../../domain/automod_rule.dart';
import '../../domain/chat_models.dart';
import 'message_forward_dialog.dart';
import 'poll_voters_dialog.dart';
import 'reaction_details_dialog.dart';

/// Everything the timeline can do to a message in this session.
///
/// The conversation pane builds one from what the session can do, and the
/// message list hands it to each row. A null field is an action the session
/// cannot offer, and then no row shows it. Rules about one message, such as
/// "own message" or "the poll is closed", stay in the row.
@immutable
final class MessageActions {
  const MessageActions({
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleReaction,
    this.onLoadReactionUsers,
    required this.onAddReaction,
    this.onToggleSuperReaction,
    this.onAddSuperReaction,
    this.onMarkUnread,
    required this.onCreateThread,
    required this.onTogglePin,
    this.onResolveAlert,
    this.onReport,
    required this.onEndPoll,
    this.onVotePoll,
    this.onLoadPollVoters,
    this.onForward,
    this.onToggleSuppressEmbeds,
    this.onRetrySend,
    this.onDiscardSend,
  });

  final ValueChanged<ChatMessage> onReply;

  /// Saves a new text for a message. True when Discord took it.
  final Future<bool> Function(ChatMessage, String) onEdit;
  final Future<void> Function(ChatMessage) onDelete;
  final Future<void> Function(ChatMessage, MessageReaction) onToggleReaction;

  /// Loads who reacted. Null hides the list.
  final ReactionUsersLoader? onLoadReactionUsers;
  final Future<void> Function(ChatMessage, String) onAddReaction;

  /// Takes back or adds the account's super reaction on a chip. Null where
  /// the account cannot send super reactions; then [onAddSuperReaction] is
  /// null too.
  final Future<void> Function(ChatMessage, MessageReaction)?
  onToggleSuperReaction;

  /// Adds a new super reaction from the hover bar.
  final Future<void> Function(ChatMessage, String)? onAddSuperReaction;

  /// Makes a message and everything after it unread again. Null on a
  /// transport with no read state.
  final Future<void> Function(ChatMessage)? onMarkUnread;

  /// Starts a thread from a message with a name and an archive time in
  /// minutes. True when the thread exists.
  final Future<bool> Function(ChatMessage, String, int) onCreateThread;
  final Future<void> Function(ChatMessage) onTogglePin;

  /// Acts on an AutoMod alert. Null where the transport cannot.
  final Future<void> Function(ChatMessage, AutoModAlertAction)? onResolveAlert;

  /// Opens the report flow for a message. Null where there is none.
  final void Function(ChatMessage)? onReport;
  final Future<bool> Function(ChatMessage) onEndPoll;

  /// Sets the account's whole vote in a poll. Null where the session cannot
  /// vote; then the answers take no tap.
  final Future<bool> Function(ChatMessage, Set<int>)? onVotePoll;

  /// Loads who voted for an answer. Null hides the list.
  final PollVotersLoader? onLoadPollVoters;

  /// Forwards a message. Null hides the action.
  final ForwardMessageCallback? onForward;

  /// Suppresses or restores a message's embeds. Null hides the action.
  final Future<bool> Function(ChatMessage)? onToggleSuppressEmbeds;

  /// Sends a failed message again.
  final ValueChanged<OutgoingMessage>? onRetrySend;

  /// Drops a message that is sending or failed.
  final ValueChanged<OutgoingMessage>? onDiscardSend;
}
