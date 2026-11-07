import 'package:flucord/src/domain/automod_rule.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/message_actions.dart';
import 'package:flucord/src/presentation/widgets/message_forward_dialog.dart';
import 'package:flucord/src/presentation/widgets/reaction_details_dialog.dart';

/// Message actions for a test harness. Each action the session always offers
/// does nothing and succeeds, unless the test passes its own. Each optional
/// action is off, so the row hides it, unless the test passes one.
MessageActions testMessageActions({
  void Function(ChatMessage)? onReply,
  Future<bool> Function(ChatMessage, String)? onEdit,
  Future<void> Function(ChatMessage)? onDelete,
  Future<void> Function(ChatMessage, MessageReaction)? onToggleReaction,
  ReactionUsersLoader? onLoadReactionUsers,
  Future<void> Function(ChatMessage, String)? onAddReaction,
  Future<bool> Function(ChatMessage, String, int)? onCreateThread,
  Future<void> Function(ChatMessage)? onTogglePin,
  Future<void> Function(ChatMessage, AutoModAlertAction)? onResolveAlert,
  void Function(ChatMessage)? onReport,
  Future<bool> Function(ChatMessage)? onEndPoll,
  ForwardMessageCallback? onForward,
  Future<bool> Function(ChatMessage)? onToggleSuppressEmbeds,
}) => MessageActions(
  onReply: onReply ?? (_) {},
  onEdit: onEdit ?? (_, _) async => true,
  onDelete: onDelete ?? (_) async {},
  onToggleReaction: onToggleReaction ?? (_, _) async {},
  onLoadReactionUsers: onLoadReactionUsers,
  onAddReaction: onAddReaction ?? (_, _) async {},
  onCreateThread: onCreateThread ?? (_, _, _) async => true,
  onTogglePin: onTogglePin ?? (_) async {},
  onResolveAlert: onResolveAlert,
  onReport: onReport,
  onEndPoll: onEndPoll ?? (_) async => true,
  onForward: onForward,
  onToggleSuppressEmbeds: onToggleSuppressEmbeds,
);
