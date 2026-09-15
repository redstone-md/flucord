import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/guild_expression_errors.dart';
import '../../theme/flucord_theme.dart';
import '../expression_file_picker.dart';
import 'guild_settings_controls.dart';

/// The expressions page: the server's emoji, stickers and soundboard sounds,
/// each with an upload and a delete.
///
/// Every action is gated on the manage-expressions permission, and the
/// numbered refusals a full server answers with arrive as the sentences the
/// error classes write, in the banner the whole window shares.
class GuildSettingsExpressionsSection extends StatefulWidget {
  const GuildSettingsExpressionsSection({
    required this.controller,
    this.filePicker = const NativeExpressionFilePicker(),
    super.key,
  });

  final GuildSettingsController controller;
  final ExpressionFilePicker filePicker;

  @override
  State<GuildSettingsExpressionsSection> createState() =>
      _GuildSettingsExpressionsSectionState();
}

class _GuildSettingsExpressionsSectionState
    extends State<GuildSettingsExpressionsSection> {
  /// Why the last chosen file was refused, or null. The refusal happens
  /// before anything is sent, so it is the page's own message rather than
  /// the window's failed-write banner.
  String? _fileError;

  Future<ExpressionFileSelection?> _pick(ExpressionKind kind) async {
    setState(() => _fileError = null);
    try {
      return await widget.filePicker.pick(kind);
    } on ExpressionFileRejected catch (rejection) {
      if (mounted) setState(() => _fileError = rejection.message);
      return null;
    } on Object {
      if (mounted) {
        setState(() => _fileError = 'That file could not be read.');
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return GuildSettingsPanel(
      title: 'Expressions',
      subtitle:
          'The emoji, stickers and sounds everybody on this server '
          'shares.',
      children: [
        // A full server or an oversized file is said out loud rather than
        // as a generic failure: the refusal's own sentence is the message.
        if (controller.actionError is GuildExpressionLimitReached)
          GuildSettingsActionError(
            error: controller.actionError,
            message: controller.actionError.toString(),
          )
        else if (_fileError != null)
          GuildSettingsActionError(error: _fileError, message: _fileError)
        else
          GuildSettingsActionError(error: controller.actionError),
        _ExpressionGroup(
          heading: 'Emoji',
          uploadLabel: 'Upload emoji',
          uploadKey: 'guild-expressions-upload-emoji',
          emptyKey: 'guild-expressions-emoji-empty',
          emptyMessage: 'This server has no custom emoji yet.',
          rows: [
            for (final emoji in controller.emoji)
              GuildSettingsRow(
                key: ValueKey('guild-expression-emoji-${emoji.id}'),
                leading: const Icon(Icons.emoji_emotions, size: 16),
                title: ':${emoji.name}:',
                subtitle: emoji.animated ? 'Animated' : null,
                trailing: _DeleteButton(
                  keyText: 'guild-expression-emoji-delete-${emoji.id}',
                  onPressed: () => unawaited(controller.deleteEmoji(emoji)),
                ),
              ),
          ],
          onUpload: () => unawaited(_uploadEmoji(context)),
        ),
        const SizedBox(height: 16),
        _ExpressionGroup(
          heading: 'Stickers',
          uploadLabel: 'Upload sticker',
          uploadKey: 'guild-expressions-upload-sticker',
          emptyKey: 'guild-expressions-sticker-empty',
          emptyMessage: 'This server has no stickers yet.',
          rows: [
            for (final sticker in controller.stickers)
              GuildSettingsRow(
                key: ValueKey('guild-expression-sticker-${sticker.id}'),
                leading: const Icon(Icons.sticky_note_2_outlined, size: 16),
                title: sticker.name,
                subtitle: _stickerFormatLabel(sticker),
                trailing: _DeleteButton(
                  keyText: 'guild-expression-sticker-delete-${sticker.id}',
                  onPressed: () => unawaited(controller.deleteSticker(sticker)),
                ),
              ),
          ],
          onUpload: () => unawaited(_uploadSticker(context)),
        ),
        const SizedBox(height: 16),
        _ExpressionGroup(
          heading: 'Sounds',
          uploadLabel: 'Upload sound',
          uploadKey: 'guild-expressions-upload-sound',
          emptyKey: 'guild-expressions-sound-empty',
          emptyMessage: 'This server has no sounds yet.',
          rows: [
            for (final sound in controller.sounds)
              GuildSettingsRow(
                key: ValueKey('guild-expression-sound-${sound.id}'),
                leading: const Icon(Icons.music_note_outlined, size: 16),
                title: sound.name,
                subtitle: 'Volume ${(sound.volume * 100).round()}%',
                trailing: _DeleteButton(
                  keyText: 'guild-expression-sound-delete-${sound.id}',
                  onPressed: () => unawaited(controller.deleteSound(sound)),
                ),
              ),
          ],
          onUpload: () => unawaited(_uploadSound(context)),
        ),
      ],
    );
  }

  Future<void> _uploadEmoji(BuildContext context) async {
    final selection = await _pick(ExpressionKind.emoji);
    if (selection == null) return;
    if (!context.mounted) return;
    final name = await _NameDialog.show(
      context,
      title: 'Name this emoji',
      hint: 'Emoji names are 2 to 32 characters.',
    );
    if (name == null || name.isEmpty) return;
    await widget.controller.uploadEmoji(name: name, dataUri: selection.dataUri);
  }

  Future<void> _uploadSticker(BuildContext context) async {
    final selection = await _pick(ExpressionKind.sticker);
    if (selection == null) return;
    if (!context.mounted) return;
    final name = await _NameDialog.show(
      context,
      title: 'Name this sticker',
      hint: 'Sticker names are 2 to 30 characters.',
    );
    if (name == null || name.isEmpty) return;
    await widget.controller.uploadSticker(
      name: name,
      description: '',
      // The route takes the name of an emoji that suits the sticker. A name
      // a person just typed is what Discord's own client files it under when
      // nobody picks one.
      tags: name,
      dataUri: selection.dataUri,
    );
  }

  Future<void> _uploadSound(BuildContext context) async {
    final selection = await _pick(ExpressionKind.sound);
    if (selection == null) return;
    if (!context.mounted) return;
    final answer = await _SoundDialog.show(context);
    if (answer == null || answer.name.isEmpty) return;
    await widget.controller.uploadSound(
      name: answer.name,
      volume: answer.volume,
      dataUri: selection.dataUri,
    );
  }

  /// The file's format as the server names it, so a person sees what they
  /// are uploading before they send it.
  static String _stickerFormatLabel(GuildSticker sticker) =>
      switch (sticker.item.format) {
        StickerFormat.png => 'PNG',
        StickerFormat.apng => 'APNG',
        StickerFormat.lottie => 'Lottie',
        StickerFormat.gif => 'GIF',
        StickerFormat.unknown => 'Unknown format',
      };
}

/// One titled group of rows with its upload button, so the three lists read
/// the same without sharing a widget nobody else needs.
class _ExpressionGroup extends StatelessWidget {
  const _ExpressionGroup({
    required this.heading,
    required this.uploadLabel,
    required this.uploadKey,
    required this.emptyKey,
    required this.emptyMessage,
    required this.rows,
    required this.onUpload,
  });

  final String heading;
  final String uploadLabel;
  final String uploadKey;
  final String emptyKey;
  final String emptyMessage;
  final List<Widget> rows;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        heading.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w700,
          color: context.surfaces.muted,
        ),
      ),
      const SizedBox(height: 6),
      if (rows.isEmpty)
        Padding(
          key: ValueKey(emptyKey),
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            emptyMessage,
            style: TextStyle(fontSize: 12, color: context.surfaces.muted),
          ),
        )
      else
        ...rows,
      FilledButton.tonal(
        key: ValueKey(uploadKey),
        onPressed: onUpload,
        child: Text(uploadLabel),
      ),
    ],
  );
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.keyText, required this.onPressed});

  final String keyText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    key: ValueKey(keyText),
    onPressed: onPressed,
    child: const Text('Delete'),
  );
}

/// Asks for the one text a name needs. Returns null when the person cancels.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String hint,
  }) => showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, hint: hint),
  );

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('guild-expression-name-field'),
      controller: _name,
      autofocus: true,
      decoration: InputDecoration(hintText: widget.hint, isDense: true),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('guild-expression-name-confirm'),
        onPressed: () => Navigator.of(context).pop(_name.text.trim()),
        child: const Text('Upload'),
      ),
    ],
  );
}

/// Asks for a sound's name and volume together, because Discord asks for both
/// on the same form.
class _SoundDialog extends StatefulWidget {
  const _SoundDialog();

  static Future<({String name, double volume})?> show(BuildContext context) =>
      showDialog<({String name, double volume})>(
        context: context,
        builder: (_) => const _SoundDialog(),
      );

  @override
  State<_SoundDialog> createState() => _SoundDialogState();
}

class _SoundDialogState extends State<_SoundDialog> {
  final TextEditingController _name = TextEditingController();
  double _volume = 1;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Name this sound'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('guild-expression-name-field'),
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Sound names are 2 to 32 characters.',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Text('Volume ${(_volume * 100).round()}%'),
        Slider(
          key: const ValueKey('guild-expression-sound-volume'),
          min: 0,
          max: 1,
          value: _volume,
          onChanged: (value) => setState(() => _volume = value),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('guild-expression-sound-name-confirm'),
        onPressed: () => Navigator.of(
          context,
        ).pop((name: _name.text.trim(), volume: _volume)),
        child: const Text('Upload'),
      ),
    ],
  );
}
