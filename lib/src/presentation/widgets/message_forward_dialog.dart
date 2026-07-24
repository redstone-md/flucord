import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/message_forward_destination_catalog.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

typedef ForwardMessageCallback =
    Future<bool> Function(ChatMessage message, String targetChannelId);

class MessageForwardDialog extends StatefulWidget {
  const MessageForwardDialog({
    required this.message,
    required this.catalog,
    required this.onForward,
    super.key,
  });

  final ChatMessage message;
  final MessageForwardDestinationCatalog catalog;
  final ForwardMessageCallback onForward;

  static Future<bool> show(
    BuildContext context, {
    required ChatMessage message,
    required ChatWorkspace workspace,
    required ForwardMessageCallback onForward,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => MessageForwardDialog(
          message: message,
          catalog: MessageForwardDestinationCatalog.fromWorkspace(workspace),
          onForward: onForward,
        ),
      ) ??
      false;

  @override
  State<MessageForwardDialog> createState() => _MessageForwardDialogState();
}

class _MessageForwardDialogState extends State<MessageForwardDialog> {
  final TextEditingController _queryController = TextEditingController();
  late List<MessageForwardDestination> _results;
  MessageForwardDestination? _selected;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _results = widget.catalog.destinations;
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableHeight = MediaQuery.sizeOf(context).height - 48;
    return Dialog(
      key: const ValueKey('message-forward-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: context.surfaces.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: math.min(560, availableHeight),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            Divider(height: 1, color: context.surfaces.border),
            Flexible(child: _destinationList(context)),
            if (_error case final error?) _errorLine(context, error),
            Divider(height: 1, color: context.surfaces.border),
            _actions(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Forward message',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('message-forward-search'),
          controller: _queryController,
          autofocus: true,
          enabled: !_isSubmitting,
          onChanged: _search,
          decoration: const InputDecoration(
            hintText: 'Search channels and conversations',
            prefixIcon: Icon(Icons.search, size: 19),
            isDense: true,
          ),
        ),
      ],
    ),
  );

  Widget _destinationList(BuildContext context) {
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No matching text channels or conversations.',
            key: const ValueKey('message-forward-empty'),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.surfaces.muted, fontSize: 12),
          ),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('message-forward-destinations'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      shrinkWrap: true,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final destination = _results[index];
        return _DestinationRow(
          destination: destination,
          selected: destination.channelId == _selected?.channelId,
          enabled: !_isSubmitting,
          onPressed: () => setState(() {
            _selected = destination;
            _error = null;
          }),
        );
      },
    );
  }

  Widget _errorLine(BuildContext context, String error) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
    child: Text(
      error,
      key: const ValueKey('message-forward-error'),
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: 11,
      ),
    ),
  );

  Widget _actions(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey('message-forward-submit'),
          onPressed: _selected == null || _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Forward'),
        ),
      ],
    ),
  );

  void _search(String query) {
    setState(() {
      _results = widget.catalog.search(query);
      if (!_results.any(
        (destination) => destination.channelId == _selected?.channelId,
      )) {
        _selected = null;
      }
      _error = null;
    });
  }

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final succeeded = await widget.onForward(
      widget.message,
      selected.channelId,
    );
    if (!mounted) return;
    if (succeeded) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _isSubmitting = false;
      _error = 'The message could not be forwarded to this destination.';
    });
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.destination,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final MessageForwardDestination destination;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? FlucordColors.brand.withValues(alpha: 0.16)
        : Colors.transparent,
    borderRadius: BorderRadius.circular(4),
    child: InkWell(
      key: ValueKey('message-forward-${destination.channelId}'),
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            const SizedBox(width: 10),
            Icon(_icon, size: 18, color: context.surfaces.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    destination.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 17, color: FlucordColors.brand),
            const SizedBox(width: 10),
          ],
        ),
      ),
    ),
  );

  IconData get _icon => switch (destination.kind) {
    MessageForwardDestinationKind.directMessage => Icons.alternate_email,
    MessageForwardDestinationKind.textChannel => Icons.tag,
    MessageForwardDestinationKind.thread => Icons.forum_outlined,
  };
}
