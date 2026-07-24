import 'package:flutter/material.dart';

import '../../application/connection_controller.dart';
import '../../application/discord_oauth_controller.dart';
import '../../theme/flucord_theme.dart';

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({
    required this.controller,
    required this.oauthController,
    super.key,
  });

  final ConnectionController controller;
  final DiscordOAuthController oauthController;

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final TextEditingController _tokenController = TextEditingController();
  bool _remember = true;
  bool _obscureToken = true;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _connectToken() async {
    final connected = await widget.controller.connectWithBotToken(
      token: _tokenController.text,
      remember: _remember,
    );
    if (connected && mounted) Navigator.of(context).pop();
  }

  Future<void> _connectSaved() async {
    final connected = await widget.controller.connectSavedCredential();
    if (connected && mounted) Navigator.of(context).pop();
  }

  Future<void> _useLocal() async {
    await widget.controller.useLocalWorkspace();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _linkAccount() => widget.oauthController.authorize();

  Future<void> _unlinkAccount() => widget.oauthController.unlink();

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height - 48;
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: context.surfaces.border),
      ),
      backgroundColor: context.surfaces.raised,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => ListenableBuilder(
            listenable: widget.oauthController,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DialogHeader(onClose: () => Navigator.of(context).pop()),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CurrentConnection(controller: widget.controller),
                        Divider(height: 1, color: context.surfaces.border),
                        _OAuthConnectionSection(
                          controller: widget.oauthController,
                          onLink: _linkAccount,
                          onUnlink: _unlinkAccount,
                        ),
                        Divider(height: 1, color: context.surfaces.border),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Discord bot',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Use an application bot token. Personal account tokens are not accepted.',
                                style: TextStyle(
                                  color: context.surfaces.muted,
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                key: const ValueKey('discord-bot-token'),
                                controller: _tokenController,
                                obscureText: _obscureToken,
                                enabled: !widget.controller.isBusy,
                                onSubmitted: (_) => _connectToken(),
                                decoration: InputDecoration(
                                  labelText: 'Bot token',
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                      () => _obscureToken = !_obscureToken,
                                    ),
                                    icon: Icon(
                                      _obscureToken
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    tooltip: _obscureToken
                                        ? 'Show token'
                                        : 'Hide token',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              CheckboxListTile(
                                value: _remember,
                                onChanged: widget.controller.isBusy
                                    ? null
                                    : (value) => setState(
                                        () => _remember = value ?? false,
                                      ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: const Text(
                                  'Remember in the system credential vault',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              if (widget.controller.errorMessage
                                  case final error?) ...[
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      size: 16,
                                      color: FlucordColors.danger,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        error,
                                        style: const TextStyle(
                                          color: FlucordColors.danger,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  if (widget.controller.hasSavedCredential) ...[
                                    TextButton.icon(
                                      onPressed: widget.controller.isBusy
                                          ? null
                                          : _connectSaved,
                                      icon: const Icon(Icons.key, size: 16),
                                      label: const Text('Use saved token'),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  const Spacer(),
                                  OutlinedButton(
                                    onPressed: widget.controller.isBusy
                                        ? null
                                        : _useLocal,
                                    child: const Text('Use local'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    key: const ValueKey('connect-discord'),
                                    onPressed: widget.controller.isBusy
                                        ? null
                                        : _connectToken,
                                    icon: widget.controller.isBusy
                                        ? const SizedBox.square(
                                            dimension: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.link, size: 16),
                                    label: Text(
                                      widget.controller.isBusy
                                          ? 'Connecting'
                                          : 'Connect',
                                    ),
                                  ),
                                ],
                              ),
                              if (widget.controller.hasSavedCredential) ...[
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: widget.controller.isBusy
                                        ? null
                                        : widget
                                              .controller
                                              .forgetSavedCredential,
                                    child: const Text(
                                      'Forget saved credential',
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OAuthConnectionSection extends StatelessWidget {
  const _OAuthConnectionSection({
    required this.controller,
    required this.onLink,
    required this.onUnlink,
  });

  final DiscordOAuthController controller;
  final Future<void> Function() onLink;
  final Future<void> Function() onUnlink;

  @override
  Widget build(BuildContext context) {
    final account = controller.account;
    final linked = controller.state == DiscordOAuthLinkState.linked;
    final statusColor = linked
        ? FlucordColors.success
        : controller.state == DiscordOAuthLinkState.failure
        ? FlucordColors.danger
        : context.surfaces.muted;
    final status = switch (controller.state) {
      DiscordOAuthLinkState.unavailable =>
        'Account linking is unavailable in this build.',
      DiscordOAuthLinkState.restoring => 'Restoring saved authorization…',
      DiscordOAuthLinkState.authorizing =>
        'Waiting for Discord in your system browser…',
      DiscordOAuthLinkState.linked =>
        '${account?.displayName ?? 'Discord account'} · '
            '${account?.guildCount ?? 0} servers',
      DiscordOAuthLinkState.failure =>
        controller.errorMessage ?? 'Account linking failed.',
      DiscordOAuthLinkState.idle => 'No Discord account linked.',
    };
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Discord account',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'OAuth links your profile and server directory. Discord does not grant third-party access to channel messages.',
            style: TextStyle(
              color: context.surfaces.muted,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaces.inset,
              border: Border.all(color: context.surfaces.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  linked ? Icons.verified_user_outlined : Icons.person_outline,
                  size: 20,
                  color: statusColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status,
                    key: const ValueKey('discord-oauth-status'),
                    style: TextStyle(
                      color: controller.state == DiscordOAuthLinkState.failure
                          ? FlucordColors.danger
                          : null,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (linked)
                  TextButton(
                    key: const ValueKey('unlink-discord-account'),
                    onPressed: controller.isBusy ? null : onUnlink,
                    child: const Text('Unlink'),
                  )
                else
                  FilledButton.icon(
                    key: const ValueKey('link-discord-account'),
                    onPressed: !controller.isConfigured || controller.isBusy
                        ? null
                        : onLink,
                    icon: controller.isBusy
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Link account'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 8),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Connections',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close),
              tooltip: 'Close',
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentConnection extends StatelessWidget {
  const _CurrentConnection({required this.controller});

  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    final connected = controller.mode == SessionMode.discord;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: connected ? FlucordColors.success : context.surfaces.muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              connected
                  ? '${controller.activeSession?.displayName ?? 'Discord'} connected'
                  : 'Local workspace active',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
