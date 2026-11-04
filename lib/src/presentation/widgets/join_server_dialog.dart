import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/chat_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/channel_link.dart';
import '../../domain/guild_management.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'remote_identity_image.dart';
import 'flucord_controls.dart';
import 'flucord_dialog.dart';

/// Discord's join-a-server dialog: an invite link or code in, a preview of
/// the server out, and a join that lands the user inside it.
class JoinServerDialog extends StatefulWidget {
  const JoinServerDialog({
    required this.chat,
    required this.workspace,
    this.initialCode,
    super.key,
  });

  final ChatController chat;
  final ChatWorkspace workspace;

  /// A code an invite link already carried when the dialog was opened, from
  /// a link tapped inside a message.
  final String? initialCode;

  @override
  State<JoinServerDialog> createState() => _JoinServerDialogState();
}

enum _InviteResolution { idle, loading, preview, refused }

class _JoinServerDialogState extends State<JoinServerDialog> {
  final TextEditingController _controller = TextEditingController();
  _InviteResolution _resolution = _InviteResolution.idle;
  InvitePreview? _preview;
  String? _message;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    final code = widget.initialCode;
    if (code != null && code.isNotEmpty) {
      _controller.text = code;
      unawaited(_resolve());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The preview answers "already in this server" without asking Discord to
  /// join it a second time, which is the one refusal the join would rather
  /// report before it is attempted.
  bool get _alreadyInServer =>
      _preview?.guildId != null &&
      widget.workspace.spaceOrNull(_preview!.guildId!) != null;

  Future<void> _resolve() async {
    final code = InviteLink.tryParseCode(_controller.text);
    if (code == null) {
      setState(() {
        _resolution = _InviteResolution.refused;
        _message = 'That does not look like an invite link or code.';
      });
      return;
    }
    setState(() => _resolution = _InviteResolution.loading);
    try {
      final preview = await widget.chat.previewInvite(code);
      if (!mounted) return;
      setState(() {
        _resolution = _InviteResolution.preview;
        _preview = preview;
        _message = null;
      });
    } on GuildAccessException catch (error) {
      if (!mounted) return;
      setState(() {
        _resolution = _InviteResolution.refused;
        _message = error.message;
      });
    }
  }

  Future<void> _join() async {
    final code = _preview?.code;
    if (code == null || _joining) return;
    setState(() => _joining = true);
    try {
      final spaceId = await widget.chat.joinGuild(code);
      if (!mounted) return;
      if (spaceId == null) {
        setState(() {
          _joining = false;
          _resolution = _InviteResolution.refused;
          _message = widget.chat.guildAccessError ?? 'The join was refused.';
        });
        return;
      }
      Navigator.of(context).pop(spaceId);
    } on GuildAccessException catch (error) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _resolution = _InviteResolution.refused;
        _message = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => FlucordDialog(
    key: const ValueKey('join-server-dialog'),
    title: const Text('Join a server'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlucordTextField(
            fieldKey: const ValueKey('join-server-invite-field'),
            label: 'Invite link or code',
            hintText: 'https://discord.gg/ or a code',
            controller: _controller,
            autofocus: true,
            enabled: !_joining,
            onChanged: (_) {
              // Any change to the text rebuilds: the submit button's action
              // reads the field, and a stale build would keep the button
              // disabled after text was typed.
              setState(() {
                _resolution = _InviteResolution.idle;
                _preview = null;
                _message = null;
              });
            },
            onSubmitted: (_) => unawaited(_resolve()),
          ),
          const SizedBox(height: 14),
          switch (_resolution) {
            _InviteResolution.idle => const SizedBox.shrink(),
            _InviteResolution.loading || _InviteResolution.refused => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _resolution == _InviteResolution.loading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Text(
                      _message ?? '',
                      key: const ValueKey('join-server-error'),
                      style: FlucordTextRole.caption.style.copyWith(
                        color: context.surfaces.errorText,
                      ),
                    ),
            ),
            _InviteResolution.preview => _previewCard(context),
          },
        ],
      ),
    ),
    confirm: FlucordDialogConfirm(
      key: const ValueKey('join-server-submit'),
      label: _buttonLabel,
      onPressed: _buttonAction,
    ),
  );

  /// The one button resolves first and joins once the preview is on screen,
  /// which is what Discord's own dialog does: the user sees the server
  /// before anything is joined.
  VoidCallback? get _buttonAction {
    if (_joining || _controller.text.trim().isEmpty) return null;
    if (_resolution == _InviteResolution.preview) {
      return _alreadyInServer ? null : () => unawaited(_join());
    }
    return () => unawaited(_resolve());
  }

  String get _buttonLabel {
    if (_joining) return 'Joining';
    if (_resolution == _InviteResolution.loading) return 'Checking';
    return _resolution == _InviteResolution.preview ? 'Join' : 'Check';
  }

  /// The preview a user reads before joining: icon, name, member count, and
  /// the channel the invite lands in.
  Widget _previewCard(BuildContext context) => Container(
    key: const ValueKey('join-server-preview'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.surfaces.inset,
      borderRadius: FlucordRadius.medium,
      border: Border.all(color: context.surfaces.border),
    ),
    child: Row(
      children: [
        SizedBox(
          key: const ValueKey('join-server-preview-icon'),
          width: 48,
          height: 48,
          child: RemoteIdentityImage(
            url: _preview?.iconUrl,
            fallback: _previewMonogram(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _preview?.name ?? '',
                key: const ValueKey('join-server-preview-name'),
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.heading.style.copyWith(
                  color: context.surfaces.text,
                ),
              ),
              if (_preview?.approximateMemberCount case final count?)
                Text(
                  '$count members',
                  style: FlucordTextRole.caption.style.copyWith(
                    color: context.surfaces.muted,
                  ),
                ),
              if (_alreadyInServer)
                Text(
                  'You are already in this server.',
                  key: const ValueKey('join-server-already-joined'),
                  style: FlucordTextRole.caption.style.copyWith(
                    color: context.surfaces.muted,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  /// What the icon column shows when the server has no icon: the same
  /// monogram the rail would draw for it.
  Widget _previewMonogram(BuildContext context) {
    final name = _preview?.name ?? '?';
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.surfaces.control,
        shape: BoxShape.circle,
      ),
      child: Text(
        name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase(),
        style: FlucordTextRole.label.style.copyWith(
          color: context.surfaces.text,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Opens the join dialog for [code], which may be null when the user opened
/// the add-server surface by hand. Answers the joined space's id.
Future<String?> showJoinServerDialog(
  BuildContext context, {
  required ChatController chat,
  String? code,
}) => showDialog<String>(
  context: context,
  builder: (_) => JoinServerDialog(
    chat: chat,
    workspace: chat.workspace!,
    initialCode: code,
  ),
);
