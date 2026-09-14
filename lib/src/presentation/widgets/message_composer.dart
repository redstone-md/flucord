import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/composer_autocomplete_catalog.dart';
import '../../domain/chat_models.dart';
import '../../domain/voice_message_recorder.dart';
import '../../theme/flucord_theme.dart';
import '../pending_attachment_picker.dart';
import 'create_poll_dialog.dart';
import '../../application/expression_favorites_controller.dart';
import '../../application/gif_picker_controller.dart';
import '../../application/slash_command_controller.dart';
import 'accessibility_scope.dart';
import 'emoji_picker.dart';
import 'gif_picker.dart';
import 'slash_command_list.dart';
import 'spell_check_scope.dart';
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
    required this.emojiSections,
    required this.stickerSections,
    required this.isSending,
    required this.onSend,
    required this.onCreatePoll,
    required this.onSendStickers,
    required this.onCancelReply,
    required this.onTyping,
    this.gifPicker,
    this.expressionFavorites,
    this.slashCommands,
    this.canAttachFiles = true,
    this.autocompleteCatalog = const ComposerAutocompleteCatalog.empty(),
    this.onSearchMembers,
    this.attachmentPicker = const NativePendingAttachmentPicker(),
    this.voiceMessageRecorder,
    this.onSendVoiceMessage,
    this.replyTo,
    this.replyAuthor,
    this.slowmode = Duration.zero,
    this.slowmodeUntil,
    this.characterLimit = 2000,
    this.attachmentSizeLimitBytes,
    super.key,
  });

  final String channelId;
  final String channelName;

  /// A voice channel's chat is not addressed with a hash, because the
  /// channel is not a text channel and `#name` would not resolve to it.
  final bool channelIsVoice;
  final String spaceName;

  /// Every server's emoji, the space this channel lives in first. The picker
  /// names each server above its own emoji.
  final List<EmojiServerSection> emojiSections;

  /// Every server's stickers, the space this channel lives in first.
  final List<StickerServerSection> stickerSections;
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

  /// The starred GIFs, stickers and emoji, when the transport holds any.
  final ExpressionFavoritesController? expressionFavorites;

  /// Slash commands, or null where they cannot be run.
  final SlashCommandController? slashCommands;
  final ComposerAutocompleteCatalog autocompleteCatalog;

  /// Asks the guild about members matching what is being typed after an
  /// at-sign, or null where the transport cannot ask.
  final ValueChanged<String>? onSearchMembers;
  final PendingAttachmentPicker attachmentPicker;
  final VoiceMessageRecorder? voiceMessageRecorder;
  final SendVoiceMessageCallback? onSendVoiceMessage;

  /// This channel's slowmode interval, or zero when there is none.
  final Duration slowmode;

  /// When slowmode lets this account send again, or null while it does not
  /// hold them. Fed by the surface that owns the last-send time, which is the
  /// channel model plus the composer's own successful sends.
  final DateTime? slowmodeUntil;

  /// The longest message this account may type here, in characters. Fed from
  /// the account's entitlements, which is where Discord derives it too.
  final int characterLimit;

  /// The largest file this account may attach here, in bytes, or null while
  /// the transport has not said. A null limit rejects nothing: a guessed
  /// limit would turn away a file the server would have taken.
  final int? attachmentSizeLimitBytes;

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
  int _charactersUsed = 0;
  bool get _canSend =>
      (_hasContent || _attachments.isNotEmpty) && !_isOverCharacterLimit;

  @override
  bool get _hasRegularMessageContent => _canSend;

  /// How many characters the typed message still has room for. Counted by
  /// characters rather than the string's code units, because Discord counts
  /// the emoji a user sees, not the two halves its encoding splits into.
  int get _charactersRemaining => widget.characterLimit - _charactersUsed;

  /// The point at which the counter appears. Discord keeps the count silent
  /// until the limit is close enough to matter, and so does this.
  bool get _showsCharacterCounter => _charactersRemaining <= 200;
  bool get _isOverCharacterLimit => _charactersRemaining < 0;

  /// Ticks once a second while slowmode holds this account back, so the
  /// countdown reaches zero on screen instead of freezing at the number it
  /// happened to be built with.
  Timer? _slowmodeTicker;
  bool _slowmodeTicking = false;

  @override
  TextEditingController get _autocompleteTextController => _controller;

  @override
  FocusNode get _autocompleteFocusNode => _focusNode;

  @override
  void initState() {
    super.initState();
    _initializeComposerAutocomplete();
    _listenToVoiceProgress();
    _startSlowmodeTicker();
  }

  @override
  void didUpdateWidget(covariant MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final channelChanged = oldWidget.channelId != widget.channelId;
    if (channelChanged) {
      _controller.clear();
      _attachments.clear();
      _hasContent = false;
      _charactersUsed = 0;
      _suppressNotifications = false;
      _discardVoiceState(oldWidget.voiceMessageRecorder);
      _resetComposerAutocomplete();
    }
    if (oldWidget.slowmodeUntil != widget.slowmodeUntil ||
        oldWidget.slowmode != widget.slowmode) {
      _startSlowmodeTicker();
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
    _slowmodeTicker?.cancel();
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

  /// How long until slowmode lets this account send again, or null when
  /// nothing is holding them back.
  Duration? get _slowmodeRemaining {
    final until = widget.slowmodeUntil;
    if (widget.slowmode == Duration.zero || until == null) return null;
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  void _startSlowmodeTicker() {
    final holding = _slowmodeRemaining != null;
    if (holding == _slowmodeTicking) return;
    _slowmodeTicking = holding;
    _slowmodeTicker?.cancel();
    _slowmodeTicker = null;
    if (!holding) return;
    _slowmodeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_slowmodeRemaining == null) {
        _slowmodeTicking = false;
        _slowmodeTicker?.cancel();
        _slowmodeTicker = null;
      }
      setState(() {});
    });
  }

  /// The countdown the composer shows, rounded up so it never reads zero
  /// while a send would still be refused.
  String _slowmodeLabel(Duration remaining) {
    final seconds =
        remaining.inSeconds +
        (remaining.inMilliseconds.remainder(1000) > 0 ? 1 : 0);
    if (seconds >= 60) {
      final minutes = seconds ~/ 60;
      final rest = seconds % 60;
      return rest == 0 ? '$minutes:00' : '$minutes:$rest';
    }
    return '$seconds';
  }

  Widget _slowmodeNotice(Duration remaining) => Padding(
    key: const ValueKey('composer-slowmode-countdown'),
    padding: const EdgeInsets.only(left: 14, bottom: 4),
    child: Row(
      children: [
        Icon(Icons.timer_outlined, size: 13, color: context.surfaces.muted),
        const SizedBox(width: 5),
        Text(
          'You are sending too fast. Wait ${_slowmodeLabel(remaining)} '
          'before sending again.',
          style: TextStyle(fontSize: 11, color: context.surfaces.muted),
        ),
      ],
    ),
  );

  Future<void> _pickAttachments() async {
    try {
      final picked = await widget.attachmentPicker.pick();
      if (!mounted || picked.isEmpty) return;
      // The size is checked before anything is attached, so the answer
      // arrives up front rather than as a failure after an upload.
      final limit = widget.attachmentSizeLimitBytes;
      final accepted = [
        for (final attachment in picked)
          if (limit == null || attachment.size <= limit) attachment,
      ];
      final rejected = picked.length - accepted.length;
      if (rejected > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              rejected == 1
                  ? 'That file is above the ${_formatSizeLimit(limit!)} '
                        'upload limit.'
                  : '$rejected files are above the '
                        '${_formatSizeLimit(limit!)} upload limit.',
            ),
          ),
        );
      }
      final reachedLimit = _attachments.merge(accepted);
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

  String _formatSizeLimit(int bytes) {
    final megabytes = bytes ~/ (1024 * 1024);
    return '$megabytes MB';
  }

  /// Applies or removes the spoiler tag on one attached file. The tag is the
  /// name, so this rewrites it: the upload carries the prefix and the
  /// receiver reads it back off the stored file.
  void _toggleAttachmentSpoiler(int index) => setState(() {
    _attachments.replaceAt(
      index,
      _attachments.items[index].asSpoiler(
        spoiler: !_attachments.items[index].isSpoiler,
      ),
    );
  });

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
      _charactersUsed = 0;
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
    setState(() {
      _hasContent = hasContent;
      _charactersUsed = next.characters.length;
    });
    _focusNode.requestFocus();
  }

  /// Empties the box after a command ran: the slash text was the command, and
  /// leaving it behind would have the next message start with it.
  void _clearComposer() {
    _controller.clear();
    if (_hasContent) {
      setState(() {
        _hasContent = false;
        _charactersUsed = 0;
      });
    }
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
          if (_slowmodeRemaining case final remaining?)
            _slowmodeNotice(remaining),
          if (widget.replyTo != null) _replyBar(context),
          if (_attachments.isNotEmpty) ...[
            PendingAttachmentStrip(
              attachments: _attachments.items,
              enabled: !widget.isSending,
              onRemove: (index) => setState(() => _attachments.removeAt(index)),
              onToggleSpoiler: _toggleAttachmentSpoiler,
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
                  // The underline comes from the local dictionary and goes
                  // nowhere: a misspelling is information for whoever is
                  // typing, not something to attach to the message.
                  spellCheckConfiguration: _spellCheckConfiguration(context),
                  onChanged: (value) {
                    final hasContent = value.trim().isNotEmpty;
                    if (hasContent) widget.onTyping();
                    // A message that begins with a slash is a command being
                    // chosen, not typed prose, so the list follows the text.
                    widget.slashCommands?.syncComposer(value);
                    final charactersUsed = value.characters.length;
                    if (hasContent != _hasContent ||
                        charactersUsed != _charactersUsed) {
                      setState(() {
                        _hasContent = hasContent;
                        _charactersUsed = charactersUsed;
                      });
                    }
                  },
                  decoration: InputDecoration(
                    hintText: widget.channelIsVoice
                        ? 'Message ${widget.channelName}'
                        : 'Message #${widget.channelName}',
                    contentPadding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
                    // Square top corners under the reply bar, so the two read
                    // as one surface. Null elsewhere keeps the theme's rounded
                    // field.
                    enabledBorder: widget.replyTo == null
                        ? null
                        : const OutlineInputBorder(
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(6),
                            ),
                            borderSide: BorderSide.none,
                          ),
                    focusedBorder: widget.replyTo == null
                        ? null
                        : OutlineInputBorder(
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(6),
                            ),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
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
                          emojiSections: widget.emojiSections,
                          onSelected: _insertEmoji,
                          favorites: widget.expressionFavorites,
                        ),
                        if (widget.gifPicker case final picker?)
                          ListenableBuilder(
                            listenable: picker,
                            builder: (_, _) => GifPickerButton(
                              controller: picker,
                              favorites: widget.expressionFavorites,
                              // A GIF is sent as its link, which is what
                              // Discord's own client posts: the embed comes
                              // from the url, not from an upload.
                              onSelected: _sendGif,
                            ),
                          ),
                        StickerPickerButton(
                          sections: widget.stickerSections,
                          isSending: widget.isSending,
                          onSend: widget.onSendStickers,
                          favorites: widget.expressionFavorites,
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
                        // The two send buttons share one key, so a disabled
                        // send updates in place; only the spinner and the
                        // recorder cross-fade.
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 130),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeOut,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: 0.9,
                                    end: 1.0,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: _trailingAction(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_showsCharacterCounter) _characterCounter(),
        ],
      ),
    );
  }

  /// The spell check configuration the composer runs with, or none where the
  /// switch is off or no service is installed.
  ///
  /// The misspelled style comes from the field's own material default: the
  /// red wavy underline is what every native app draws, and inventing a
  /// second one would only look wrong.
  SpellCheckConfiguration _spellCheckConfiguration(BuildContext context) {
    final spellcheck = AccessibilityScope.maybeOf(context)?.spellchecks ?? true;
    final service = SpellCheckScope.maybeOf(context);
    if (!spellcheck || service == null) {
      return const SpellCheckConfiguration.disabled();
    }
    return SpellCheckConfiguration(
      spellCheckService: service,
      misspelledTextStyle: TextField.materialMisspelledTextStyle,
    );
  }

  /// The remaining-character count, shown only near the limit. A negative
  /// count is red, and the send above refuses while one is showing.
  Widget _characterCounter() => Padding(
    key: const ValueKey('composer-character-counter'),
    padding: const EdgeInsets.only(left: 14, bottom: 4),
    child: Row(
      children: [
        Text(
          '$_charactersRemaining',
          style: TextStyle(
            fontSize: 11,
            color: _isOverCharacterLimit
                ? Theme.of(context).colorScheme.error
                : context.surfaces.muted,
          ),
        ),
        if (_isOverCharacterLimit) ...[
          const SizedBox(width: 5),
          Text(
            'Your message is above the limit.',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    ),
  );

  /// The last control in the composer's trailing cluster.
  Widget _trailingAction() {
    if (widget.isSending) {
      return const SizedBox.square(
        key: ValueKey('send-progress'),
        dimension: 48,
        child: Center(
          child: SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_canSend) {
      return IconButton(
        key: const ValueKey('send-message'),
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        padding: EdgeInsets.zero,
        onPressed: _send,
        icon: const Icon(Icons.send, size: 19, color: FlucordColors.brand),
        tooltip: 'Send message',
      );
    }
    // A message that is over the limit keeps its send button, greyed out
    // beside the red count, rather than swapping to the recorder: the user
    // typed words, and the honest answer is that they are too many.
    if (_hasContent || _attachments.isNotEmpty) {
      return const IconButton(
        key: ValueKey('send-message'),
        constraints: BoxConstraints.tightFor(width: 48, height: 48),
        padding: EdgeInsets.zero,
        onPressed: null,
        icon: Icon(Icons.send, size: 19),
        tooltip: 'Send message',
      );
    }
    if (widget.voiceMessageRecorder != null &&
        widget.onSendVoiceMessage != null) {
      return IconButton(
        key: const ValueKey('record-voice-message'),
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        padding: EdgeInsets.zero,
        onPressed: _canRecordVoice ? _startVoiceRecording : null,
        icon: const Icon(Icons.mic_none_rounded, size: 20),
        tooltip: 'Record voice message',
      );
    }
    return const IconButton(
      key: ValueKey('send-message'),
      constraints: BoxConstraints.tightFor(width: 48, height: 48),
      padding: EdgeInsets.zero,
      onPressed: null,
      icon: Icon(Icons.send, size: 19),
      tooltip: 'Send message',
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
      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
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
