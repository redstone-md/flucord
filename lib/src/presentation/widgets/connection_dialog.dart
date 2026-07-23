import 'package:flutter/material.dart';

import '../../application/connection_controller.dart';
import '../../theme/flucord_theme.dart';

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({required this.controller, super.key});

  final ConnectionController controller;

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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: context.surfaces.border),
      ),
      backgroundColor: context.surfaces.raised,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DialogHeader(onClose: () => Navigator.of(context).pop()),
              _CurrentConnection(controller: widget.controller),
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
                          onPressed: () =>
                              setState(() => _obscureToken = !_obscureToken),
                          icon: Icon(
                            _obscureToken
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscureToken ? 'Show token' : 'Hide token',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _remember,
                      onChanged: widget.controller.isBusy
                          ? null
                          : (value) =>
                                setState(() => _remember = value ?? false),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Remember in Windows Credential Manager',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    if (widget.controller.errorMessage case final error?) ...[
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
                            widget.controller.isBusy ? 'Connecting' : 'Connect',
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
                              : widget.controller.forgetSavedCredential,
                          child: const Text('Forget saved credential'),
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
    final connected = controller.mode == SessionMode.discordBot;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: connected ? FlucordColors.signal : context.surfaces.muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              connected ? 'Discord bot connected' : 'Local workspace active',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
