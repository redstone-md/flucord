import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/chat_models.dart';
import '../../domain/voice_message_recorder.dart';
import '../../theme/flucord_theme.dart';
import '../pending_attachment_picker.dart';
import 'create_poll_dialog.dart';
import 'emoji_picker.dart';
import 'native_voice_message_player.dart';
import 'pending_attachment_strip.dart';
import 'sticker_picker.dart';

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
    required this.spaceName,
    required this.customEmojis,
    required this.guildStickers,
    required this.isSending,
    required this.onSend,
    required this.onCreatePoll,
    required this.onSendStickers,
    required this.onCancelReply,
    required this.onTyping,
    this.attachmentPicker = const NativePendingAttachmentPicker(),
    this.voiceMessageRecorder,
    this.onSendVoiceMessage,
    this.replyTo,
    this.replyAuthor,
    super.key,
  });

  final String channelId;
  final String channelName;
  final String spaceName;
  final List<GuildEmoji> customEmojis;
  final List<GuildSticker> guildStickers;
  final bool isSending;
  final SendMessageCallback onSend;
  final CreatePollCallback onCreatePoll;
  final SendStickersCallback onSendStickers;
  final ChatMessage? replyTo;
  final Member? replyAuthor;
  final VoidCallback onCancelReply;
  final VoidCallback onTyping;
  final PendingAttachmentPicker attachmentPicker;
  final VoiceMessageRecorder? voiceMessageRecorder;
  final SendVoiceMessageCallback? onSendVoiceMessage;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer>
    with _VoiceMessageComposerStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final PendingAttachmentSelection _attachments = PendingAttachmentSelection();
  bool _hasContent = false;
  bool _suppressNotifications = false;
  bool get _canSend => _hasContent || _attachments.isNotEmpty;

  @override
  bool get _hasRegularMessageContent => _canSend;

  @override
  void initState() {
    super.initState();
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
    }
    if (oldWidget.voiceMessageRecorder != widget.voiceMessageRecorder) {
      if (!channelChanged) {
        _discardVoiceState(oldWidget.voiceMessageRecorder);
      }
      unawaited(_voiceProgressSubscription?.cancel());
      _listenToVoiceProgress();
    }
    if (oldWidget.replyTo?.id != widget.replyTo?.id && widget.replyTo != null) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
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
              child: Focus(
                autofocus: true,
                child: TextField(
                  key: const ValueKey('message-composer'),
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 4,
                  onChanged: (value) {
                    final hasContent = value.trim().isNotEmpty;
                    if (hasContent) widget.onTyping();
                    if (hasContent != _hasContent) {
                      setState(() => _hasContent = hasContent);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Message #${widget.channelName}',
                    contentPadding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
                    prefixIcon: IconButton(
                      key: const ValueKey('add-attachment'),
                      onPressed: widget.isSending ? null : _pickAttachments,
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      tooltip: 'Add attachment',
                    ),
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
