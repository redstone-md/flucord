import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/composer_autocomplete_catalog.dart';
import '../../domain/chat_models.dart';
import '../../domain/voice_message_recorder.dart';
import '../../theme/flucord_theme.dart';
import '../pending_attachment_picker.dart';
import 'create_poll_dialog.dart';
import '../../application/gif_picker_controller.dart';
import '../../application/slash_command_controller.dart';
import 'emoji_picker.dart';
import 'gif_picker.dart';
import 'slash_command_list.dart';
import 'native_voice_message_player.dart';
import 'pending_attachment_strip.dart';
import 'remote_identity_image.dart';
import 'sticker_picker.dart';

part 'message_composer_autocomplete.dart';
part 'message_composer_voice.dart';

typedef SendMessageCallback =
    Future<bool> Function(
      String body,
      List<PendingAttachment> attachments,
      String? replyToMessageId,
      bool suppressNotifications,
    );
typedef SendVoiceMessageCallback =
    Future<bool> Function(PendingVoiceMessage voiceMessage);

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    required this.channelId,
    required this.channelName,
    this.channelIsVoice = false,
    required this.spaceName,
    required this.customEmojis,
    required this.guildStickers,
    required this.isSending,
    required this.onSend,
    required this.onCreatePoll,
    required this.onSendStickers,
    required this.onCancelReply,
    required this.onTyping,
    this.gifPicker,
    this.slashCommands,
    this.canAttachFiles = true,
    this.autocompleteCatalog = const ComposerAutocompleteCatalog.empty(),
    this.onSearchMembers,
    this.attachmentPicker = const NativePendingAttachmentPicker(),
    this.voiceMessageRecorder,
    this.onSendVoiceMessage,
    this.replyTo,
    this.replyAuthor,
    super.key,
  });

  final String channelId;
  final String channelName;

  /// A voice channel's chat is not addressed with a hash, because the
  /// channel is not a text channel and `#name` would not resolve to it.
  final bool channelIsVoice;
  final String spaceName;
  final List<GuildEmoji> customEmojis;
  final List<GuildSticker> guildStickers;
  final bool isSending;
  final SendMessageCallback onSend;
  final CreatePollCallback onCreatePoll;
  final SendStickersCallback onSendStickers;

  /// `ATTACH_FILES`. Without it the upload control is not offered at all,
  /// rather than offered and rejected once the file is already picked.
  final bool canAttachFiles;
  final ChatMessage? replyTo;
  final Member? replyAuthor;
  final VoidCallback onCancelReply;
  final VoidCallback onTyping;

  /// The GIF picker, or null on a transport that has no provider proxy.
  final GifPickerController? gifPicker;

  /// Slash commands, or null where they cannot be run.
  final SlashCommandController? slashCommands;
  final ComposerAutocompleteCatalog autocompleteCatalog;

  /// Asks the guild about members matching what is being typed after an
  /// at-sign, or null where the transport cannot ask.
  final ValueChanged<String>? onSearchMembers;
  final PendingAttachmentPicker attachmentPicker;
  final VoiceMessageRecorder? voiceMessageRecorder;
  final SendVoiceMessageCallback? onSendVoiceMessage;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer>
    with _ComposerAutocompleteStateMixin, _VoiceMessageComposerStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final PendingAttachmentSelection _attachments = PendingAttachmentSelection();
  bool _hasContent = false;
  bool _suppressNotifications = false;
  bool get _canSend => _hasContent || _attachments.isNotEmpty;

  @override
  bool get _hasRegularMessageContent => _canSend;

  @override
  TextEditingController get _autocompleteTextController => _controller;

  @override
  FocusNode get _autocompleteFocusNode => _focusNode;

  @override
  void initState() {
    super.initState();
    _initializeComposerAutocomplete();
    _listenToVoiceProgress();
  }

  @override
  void didUpdateWidget(covariant MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final channelChanged = oldWidget.channelId != widget.channelId;
    if (channelChanged) {
      _controller.clear();
      _attachments.clear();
      _hasContent = false;
      _suppressNotifications = false;
      _discardVoiceState(oldWidget.voiceMessageRecorder);
      _resetComposerAutocomplete();
    }
    if (oldWidget.voiceMessageRecorder != widget.voiceMessageRecorder) {
      if (!channelChanged) {
        _discardVoiceState(oldWidget.voiceMessageRecorder);
      }
      unawaited(_voiceProgressSubscription?.cancel());
      _listenToVoiceProgress();
    }
    if (oldWidget.autocompleteCatalog != widget.autocompleteCatalog &&
        !channelChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshComposerAutocomplete();
      });
    }
    if (oldWidget.replyTo?.id != widget.replyTo?.id && widget.replyTo != null) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _disposeComposerAutocomplete();
    _voiceGeneration++;
    unawaited(_voiceProgressSubscription?.cancel());
    final recorder = widget.voiceMessageRecorder;
    final pending = _pendingVoiceMessage;
    if ((recorder?.isRecording ?? false) && !_isUploadingVoice) {
      unawaited(_cancelVoiceRecordingIgnoringErrors(recorder));
    }
    if (pending != null && !_isUploadingVoice) {
      unawaited(_deleteVoiceMessageIgnoringErrors(recorder, pending));
    }
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    try {
      final picked = await widget.attachmentPicker.pick();
      if (!mounted || picked.isEmpty) return;
      final reachedLimit = _attachments.merge(picked);
      setState(() {});
      if (reachedLimit) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can attach up to 10 files.')),
        );
      }
      _focusNode.requestFocus();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The file picker could not be opened.')),
      );
    }
  }

  Future<void> _send() async {
    if (!_canSend || widget.isSending) return;
    final sent = await widget.onSend(
      _controller.text,
      _attachments.items,
      widget.replyTo?.id,
      _suppressNotifications,
    );
    if (!mounted || !sent) return;
    _controller.clear();
    setState(() {
      _hasContent = false;
      _attachments.clear();
      _suppressNotifications = false;
    });
    _focusNode.requestFocus();
  }

  /// Sends the GIF straight away, as Discord's own client does: the picker is
  /// a send action, not a way to paste a link into a half-written message.
  Future<void> _sendGif(String url) async {
    if (widget.isSending) return;
    await widget.onSend(
      url,
      const [],
      widget.replyTo?.id,
      _suppressNotifications,
    );
  }

  void _insertEmoji(String token) {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final next = text.replaceRange(start, end, token);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    final hasContent = next.trim().isNotEmpty;
    if (hasContent) widget.onTyping();
    setState(() => _hasContent = hasContent);
    _focusNode.requestFocus();
  }

  /// Empties the box after a command ran: the slash text was the command, and
  /// leaving it behind would have the next message start with it.
  void _clearComposer() {
    _controller.clear();
    if (_hasContent) setState(() => _hasContent = false);
  }

  void _showPollDialog() {
    if (widget.isSending) return;
    CreatePollDialog.show(context, onCreate: widget.onCreatePoll);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: context.surfaces.canvas,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.slashCommands case final commands?)
            ListenableBuilder(
              listenable: commands,
              builder: (_, _) => SlashCommandList(
                controller: commands,
                onPicked: _clearComposer,
              ),
            ),
          if (widget.replyTo != null) _replyBar(context),
          if (_attachments.isNotEmpty) ...[
            PendingAttachmentStrip(
              attachments: _attachments.items,
              enabled: !widget.isSending,
              onRemove: (index) => setState(() => _attachments.removeAt(index)),
            ),
            const SizedBox(height: 6),
          ],
          if (_hasVoiceSession)
            _VoiceMessageComposerBar(
              progress: _voiceProgress,
              isRecording: _isRecordingVoice,
              isUploading: _isUploadingVoice,
              hasPendingMessage: _pendingVoiceMessage != null,
              error: _voiceError,
              onCancel: _isUploadingVoice ? null : _cancelVoiceMessage,
              onPrimaryAction: _isUploadingVoice
                  ? null
                  : _isRecordingVoice
                  ? _stopAndSendVoiceMessage
                  : _retryVoiceMessage,
            )
          else
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): _send,
              },
              child: _buildComposerAutocompletePortal(
                child: TextField(
                  key: const ValueKey('message-composer'),
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 4,
                  onChanged: (value) {
                    final hasContent = value.trim().isNotEmpty;
                    if (hasContent) widget.onTyping();
                    // A message that begins with a slash is a command being
                    // chosen, not typed prose, so the list follows the text.
                    widget.slashCommands?.syncComposer(value);
                    if (hasContent != _hasContent) {
                      setState(() => _hasContent = hasContent);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: widget.channelIsVoice
                        ? 'Message ${widget.channelName}'
                        : 'Message #${widget.channelName}',
                    contentPadding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
                    prefixIcon: widget.canAttachFiles
                        ? IconButton(
                            key: const ValueKey('add-attachment'),
                            onPressed: widget.isSending
                                ? null
                                : _pickAttachments,
                            icon: const Icon(
                              Icons.add_circle_outline,
                              size: 20,
                            ),
                            tooltip: 'Add attachment',
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints.tightFor(
                      width: 240,
                      height: 48,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EmojiPickerButton(
                          spaceName: widget.spaceName,
                          customEmojis: widget.customEmojis,
                          onSelected: _insertEmoji,
                        ),
                        if (widget.gifPicker case final picker?)
                          ListenableBuilder(
                            listenable: picker,
                            builder: (_, _) => GifPickerButton(
                              controller: picker,
                              // A GIF is sent as its link, which is what
                              // Discord's own client posts: the embed comes
                              // from the url, not from an upload.
                              onSelected: _sendGif,
                            ),
                          ),
                        StickerPickerButton(
                          stickers: widget.guildStickers,
                          isSending: widget.isSending,
                          onSend: widget.onSendStickers,
                        ),
                        IconButton(
                          key: const ValueKey('create-poll'),
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: widget.isSending ? null : _showPollDialog,
                          icon: const Icon(Icons.poll_outlined, size: 19),
                          tooltip: 'Create poll',
                        ),
                        IconButton(
                          key: const ValueKey('send-silently'),
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          padding: EdgeInsets.zero,
                          isSelected: _suppressNotifications,
                          onPressed: widget.isSending
                              ? null
                              : () => setState(
                                  () => _suppressNotifications =
                                      !_suppressNotifications,
                                ),
                          icon: const Icon(
                            Icons.notifications_outlined,
                            size: 19,
                          ),
                          selectedIcon: const Icon(
                            Icons.notifications_off_outlined,
                            size: 19,
                            color: FlucordColors.brand,
                          ),
                          tooltip: _suppressNotifications
                              ? 'Send with notifications'
                              : 'Send silently',
                        ),
                        if (widget.isSending)
                          const SizedBox.square(
                            dimension: 48,
                            child: Center(
                              child: SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        else if (_canSend)
                          IconButton(
                            key: const ValueKey('send-message'),
                            constraints: const BoxConstraints.tightFor(
                              width: 48,
                              height: 48,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: _send,
                            icon: const Icon(
                              Icons.send,
                              size: 19,
                              color: FlucordColors.brand,
                            ),
                            tooltip: 'Send message',
                          )
                        else if (widget.voiceMessageRecorder != null &&
                            widget.onSendVoiceMessage != null)
                          IconButton(
                            key: const ValueKey('record-voice-message'),
                            constraints: const BoxConstraints.tightFor(
                              width: 48,
                              height: 48,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: _canRecordVoice
                                ? _startVoiceRecording
                                : null,
                            icon: const Icon(Icons.mic_none_rounded, size: 20),
                            tooltip: 'Record voice message',
                          )
                        else
                          const IconButton(
                            key: ValueKey('send-message'),
                            constraints: BoxConstraints.tightFor(
                              width: 48,
                              height: 48,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: null,
                            icon: Icon(Icons.send, size: 19),
                            tooltip: 'Send message',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _replyBar(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.only(left: 12),
    decoration: BoxDecoration(
      color: context.surfaces.surface,
      border: Border(
        top: BorderSide(color: context.surfaces.border),
        left: BorderSide(color: context.surfaces.border),
        right: BorderSide(color: context.surfaces.border),
      ),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    ),
    child: Row(
      children: [
        Icon(Icons.reply, size: 14, color: context.surfaces.muted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Replying to ${widget.replyAuthor?.displayName ?? 'Unknown user'}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
        IconButton(
          onPressed: widget.onCancelReply,
          icon: const Icon(Icons.close, size: 16),
          tooltip: 'Cancel reply',
        ),
      ],
    ),
  );
}

/// Stands in for the composer in a channel the account may read but not post
/// in, which is what `SEND_MESSAGES` withheld actually looks like: Discord
/// removes the input rather than letting a message be typed and refused.
class ReadOnlyChannelNotice extends StatelessWidget {
  const ReadOnlyChannelNotice({super.key});

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('read-only-channel-notice'),
    constraints: const BoxConstraints(minHeight: 52),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: context.surfaces.surface,
      border: Border(top: BorderSide(color: context.surfaces.border)),
    ),
    child: Row(
      children: [
        Icon(Icons.block_outlined, size: 17, color: context.surfaces.muted),
        const SizedBox(width: 9),
        const Expanded(
          child: Text(
            'You do not have permission to send messages here.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}
