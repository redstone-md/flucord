import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/server_profile_controller.dart';
import '../../data/discord/discord_cdn.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_type.dart';
import '../profile_image_picker.dart';
import 'flucord_dialog.dart';
import 'user_profile_controls.dart';

/// Opens Edit server profile: this account's nickname, avatar, banner and
/// bio in [space] only.
///
/// [canChangeNickname] is CHANGE_NICKNAME there. [hasServerProfiles] is
/// whether the account's Nitro covers per-server avatars, banners and bios;
/// without it those fields are not shown, since Discord would refuse them.
/// The caller owns [controller] and disposes it after the dialog closes.
Future<void> showServerProfileDialog(
  BuildContext context, {
  required CommunitySpace space,
  required Member self,
  required ServerProfileController controller,
  required bool canChangeNickname,
  required bool hasServerProfiles,
  ProfileImagePicker imagePicker = const NativeProfileImagePicker(),
}) => showDialog<void>(
  context: context,
  builder: (_) => _ServerProfileDialog(
    space: space,
    self: self,
    controller: controller,
    canChangeNickname: canChangeNickname,
    hasServerProfiles: hasServerProfiles,
    imagePicker: imagePicker,
  ),
);

class _ServerProfileDialog extends StatefulWidget {
  const _ServerProfileDialog({
    required this.space,
    required this.self,
    required this.controller,
    required this.canChangeNickname,
    required this.hasServerProfiles,
    required this.imagePicker,
  });

  final CommunitySpace space;
  final Member self;
  final ServerProfileController controller;
  final bool canChangeNickname;
  final bool hasServerProfiles;
  final ProfileImagePicker imagePicker;

  @override
  State<_ServerProfileDialog> createState() => _ServerProfileDialogState();
}

class _ServerProfileDialogState extends State<_ServerProfileDialog> {
  final TextEditingController _nickname = TextEditingController();
  final TextEditingController _bio = TextEditingController();
  bool _filled = false;
  String? _pickerError;

  ServerProfileController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _nickname.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// Fills the fields once, when the first read answers.
  void _onChange() {
    final profile = _controller.profile;
    if (!_filled && profile != null) {
      _filled = true;
      _nickname.text = profile.nickname ?? '';
      _bio.text = profile.bio;
    }
    setState(() {});
  }

  Future<void> _save() async {
    final saved = await _controller.save();
    if (saved && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => FlucordDialog(
    key: const ValueKey('server-profile-dialog'),
    title: const Text('Edit server profile'),
    description: 'How you show up in ${widget.space.name}, and only there.',
    maxWidth: 480,
    content: SizedBox(width: 420, child: _body(context)),
    confirm: FlucordDialogConfirm(
      key: const ValueKey('server-profile-save'),
      label: 'Save',
      onPressed: _controller.hasChanges && !_controller.isSaving
          ? () => unawaited(_save())
          : null,
    ),
  );

  Widget _body(BuildContext context) {
    final profile = _controller.profile;
    if (profile == null) {
      return _controller.loadError == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _error(context, 'Discord did not return your server profile.');
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.canChangeNickname)
          ProfileField(
            label: 'Nickname',
            hint: widget.self.displayName,
            helper: 'Leave empty to use your own name.',
            maxLength: 32,
            controller: _nickname,
            fieldKey: const ValueKey('server-profile-nickname'),
            onChanged: _controller.editNickname,
          ),
        if (widget.hasServerProfiles) ...[
          ProfileAvatarRow(
            url: _avatarUrl(),
            monogram: widget.self.initials,
            onPick: () => unawaited(_pick(_controller.editAvatar)),
            onRemove: profile.avatarHash == null
                ? null
                : () => _controller.editAvatar(null),
          ),
          const SizedBox(height: 16),
          ProfileImageButtons(
            label: 'banner',
            onPick: () => unawaited(_pick(_controller.editBanner)),
            onRemove: profile.bannerHash == null
                ? null
                : () => _controller.editBanner(null),
          ),
          if (_pickerError case final message?) _error(context, message),
          const SizedBox(height: 16),
          ProfileField(
            label: 'About me',
            maxLength: 190,
            maxLines: 4,
            controller: _bio,
            fieldKey: const ValueKey('server-profile-bio'),
            onChanged: _controller.editBio,
          ),
        ],
        if (_controller.refusal case final refusal?) _error(context, refusal),
      ],
    );
  }

  /// The avatar about to be saved, else the one set for this server, else
  /// the account's own.
  String? _avatarUrl() {
    final pending = _controller.pendingAvatar;
    if (pending.dataUri case final staged?) return staged;
    final hash = pending.isUntouched ? _controller.profile?.avatarHash : null;
    final id = widget.self.id;
    return DiscordCdn.guildMemberAvatar(widget.space.id, id, hash) ??
        widget.self.avatarUrl;
  }

  Future<void> _pick(void Function(String dataUri) stage) async {
    setState(() => _pickerError = null);
    try {
      final selection = await widget.imagePicker.pick();
      if (selection != null) stage(selection.dataUri);
    } on ProfileImageRejected catch (rejection) {
      if (mounted) setState(() => _pickerError = rejection.message);
    } on Object {
      if (mounted) {
        setState(() => _pickerError = 'That image could not be read.');
      }
    }
  }

  static Widget _error(BuildContext context, String message) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      message,
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: FlucordType.caption,
      ),
    ),
  );
}
