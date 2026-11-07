import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/composer_autocomplete_catalog.dart';
import '../../application/send_failure.dart';
import '../../domain/chat_models.dart';
import '../../domain/composer_draft.dart';
import '../../domain/voice_message_recorder.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import '../clipboard_attachments.dart';
import '../pending_attachment_picker.dart';
import 'create_poll_dialog.dart';
import '../../application/expression_favorites_controller.dart';
import '../../application/gif_picker_controller.dart';
import '../../application/slash_command_controller.dart';
import 'accessibility_dials.dart';
import 'accessibility_scope.dart';
import 'emoji_picker.dart';
import 'flucord_button.dart';
import 'flucord_icon_button.dart';
import 'flucord_menu.dart';
import 'gif_picker.dart';
import 'slash_command_list.dart';
import 'spell_check_scope.dart';
import 'native_voice_message_player.dart';
import 'voice_recording_waveform.dart';
import 'pending_attachment_strip.dart';
import 'recessed_field.dart';
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

/// Hands a finished recording over to be sent. The composer is done with it
/// from here. [release] deletes the recording file: call it once the file is
/// no longer needed.
typedef SendVoiceMessageCallback =
    void Function(PendingVoiceMessage voiceMessage, void Function() release);

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    required this.channelId,
    required this.channelName,
    required this.drafts,
    this.channelHintPrefix = '#',
    required this.spaceName,
    required this.emojiSections,
    required this.stickerSections,
    required this.isSending,
    required this.onSend,
    required this.onCreatePoll,
    this.onSendStickers,
    required this.onCancelReply,
    required this.onTyping,
    this.onEditLastMessage,
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
    this.replyAuthorName,
    this.slowmode = Duration.zero,
    this.slowmodeUntil,
    this.characterLimit = 2000,
    this.attachmentSizeLimitBytes,
    super.key,
  });

  final String channelId;
  final String channelName;

  /// Where the box keeps its text and files while another channel is open.
  final ComposerDraftStore drafts;

  /// What stands before the channel's name in the box's hint: `#` for a text
  /// channel, `@` for a person, nothing where `#name` would not resolve.
  final String channelHintPrefix;
  final String spaceName;

  /// Every server's emoji, the space this channel lives in first. The picker
  /// names each server above its own emoji.
  final List<EmojiServerSection> emojiSections;

  /// Every server's stickers, the space this channel lives in first.
  final List<StickerServerSection> stickerSections;
  final bool isSending;
  final SendMessageCallback onSend;
  final CreatePollCallback onCreatePoll;

  /// Sends stickers, or null where the session cannot. Then there is no
  /// sticker picker.
  final SendStickersCallback? onSendStickers;

  /// `ATTACH_FILES`. Without it the upload control is not offered at all,
  /// rather than offered and rejected once the file is already picked.
  final bool canAttachFiles;
  final ChatMessage? replyTo;

  /// The name the replied-to author goes by where the reply is written.
  final String? replyAuthorName;
  final VoidCallback onCancelReply;
  final VoidCallback onTyping;

  /// Opens the account's last message for editing, and answers whether there
  /// was one. Up on an empty box asks for it.
  final bool Function()? onEditLastMessage;

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
  /// hold them. Until then nothing goes out from here: the server would only
  /// refuse it.
  final DateTime? slowmodeUntil;

  /// The longest message this account may type here, in characters. Fed from
  /// the account's entitlements, which is where Discord derives it too.
  final int characterLimit;

  /// The largest file this account may attach here, in bytes, or null while
  /// the transport has not said. A null limit rejects nothing: a guessed
  /// limit would turn away a file the server would have taken.
  final int? attachmentSizeLimitBytes;

  @override
  State<MessageComposer> createState() => MessageComposerState();
}

/// Public so the conversation pane can reach the box through a global key: the
/// keyboard works from outside this widget.
class MessageComposerState extends State<MessageComposer>
    with _ComposerAutocompleteStateMixin, _VoiceMessageComposerStateMixin {
  /// The room between the box and the chat card's edges.
  static const _gutter = 16.0;

  /// The empty box's height. It grows with its text.
  static const _height = 44.0;

  /// Above and below one line of text, so one line makes [_height].
  static final _textInset = (_height - FlucordTextRole.body.lineHeight) / 2;

  /// From the box's edge to the first and last button.
  static const _buttonInset = 8.0;
  static const _buttonGap = 4.0;

  /// The button slots keep the buttons' own height, so [_height] holds.
  static const _buttonRow = BoxConstraints(
    minWidth: FlucordIconButton.size,
    minHeight: FlucordIconButton.size,
  );

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final PendingAttachmentSelection _attachments = PendingAttachmentSelection();
  late final _pasteAction = _PasteAction(_paste);
  bool _hasContent = false;
  bool _suppressNotifications = false;
  int _charactersUsed = 0;
  bool get _canSend =>
      (_hasContent || _attachments.isNotEmpty) &&
      !_isOverCharacterLimit &&
      !_isHeldBySlowmode;

  @override
  bool get _hasRegularMessageContent => _canSend;

  @override
  bool get _isHeldBySlowmode => _slowmodeRemaining != null;

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
  FocusOnKeyEventCallback get _composerKeyHandler => _handleComposerKey;

  @override
  void initState() {
    super.initState();
    _openDraft();
    _initializeComposerAutocomplete();
    _listenToVoiceProgress();
    _startSlowmodeTicker();
    // A box that appears under a room or a read-only notice is where typing
    // goes next. It has no route to ask about until the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focus();
    });
    DesktopDrop.instance
      ..init()
      ..addRawDropEventListener(_onFilesDropped);
  }

  @override
  void didUpdateWidget(covariant MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final channelChanged = oldWidget.channelId != widget.channelId;
    if (channelChanged) {
      _saveDraft(oldWidget.channelId);
      _discardVoiceState(oldWidget.voiceMessageRecorder);
      _withAutocompleteClosed(_openDraft);
      focus();
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
    _updateAutocompleteCatalog(channelChanged: channelChanged);
    if (oldWidget.replyTo?.id != widget.replyTo?.id && widget.replyTo != null) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    DesktopDrop.instance.removeRawDropEventListener(_onFilesDropped);
    _saveDraft(widget.channelId);
    _disposeComposerAutocomplete();
    _slowmodeTicker?.cancel();
    _voiceGeneration++;
    unawaited(_voiceProgressSubscription?.cancel());
    _voiceLevels.dispose();
    final recorder = widget.voiceMessageRecorder;
    if ((recorder?.isRecording ?? false) && !_isStoppingVoice) {
      unawaited(_cancelVoiceRecordingIgnoringErrors(recorder));
    }
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Puts the cursor in the box, unless a dialog or a menu covers it. A focus
  /// request from behind one would take the keyboard away from it.
  void focus() {
    if (ModalRoute.isCurrentOf(context) ?? true) _focusNode.requestFocus();
  }

  /// Types [text] at the caret on behalf of a key pressed elsewhere, as if the
  /// box had the focus all along. Answers false while a voice message stands in
  /// for the box.
  bool typeText(String text) {
    if (_hasVoiceSession) return false;
    _focusNode.requestFocus();
    // Suggestions only open for a box that has the focus, and a request lands
    // at the end of this event. A first `@` must not miss them.
    FocusManager.instance.applyFocusChangesIfNeeded();
    _insertText(text);
    return true;
  }

  /// Up on an empty box edits the last message, as in Discord. Suggestions see
  /// the key first, and any other Up moves the caret.
  KeyEventResult _handleComposerKey(FocusNode node, KeyEvent event) {
    final suggestions = _handleComposerAutocompleteKey(node, event);
    if (suggestions != KeyEventResult.ignored) return suggestions;
    if (_controller.text.isNotEmpty ||
        !const SingleActivator(
          LogicalKeyboardKey.arrowUp,
        ).accepts(event, HardwareKeyboard.instance)) {
      return KeyEventResult.ignored;
    }
    return (widget.onEditLastMessage?.call() ?? false)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// What the box holds now. The reply target is the pane's to set, so it is
  /// not part of this.
  ComposerDraft get _boxContent => ComposerDraft(
    text: _controller.text,
    attachments: _attachments.items,
    silent: _suppressNotifications,
  );

  void _saveDraft(String channelId) {
    final replyTo = widget.drafts.read(channelId).replyTo;
    widget.drafts.write(channelId, _boxContent.withReply(replyTo));
  }

  /// Fills the box from the open channel's draft, without telling anyone that
  /// the user is typing.
  void _openDraft() {
    final draft = widget.drafts.read(widget.channelId);
    _showInBox(draft);
    if (draft.text.isEmpty) return;
    // The pane points the command list at this channel in a microtask, which
    // closes the list, and it queued that one first. A `/ban` that comes back
    // with no list would go out as plain text.
    scheduleMicrotask(() {
      if (mounted) widget.slashCommands?.syncComposer(_controller.text);
    });
  }

  void _showInBox(ComposerDraft draft) {
    final text = draft.text;
    // Leaves the caret alone when the text stays.
    if (_controller.text != text) {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    _hasContent = text.trim().isNotEmpty;
    _charactersUsed = text.characters.length;
    _suppressNotifications = draft.silent;
    _attachments
      ..clear()
      ..merge(draft.attachments);
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
      final rest = (seconds % 60).toString().padLeft(2, '0');
      return '${seconds ~/ 60}:$rest';
    }
    return '$seconds';
  }

  /// One line of small text above the field.
  Widget _composerNotice({
    required Key key,
    required FlucordIconData icon,
    required String text,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.only(left: 14, bottom: 4),
    child: Row(
      children: [
        FlucordIcon(icon, size: 13, color: context.surfaces.muted),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: FlucordTextRole.caption.style.copyWith(
              color: context.surfaces.muted,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _slowmodeNotice(Duration remaining) => _composerNotice(
    key: const ValueKey('composer-slowmode-countdown'),
    icon: FlucordIcons.slowmode,
    text: sendingTooFast(_slowmodeLabel(remaining)),
  );

  Future<void> _pickAttachments() => _attachFrom(
    widget.attachmentPicker.pick,
    failure: 'The file picker could not be opened.',
  );

  /// A drop anywhere in the window lands here, as it does in Discord: the
  /// system offers a drop over the whole window, so a part of it that ignored
  /// the file would look broken.
  void _onFilesDropped(DropEvent event) {
    if (event is! DropDoneEvent || !widget.canAttachFiles) return;
    // A dialog in front of the chat has the user's attention, not this box.
    if (ModalRoute.isCurrentOf(context) == false) return;
    unawaited(
      _attachFrom(
        () => pendingAttachmentsAt(event.files.map((file) => file.path)),
        failure: 'Those files could not be read.',
      ),
    );
  }

  /// Ctrl+V. Text pastes as it always has, even with a picture beside it: a
  /// spreadsheet or a document copies both, and the user wants the words. So
  /// only a clipboard with no text attaches anything.
  Future<void> _paste(VoidCallback pasteText) async {
    final attaches = widget.canAttachFiles && !await Clipboard.hasStrings();
    if (!mounted) return;
    if (!attaches) return pasteText();
    await _attachFrom(
      ClipboardAttachments.read,
      failure: 'The clipboard could not be read.',
    );
  }

  /// The one way a file reaches the strip, wherever it came from.
  ///
  /// A channel left while [source] reads keeps nothing: a file meant for one
  /// conversation must not appear in the next.
  Future<void> _attachFrom(
    Future<List<PendingAttachment>> Function() source, {
    required String failure,
  }) async {
    final channelId = widget.channelId;
    try {
      final picked = await source();
      if (!mounted || widget.channelId != channelId || picked.isEmpty) return;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  String _formatSizeLimit(int bytes) {
    final megabytes = bytes ~/ (1024 * 1024);
    return '$megabytes MB';
  }

  /// Takes one file off the strip. A pasted picture's temp file goes with it,
  /// because nothing will send it now.
  void _removeAttachment(int index) {
    final removed = _attachments.items[index];
    setState(() => _attachments.removeAt(index));
    unawaited(ClipboardAttachments.release([removed]));
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

  /// Whether a slash in the box took the send, rather than the text going out.
  ///
  /// The text waits while the list is still looking, because `/ban` must not
  /// post just because Enter beat the answer. A slash no command matches is
  /// ordinary text, as it is in Discord.
  bool _runTypedCommand() {
    final commands = widget.slashCommands;
    if (commands == null || !commands.isSupported || !commands.isOpen) {
      return false;
    }
    if (commands.isLoading || commands.isSending) return true;
    final command = commands.commands.firstOrNull;
    if (command == null) return false;
    unawaited(
      SlashCommandList.run(
        context,
        controller: commands,
        command: command,
        onPicked: _clearComposer,
      ),
    );
    return true;
  }

  Future<void> _send() async {
    if (!_canSend || widget.isSending || _runTypedCommand()) return;
    final content = _boxContent;
    final send = widget.onSend(
      content.text,
      content.attachments,
      widget.replyTo?.id,
      content.silent,
    );
    // The box empties on the press, not on the answer, so whatever is typed
    // while the request runs belongs to the next message.
    _controller.clear();
    // Clearing from code does not reach the field's onChanged.
    widget.slashCommands?.close();
    setState(() {
      _hasContent = false;
      _charactersUsed = 0;
      _attachments.clear();
      _suppressNotifications = false;
    });
    _focusNode.requestFocus();
    // A failed message stays in the timeline with Retry, so the box does not
    // take it back, and a pasted picture stays on disk for the retry.
    if (await send) await ClipboardAttachments.release(content.attachments);
  }

  /// Sends the GIF straight away, as Discord's own client does: the picker is
  /// a send action, not a way to paste a link into a half-written message.
  Future<void> _sendGif(String url) async {
    if (widget.isSending || _isHeldBySlowmode) return;
    await widget.onSend(
      url,
      const [],
      widget.replyTo?.id,
      _suppressNotifications,
    );
  }

  void _insertText(String token) {
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
    widget.slashCommands?.syncComposer(next);
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
    if (widget.isSending || _isHeldBySlowmode) return;
    CreatePollDialog.show(context, onCreate: widget.onCreatePoll);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_gutter),
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
          // The switch lives in a closed menu, so its state shows here.
          if (_suppressNotifications)
            _composerNotice(
              key: const ValueKey('composer-silent-notice'),
              icon: FlucordIcons.silent,
              text: 'This message will send without notifications.',
            ),
          if (widget.replyTo != null) _replyBar(context),
          if (_attachments.isNotEmpty) ...[
            PendingAttachmentStrip(
              attachments: _attachments.items,
              enabled: !widget.isSending,
              onRemove: _removeAttachment,
              onToggleSpoiler: _toggleAttachmentSpoiler,
            ),
            const SizedBox(height: 6),
          ],
          if (_hasVoiceSession)
            _VoiceMessageComposerBar(
              levels: _voiceLevels,
              isRecording: _isRecordingVoice,
              onCancel: _isRecordingVoice ? _cancelVoiceMessage : null,
              onSend: _isRecordingVoice ? _stopAndSendVoiceMessage : null,
            )
          else
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): _send,
                const SingleActivator(LogicalKeyboardKey.numpadEnter): _send,
              },
              child: _fieldTakingPaste(
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
                  contextMenuBuilder: zoomedTextFieldMenu,
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
                  style: FlucordTextRole.body.style.copyWith(
                    color: context.surfaces.text,
                  ),
                  decoration:
                      recessedFieldDecoration(
                        context,
                        // Square top corners under the reply bar, so the two
                        // read as one surface.
                        borderRadius: widget.replyTo == null
                            ? FlucordRadius.medium
                            : const BorderRadius.vertical(
                                bottom: FlucordRadius.mediumCorner,
                              ),
                      ).copyWith(
                        hintText:
                            'Message ${widget.channelHintPrefix}${widget.channelName}',
                        hintStyle: FlucordTextRole.body.style.copyWith(
                          color: context.surfaces.captionText,
                        ),
                        // In a narrow composer a wrapped hint is what makes
                        // the box tall, and that takes the height from the
                        // timeline.
                        hintMaxLines: 1,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: _textInset,
                        ),
                        prefixIcon: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: _buttonInset,
                            end: _buttonGap,
                          ),
                          child: _composerMenu(),
                        ),
                        prefixIconConstraints: _buttonRow,
                        suffixIconConstraints: _buttonRow,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: _buttonGap,
                          children: [
                            EmojiPickerButton(
                              spaceName: widget.spaceName,
                              emojiSections: widget.emojiSections,
                              onSelected: _insertText,
                              favorites: widget.expressionFavorites,
                              dimension: FlucordIconButton.size,
                              iconSize: FlucordIconButton.iconSize,
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
                            if (widget.onSendStickers case final send?)
                              StickerPickerButton(
                                sections: widget.stickerSections,
                                isSending:
                                    widget.isSending || _isHeldBySlowmode,
                                onSend: send,
                                favorites: widget.expressionFavorites,
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
                            const SizedBox(width: _buttonInset - _buttonGap),
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

  Widget _fieldTakingPaste({required Widget child}) => Actions(
    actions: {PasteTextIntent: _pasteAction},
    child: _buildComposerAutocompletePortal(child: child),
  );

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
          style: FlucordTextRole.caption.style.copyWith(
            color: _isOverCharacterLimit
                ? Theme.of(context).colorScheme.error
                : context.surfaces.muted,
          ),
        ),
        if (_isOverCharacterLimit) ...[
          const SizedBox(width: 5),
          Text(
            'Your message is above the limit.',
            style: FlucordTextRole.caption.style.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    ),
  );

  /// The button at the start of the field: uploads, polls and silent send.
  ///
  /// Without `ATTACH_FILES` it holds no upload and stops looking like an
  /// attach button, while polls and silent send stay in reach.
  Widget _composerMenu() => PopupMenuButton<_ComposerMenuAction>(
    key: const ValueKey('composer-menu'),
    enabled: !widget.isSending,
    tooltip: 'More options',
    style: FlucordIconButton.squareStyle,
    iconSize: FlucordIconButton.iconSize,
    icon: FlucordIcon(
      widget.canAttachFiles ? FlucordIcons.attach : FlucordIcons.more,
    ),
    onSelected: (action) => switch (action) {
      _ComposerMenuAction.attach => unawaited(_pickAttachments()),
      _ComposerMenuAction.poll => _showPollDialog(),
      _ComposerMenuAction.silent => setState(
        () => _suppressNotifications = !_suppressNotifications,
      ),
    },
    itemBuilder: (_) => [
      if (widget.canAttachFiles)
        const FlucordMenuItem(
          key: ValueKey('add-attachment'),
          value: _ComposerMenuAction.attach,
          icon: FlucordIcons.upload,
          label: 'Add attachment',
        ),
      FlucordMenuItem(
        key: const ValueKey('create-poll'),
        value: _ComposerMenuAction.poll,
        // A poll is a message, so slowmode holds it like the rest.
        enabled: !_isHeldBySlowmode,
        icon: FlucordIcons.poll,
        label: 'Create poll',
      ),
      _suppressNotifications
          ? const FlucordMenuItem(
              key: ValueKey('send-silently'),
              value: _ComposerMenuAction.silent,
              icon: FlucordIcons.notifications,
              label: 'Send with notifications',
            )
          : const FlucordMenuItem(
              key: ValueKey('send-silently'),
              value: _ComposerMenuAction.silent,
              icon: FlucordIcons.silent,
              label: 'Send silently',
            ),
    ],
  );

  /// The last control in the composer's trailing cluster.
  Widget _trailingAction() {
    if (widget.isSending) {
      return const SizedBox.square(
        key: ValueKey('send-progress'),
        dimension: FlucordIconButton.size,
        child: Center(
          child: SizedBox.square(
            dimension: FlucordIconButton.iconSize,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_canSend) {
      return FlucordIconButton(
        key: const ValueKey('send-message'),
        onPressed: _send,
        icon: FlucordIcons.send,
        color: context.surfaces.accentIcon,
        tooltip: 'Send message',
      );
    }
    // A message that is over the limit keeps its send button, greyed out
    // beside the red count, rather than swapping to the recorder: the user
    // typed words, and the honest answer is that they are too many.
    if (_hasContent || _attachments.isNotEmpty) return _disabledSend;
    if (widget.voiceMessageRecorder != null &&
        widget.onSendVoiceMessage != null) {
      return FlucordIconButton(
        key: const ValueKey('record-voice-message'),
        onPressed: _canRecordVoice ? _startVoiceRecording : null,
        icon: FlucordIcons.mic,
        tooltip: 'Record voice message',
      );
    }
    return _disabledSend;
  }

  static const _disabledSend = FlucordIconButton(
    key: ValueKey('send-message'),
    onPressed: null,
    icon: FlucordIcons.send,
    tooltip: 'Send message',
  );

  Widget _replyBar(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.only(left: 12),
    decoration: BoxDecoration(
      color: context.surfaces.inset,
      border: Border(
        top: BorderSide(color: context.surfaces.border),
        left: BorderSide(color: context.surfaces.border),
        right: BorderSide(color: context.surfaces.border),
      ),
      borderRadius: const BorderRadius.vertical(
        top: FlucordRadius.mediumCorner,
      ),
    ),
    child: Row(
      children: [
        FlucordIcon(
          FlucordIcons.reply,
          size: 14,
          color: context.surfaces.muted,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Replying to ${widget.replyAuthorName ?? 'Unknown user'}',
            overflow: TextOverflow.ellipsis,
            style: FlucordTextRole.caption.style.copyWith(
              color: context.surfaces.bodyText,
            ),
          ),
        ),
        FlucordIconButton(
          onPressed: widget.onCancelReply,
          icon: FlucordIcons.clear,
          tooltip: 'Cancel reply',
        ),
        const SizedBox(width: _buttonInset),
      ],
    ),
  );
}

/// Takes Ctrl+V from the text field. [callingAction] is the field's own paste,
/// and it is only set while [invoke] runs, so it is passed on as a callback.
final class _PasteAction extends Action<PasteTextIntent> {
  _PasteAction(this._onPaste);

  final Future<void> Function(VoidCallback pasteText) _onPaste;

  @override
  Future<void> invoke(PasteTextIntent intent) {
    final fieldPaste = callingAction;
    return _onPaste(() => fieldPaste?.invoke(intent));
  }
}

enum _ComposerMenuAction { attach, poll, silent }

/// Stands in for the composer while the account has yet to agree to the
/// server's rules: Discord lets a pending member read, not talk.
/// [onReadRules] is null on a session that cannot show the rules.
class PendingMemberNotice extends StatelessWidget {
  const PendingMemberNotice({this.onReadRules, super.key});

  final VoidCallback? onReadRules;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('pending-member-notice'),
    constraints: const BoxConstraints(minHeight: 52),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: context.surfaces.surface,
      border: Border(top: BorderSide(color: context.surfaces.border)),
    ),
    child: Row(
      children: [
        FlucordIcon(
          FlucordIcons.readOnly,
          size: FlucordIconButton.iconSize,
          color: context.surfaces.muted,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Agree to this server\'s rules before you can talk here.',
            style: FlucordTextRole.caption.style.copyWith(
              color: context.surfaces.bodyText,
            ),
          ),
        ),
        if (onReadRules case final read?)
          FlucordButton(
            key: const ValueKey('pending-member-read-rules'),
            kind: FlucordButtonKind.primary,
            label: 'Read the rules',
            onPressed: read,
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
        FlucordIcon(
          FlucordIcons.readOnly,
          size: FlucordIconButton.iconSize,
          color: context.surfaces.muted,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'You do not have permission to send messages here.',
            style: FlucordTextRole.caption.style.copyWith(
              color: context.surfaces.bodyText,
            ),
          ),
        ),
      ],
    ),
  );
}
