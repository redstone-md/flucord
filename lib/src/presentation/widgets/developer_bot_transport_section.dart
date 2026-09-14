import 'package:flutter/material.dart';

import '../../application/connection_controller.dart';
import '../../theme/flucord_theme.dart';

final class DeveloperBotTransportSection extends StatefulWidget {
  const DeveloperBotTransportSection({
    required this.controller,
    required this.onSessionChanged,
    super.key,
  });

  final ConnectionController controller;
  final VoidCallback onSessionChanged;

  @override
  State<DeveloperBotTransportSection> createState() =>
      _DeveloperBotTransportSectionState();
}

final class _DeveloperBotTransportSectionState
    extends State<DeveloperBotTransportSection> {
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
    if (connected && mounted) widget.onSessionChanged();
  }

  Future<void> _connectSaved() async {
    final connected = await widget.controller.connectSavedCredential();
    if (connected && mounted) widget.onSessionChanged();
  }

  Future<void> _disconnect() async {
    await widget.controller.disconnect();
    if (mounted) widget.onSessionChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const ValueKey('developer-bot-transport'),
      initiallyExpanded: false,
      tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      title: const Text(
        'Developer bot transport',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'Optional application-bot workspace. This is not your Discord account.',
        style: TextStyle(
          color: context.surfaces.muted,
          fontSize: 10,
          height: 1.3,
        ),
      ),
      children: [
        _TransportStatus(controller: widget.controller),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('discord-bot-token'),
          controller: _tokenController,
          obscureText: _obscureToken,
          enabled: !widget.controller.isBusy,
          onSubmitted: (_) => _connectToken(),
          decoration: InputDecoration(
            labelText: 'Application bot token',
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscureToken = !_obscureToken),
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
              : (value) => setState(() => _remember = value ?? false),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Remember in the system credential vault',
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
                onPressed: widget.controller.isBusy ? null : _connectSaved,
                icon: const Icon(Icons.key, size: 16),
                label: const Text('Use saved token'),
              ),
              const SizedBox(width: 4),
            ],
            const Spacer(),
            if (widget.controller.mode != SessionMode.disconnected) ...[
              OutlinedButton(
                onPressed: widget.controller.isBusy ? null : _disconnect,
                child: const Text('Disconnect'),
              ),
              const SizedBox(width: 8),
            ],
            FilledButton.icon(
              key: const ValueKey('connect-discord-bot'),
              onPressed: widget.controller.isBusy ? null : _connectToken,
              icon: widget.controller.isBusy
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.developer_mode_outlined, size: 16),
              label: Text(
                widget.controller.isBusy ? 'Connecting' : 'Connect bot',
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
    );
  }
}

final class _TransportStatus extends StatelessWidget {
  const _TransportStatus({required this.controller});

  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (controller.mode) {
      SessionMode.disconnected => (
        'No developer transport connected',
        context.surfaces.muted,
      ),
      SessionMode.demo => (
        'Demo workspace active',
        Theme.of(context).colorScheme.primary,
      ),
      SessionMode.discord => (
        '${controller.activeSession?.displayName ?? 'Discord bot'} connected',
        FlucordColors.success,
      ),
    };
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
      ],
    );
  }
}
