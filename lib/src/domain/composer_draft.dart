import 'chat_models.dart';

/// What the user has written in one channel and not sent yet.
final class ComposerDraft {
  const ComposerDraft({
    this.text = '',
    this.attachments = const [],
    this.silent = false,
    this.replyTo,
  });

  final String text;
  final List<PendingAttachment> attachments;

  /// Whether this message goes out without notifications. It stays with the
  /// draft, so a message set to be quiet does not come back loud.
  final bool silent;
  final ChatMessage? replyTo;

  bool get isEmpty =>
      text.isEmpty && attachments.isEmpty && !silent && replyTo == null;

  ComposerDraft withReply(ChatMessage? replyTo) => ComposerDraft(
    text: text,
    attachments: attachments,
    silent: silent,
    replyTo: replyTo,
  );
}

/// Holds one draft per channel, for one signed-in account.
///
/// The composer and the conversation pane read and write through this. A store
/// that keeps drafts across a relaunch can load them before it is first read
/// and save on each write, so this interface does not need to change.
abstract interface class ComposerDraftStore {
  /// The draft of [channelId], or an empty one.
  ComposerDraft read(String channelId);

  void write(String channelId, ComposerDraft draft);
}

/// Keeps drafts until the app quits or the account changes.
final class MemoryComposerDraftStore implements ComposerDraftStore {
  final Map<String, ComposerDraft> _drafts = {};

  @override
  ComposerDraft read(String channelId) =>
      _drafts[channelId] ?? const ComposerDraft();

  @override
  void write(String channelId, ComposerDraft draft) {
    if (draft.isEmpty) {
      _drafts.remove(channelId);
    } else {
      _drafts[channelId] = draft;
    }
  }
}
